const std = @import("std");
const utils = @import("../utils.zig");
const report = @import("../models/report.zig");

pub fn collectLogInfo(allocator: std.mem.Allocator) ?report.LogInfo {
    if (!utils.commandExists("journalctl")) {
        return report.LogInfo{
            .available = false,
            .stats = report.LogStats{},
        };
    }

    var stats = report.LogStats{};

    // Get errors and above with JSON output
    const output = utils.runCommand(allocator, &[_][]const u8{
        "journalctl",
        "--since",
        "24 hours ago",
        "-p",
        "err..emerg",
        "--no-pager",
        "-o",
        "json",
    }) catch "";

    var error_patterns = std.ArrayList(report.ErrorPattern).empty;
    var pattern_counts = std.StringHashMap(i32).init(allocator);
    defer pattern_counts.deinit();

    if (output.len > 0) {
        var lines = std.mem.splitScalar(u8, output, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;

            // Parse JSON entry
            const parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
            defer parsed.deinit();

            const obj = parsed.value.object;

            // Get priority
            if (obj.get("PRIORITY")) |priority_val| {
                const priority_str = switch (priority_val) {
                    .string => |s| s,
                    .integer => |i| blk: {
                        var buf: [8]u8 = undefined;
                        break :blk std.fmt.bufPrint(&buf, "{d}", .{i}) catch "3";
                    },
                    else => "3",
                };
                // Priority: 0=emerg, 1=alert, 2=crit, 3=err, 4=warning
                if (std.mem.eql(u8, priority_str, "0") or
                    std.mem.eql(u8, priority_str, "1") or
                    std.mem.eql(u8, priority_str, "2"))
                {
                    stats.critical_count += 1;
                } else if (std.mem.eql(u8, priority_str, "3")) {
                    stats.error_count += 1;
                } else if (std.mem.eql(u8, priority_str, "4")) {
                    stats.warning_count += 1;
                }
            }

            // Get message for pattern extraction
            if (obj.get("MESSAGE")) |msg_val| {
                if (msg_val == .string) {
                    const msg = msg_val.string;
                    const pattern = simplifyLogPattern(allocator, msg);
                    if (pattern.len > 0 and pattern.len < 200) {
                        const result = pattern_counts.getOrPut(pattern) catch continue;
                        if (result.found_existing) {
                            result.value_ptr.* += 1;
                        } else {
                            result.value_ptr.* = 1;
                        }
                    }
                }
            }
        }
    }

    // Count OOM events with separate grep
    stats.oom_events = countGrepMatches(allocator, "Out of memory|oom-kill|oom_reaper");

    // Count kernel panics
    stats.kernel_panics = countGrepMatches(allocator, "Kernel panic");

    // Count segfaults
    stats.segfaults = countGrepMatches(allocator, "segfault");

    // Convert to top errors
    var pattern_list = std.ArrayList(PatternCount).empty;
    defer pattern_list.deinit(allocator);

    var it = pattern_counts.iterator();
    while (it.next()) |entry| {
        pattern_list.append(allocator, .{
            .pattern = entry.key_ptr.*,
            .count = entry.value_ptr.*,
        }) catch continue;
    }

    std.mem.sort(PatternCount, pattern_list.items, {}, struct {
        fn lessThan(_: void, a: PatternCount, b: PatternCount) bool {
            return a.count > b.count;
        }
    }.lessThan);

    const max_patterns = @min(pattern_list.items.len, 5);
    for (pattern_list.items[0..max_patterns]) |pc| {
        error_patterns.append(allocator, report.ErrorPattern{
            .pattern = allocator.dupe(u8, pc.pattern) catch continue,
            .count = pc.count,
        }) catch continue;
    }

    stats.top_errors = error_patterns.toOwnedSlice(allocator) catch null;

    return report.LogInfo{
        .available = true,
        .period = "24h",
        .stats = stats,
    };
}

fn countGrepMatches(allocator: std.mem.Allocator, grep_pattern: []const u8) i32 {
    const output = utils.runCommand(allocator, &[_][]const u8{
        "journalctl",
        "--since",
        "24 hours ago",
        "-k",
        "--no-pager",
        "--grep",
        grep_pattern,
    }) catch return 0;

    var count: i32 = 0;
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (line.len > 0) count += 1;
    }
    return count;
}

const PatternCount = struct {
    pattern: []const u8,
    count: i32,
};

fn simplifyLogPattern(allocator: std.mem.Allocator, msg: []const u8) []const u8 {
    if (msg.len == 0) return "";

    // Simplify: replace hex addresses and long numbers
    var result = std.ArrayList(u8).empty;
    var i: usize = 0;
    while (i < msg.len) {
        // Check for hex address (0x...)
        if (i + 2 < msg.len and msg[i] == '0' and msg[i + 1] == 'x') {
            result.appendSlice(allocator, "0x...") catch return msg[0..@min(msg.len, 80)];
            i += 2;
            while (i < msg.len and isHexChar(msg[i])) : (i += 1) {}
            continue;
        }

        // Check for long numbers (4+ digits)
        if (isDigit(msg[i])) {
            var num_len: usize = 0;
            const start = i;
            while (i < msg.len and isDigit(msg[i])) : (i += 1) {
                num_len += 1;
            }
            if (num_len >= 4) {
                result.appendSlice(allocator, "...") catch return msg[0..@min(msg.len, 80)];
            } else {
                result.appendSlice(allocator, msg[start..i]) catch return msg[0..@min(msg.len, 80)];
            }
            continue;
        }

        result.append(allocator, msg[i]) catch return msg[0..@min(msg.len, 80)];
        i += 1;
    }

    const final = result.toOwnedSlice(allocator) catch return msg[0..@min(msg.len, 80)];
    if (final.len > 80) {
        return allocator.dupe(u8, final[0..77] ++ "...") catch final[0..80];
    }
    return final;
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isHexChar(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}
