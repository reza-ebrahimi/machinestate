const std = @import("std");
const utils = @import("../utils.zig");
const report = @import("../models/report.zig");

pub fn collectSnapInfo(allocator: std.mem.Allocator) ?report.SnapInfo {
    if (!utils.commandExists("snap")) {
        return report.SnapInfo{
            .available = false,
        };
    }

    var packages = std.ArrayList(report.SnapPackage).empty;

    const list_output = utils.runCommand(allocator, &[_][]const u8{
        "snap", "list", "--color=never",
    }) catch {
        return report.SnapInfo{
            .available = false,
        };
    };

    var lines = std.mem.splitScalar(u8, list_output, '\n');
    _ = lines.next(); // Skip header

    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (parseSnapLine(allocator, line)) |snap| {
            packages.append(allocator, snap) catch continue;
        }
    }

    // Get pending refreshes
    var pending_refreshes: i32 = 0;
    const refresh_output = utils.runCommand(allocator, &[_][]const u8{
        "snap", "refresh", "--list",
    }) catch "";

    if (refresh_output.len > 0 and !std.mem.startsWith(u8, refresh_output, "All snaps")) {
        var refresh_lines = std.mem.splitScalar(u8, refresh_output, '\n');
        _ = refresh_lines.next(); // Skip header
        while (refresh_lines.next()) |l| {
            if (l.len > 0) pending_refreshes += 1;
        }
    }

    // Calculate total size
    var total_size: i64 = 0;
    for (packages.items) |p| {
        total_size += p.disk_usage;
    }

    const snap_slice = packages.toOwnedSlice(allocator) catch null;

    return report.SnapInfo{
        .available = true,
        .snaps = snap_slice,
        .total_disk_usage = total_size,
        .pending_refreshes = pending_refreshes,
    };
}

fn parseSnapLine(allocator: std.mem.Allocator, line: []const u8) ?report.SnapPackage {
    var parts = std.mem.tokenizeScalar(u8, line, ' ');

    const name = parts.next() orelse return null;
    const version = parts.next() orelse return null;
    const rev = parts.next() orelse return null;
    _ = parts.next(); // tracking
    const publisher = parts.next() orelse "";

    // Get disk usage
    var path_buf: [256]u8 = undefined;
    const snap_path = std.fmt.bufPrint(&path_buf, "/snap/{s}", .{name}) catch return null;

    var size: i64 = 0;
    const du_output = utils.runCommand(allocator, &[_][]const u8{
        "du", "-sb", snap_path,
    }) catch "";

    if (du_output.len > 0) {
        var du_parts = std.mem.tokenizeAny(u8, du_output, " \t");
        const size_str = du_parts.next() orelse "";
        size = utils.parseInt(i64, size_str, 0);
    }

    return report.SnapPackage{
        .name = allocator.dupe(u8, name) catch return null,
        .version = allocator.dupe(u8, version) catch return null,
        .revision = allocator.dupe(u8, rev) catch return null,
        .publisher = allocator.dupe(u8, publisher) catch return null,
        .disk_usage = size,
    };
}
