const std = @import("std");
const builtin = @import("builtin");
const utils = @import("../utils.zig");
const report = @import("../models/report.zig");

/// Collect OS information from /etc/os-release and system
pub fn collectOSInfo(allocator: std.mem.Allocator) report.OSInfo {
    var info = report.OSInfo{
        .name = "",
        .version = "",
        .kernel = "",
        .architecture = "",
    };

    // Parse /etc/os-release
    var buf: [4096]u8 = undefined;
    const content = utils.readFileFixed("/etc/os-release", &buf) catch {
        return info;
    };

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        if (std.mem.indexOf(u8, line, "=")) |eq_pos| {
            const key = line[0..eq_pos];
            var value = line[eq_pos + 1 ..];

            // Remove quotes from value
            if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
                value = value[1 .. value.len - 1];
            }

            if (std.mem.eql(u8, key, "PRETTY_NAME")) {
                info.name = allocator.dupe(u8, value) catch "";
            } else if (std.mem.eql(u8, key, "VERSION")) {
                info.version = allocator.dupe(u8, value) catch "";
            }
        }
    }

    // Get kernel version from /proc/version
    var kernel_buf: [256]u8 = undefined;
    if (utils.readFileFixed("/proc/version", &kernel_buf)) |version_content| {
        // Format: "Linux version X.X.X-XXX ..."
        var parts = std.mem.splitScalar(u8, version_content, ' ');
        _ = parts.next(); // "Linux"
        _ = parts.next(); // "version"
        if (parts.next()) |kernel_version| {
            info.kernel = allocator.dupe(u8, kernel_version) catch "";
        }
    } else |_| {}

    // Get architecture
    const arch = @tagName(builtin.cpu.arch);
    const arch_name = if (std.mem.eql(u8, arch, "x86_64"))
        "amd64"
    else if (std.mem.eql(u8, arch, "aarch64"))
        "arm64"
    else
        arch;
    info.architecture = allocator.dupe(u8, arch_name) catch "";

    return info;
}

/// Collect system metrics (uptime, load, memory, CPU)
pub fn collectSystemInfo(allocator: std.mem.Allocator) report.SystemInfo {
    var info = report.SystemInfo{
        .uptime = 0,
        .uptime_human = "",
        .timezone = "",
        .reboot_required = false,
        .load_avg_1 = 0,
        .load_avg_5 = 0,
        .load_avg_15 = 0,
        .cpu_cores = 0,
        .cpu_usage = 0,
        .memory_total = 0,
        .memory_used = 0,
        .memory_free = 0,
        .memory_percent = 0,
        .swap_total = 0,
        .swap_used = 0,
        .swap_percent = 0,
    };

    // Get uptime from /proc/uptime
    var uptime_buf: [64]u8 = undefined;
    if (utils.readFileFixed("/proc/uptime", &uptime_buf)) |content| {
        var parts = std.mem.splitScalar(u8, content, ' ');
        if (parts.next()) |uptime_str| {
            const uptime_secs = utils.parseFloat(uptime_str, 0);
            info.uptime = @intFromFloat(uptime_secs * 1_000_000_000); // Convert to nanoseconds
            info.uptime_human = utils.formatUptime(allocator, @intFromFloat(uptime_secs)) catch "";
        }
    } else |_| {}

    // Get timezone from /etc/timezone
    var tz_buf: [64]u8 = undefined;
    if (utils.readFileFixed("/etc/timezone", &tz_buf)) |content| {
        const trimmed = utils.trim(content);
        info.timezone = allocator.dupe(u8, trimmed) catch "";
    } else |_| {
        info.timezone = allocator.dupe(u8, "UTC") catch "";
    }

    // Check if reboot required
    info.reboot_required = utils.fileExists("/var/run/reboot-required");

    // Get load average from /proc/loadavg
    var loadavg_buf: [64]u8 = undefined;
    if (utils.readFileFixed("/proc/loadavg", &loadavg_buf)) |content| {
        var parts = std.mem.splitScalar(u8, content, ' ');
        if (parts.next()) |load1| {
            info.load_avg_1 = utils.parseFloat(load1, 0);
        }
        if (parts.next()) |load5| {
            info.load_avg_5 = utils.parseFloat(load5, 0);
        }
        if (parts.next()) |load15| {
            info.load_avg_15 = utils.parseFloat(load15, 0);
        }
    } else |_| {}

    // Count CPU cores from /proc/cpuinfo
    var cpuinfo_buf: [32768]u8 = undefined;
    if (utils.readFileFixed("/proc/cpuinfo", &cpuinfo_buf)) |content| {
        var lines = std.mem.splitScalar(u8, content, '\n');
        var count: i32 = 0;
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "processor")) {
                count += 1;
            }
        }
        info.cpu_cores = count;
    } else |_| {}

    // Get memory info from /proc/meminfo
    var meminfo_buf: [4096]u8 = undefined;
    if (utils.readFileFixed("/proc/meminfo", &meminfo_buf)) |content| {
        var mem_total: u64 = 0;
        var mem_available: u64 = 0;
        var swap_total: u64 = 0;
        var swap_free: u64 = 0;

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "MemTotal:")) {
                mem_total = parseMemValue(line);
            } else if (std.mem.startsWith(u8, line, "MemAvailable:")) {
                mem_available = parseMemValue(line);
            } else if (std.mem.startsWith(u8, line, "SwapTotal:")) {
                swap_total = parseMemValue(line);
            } else if (std.mem.startsWith(u8, line, "SwapFree:")) {
                swap_free = parseMemValue(line);
            }
        }

        info.memory_total = mem_total * 1024; // Convert from KB to bytes
        info.memory_free = mem_available * 1024;
        info.memory_used = info.memory_total - info.memory_free;
        if (info.memory_total > 0) {
            info.memory_percent = @as(f64, @floatFromInt(info.memory_used)) / @as(f64, @floatFromInt(info.memory_total)) * 100.0;
        }

        info.swap_total = swap_total * 1024;
        info.swap_used = (swap_total - swap_free) * 1024;
        if (info.swap_total > 0) {
            info.swap_percent = @as(f64, @floatFromInt(info.swap_used)) / @as(f64, @floatFromInt(info.swap_total)) * 100.0;
        }
    } else |_| {}

    // Calculate CPU usage from /proc/stat (simplified - just current snapshot)
    info.cpu_usage = calculateCPUUsage();

    return info;
}

/// Parse memory value from /proc/meminfo line (e.g., "MemTotal:       16384 kB")
fn parseMemValue(line: []const u8) u64 {
    // Find the colon
    const colon_pos = std.mem.indexOf(u8, line, ":") orelse return 0;
    const value_part = utils.trim(line[colon_pos + 1 ..]);

    // Parse the number (ignore "kB" suffix)
    var parts = std.mem.splitScalar(u8, value_part, ' ');
    if (parts.next()) |num_str| {
        return utils.parseInt(u64, num_str, 0);
    }
    return 0;
}

/// Calculate CPU usage from /proc/stat
fn calculateCPUUsage() f64 {
    var buf1: [512]u8 = undefined;
    const content1 = utils.readFileFixed("/proc/stat", &buf1) catch return 0;

    const cpu_times1 = parseCPULine(content1) orelse return 0;

    // Sleep for a short time to get a second sample (100ms)
    std.posix.nanosleep(0, 100_000_000);

    var buf2: [512]u8 = undefined;
    const content2 = utils.readFileFixed("/proc/stat", &buf2) catch return 0;

    const cpu_times2 = parseCPULine(content2) orelse return 0;

    // Calculate differences
    const total_diff = cpu_times2.total - cpu_times1.total;
    const idle_diff = cpu_times2.idle - cpu_times1.idle;

    if (total_diff == 0) return 0;

    const usage = @as(f64, @floatFromInt(total_diff - idle_diff)) / @as(f64, @floatFromInt(total_diff)) * 100.0;
    return usage;
}

const CPUTimes = struct {
    total: u64,
    idle: u64,
};

fn parseCPULine(content: []const u8) ?CPUTimes {
    var lines = std.mem.splitScalar(u8, content, '\n');
    const first_line = lines.next() orelse return null;

    if (!std.mem.startsWith(u8, first_line, "cpu ")) return null;

    var parts = std.mem.splitScalar(u8, first_line, ' ');
    _ = parts.next(); // "cpu"

    var values: [10]u64 = [_]u64{0} ** 10;
    var i: usize = 0;
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        if (i >= values.len) break;
        values[i] = utils.parseInt(u64, part, 0);
        i += 1;
    }

    // user, nice, system, idle, iowait, irq, softirq, steal, guest, guest_nice
    var total: u64 = 0;
    for (values) |v| {
        total += v;
    }

    return CPUTimes{
        .total = total,
        .idle = values[3] + values[4], // idle + iowait
    };
}

test "parseMemValue" {
    try std.testing.expectEqual(@as(u64, 16384), parseMemValue("MemTotal:       16384 kB"));
    try std.testing.expectEqual(@as(u64, 0), parseMemValue("Invalid line"));
}
