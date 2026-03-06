const std = @import("std");
const utils = @import("../utils.zig");
const report = @import("../models/report.zig");

pub fn collectServiceInfo(allocator: std.mem.Allocator) report.ServiceInfo {
    var failed_units = std.ArrayList([]const u8).empty;
    var top_cpu = std.ArrayList(report.ProcessInfo).empty;
    var top_memory = std.ArrayList(report.ProcessInfo).empty;
    var zombie_count: i32 = 0;

    // Get failed systemd units
    const systemctl_output = utils.runCommand(allocator, &[_][]const u8{
        "systemctl", "--failed", "--no-pager", "--no-legend",
    }) catch "";

    if (systemctl_output.len > 0) {
        var lines = std.mem.splitScalar(u8, systemctl_output, '\n');
        while (lines.next()) |line| {
            const trimmed = utils.trim(line);
            if (trimmed.len == 0) continue;

            var fields = std.mem.tokenizeScalar(u8, trimmed, ' ');
            if (fields.next()) |unit| {
                failed_units.append(allocator, allocator.dupe(u8, unit) catch continue) catch continue;
            }
        }
    }

    // Get top CPU processes
    const cpu_output = utils.runCommand(allocator, &[_][]const u8{
        "ps", "-eo", "pid,user,%cpu,%mem,comm", "--no-headers", "--sort=-%cpu",
    }) catch "";

    if (cpu_output.len > 0) {
        var lines = std.mem.splitScalar(u8, cpu_output, '\n');
        var count: usize = 0;
        while (lines.next()) |line| : (count += 1) {
            if (count >= 5) break;
            if (parseProcessLine(allocator, line)) |proc| {
                if (proc.cpu > 0 or count < 5) {
                    top_cpu.append(allocator, proc) catch continue;
                }
            }
        }
    }

    // Get top memory processes
    const mem_output = utils.runCommand(allocator, &[_][]const u8{
        "ps", "-eo", "pid,user,%cpu,%mem,comm", "--no-headers", "--sort=-%mem",
    }) catch "";

    if (mem_output.len > 0) {
        var lines = std.mem.splitScalar(u8, mem_output, '\n');
        var count: usize = 0;
        while (lines.next()) |line| : (count += 1) {
            if (count >= 5) break;
            if (parseProcessLine(allocator, line)) |proc| {
                if (proc.memory > 0 or count < 5) {
                    top_memory.append(allocator, proc) catch continue;
                }
            }
        }
    }

    // Count zombie processes
    const zombie_output = utils.runCommand(allocator, &[_][]const u8{
        "ps", "-eo", "stat", "--no-headers",
    }) catch "";

    if (zombie_output.len > 0) {
        var lines = std.mem.splitScalar(u8, zombie_output, '\n');
        while (lines.next()) |line| {
            const stat = utils.trim(line);
            if (stat.len > 0 and stat[0] == 'Z') {
                zombie_count += 1;
            }
        }
    }

    return report.ServiceInfo{
        .failed_units = failed_units.toOwnedSlice(allocator) catch &[_][]const u8{},
        .zombie_count = zombie_count,
        .top_cpu = top_cpu.toOwnedSlice(allocator) catch &[_]report.ProcessInfo{},
        .top_memory = top_memory.toOwnedSlice(allocator) catch &[_]report.ProcessInfo{},
    };
}

fn parseProcessLine(allocator: std.mem.Allocator, line: []const u8) ?report.ProcessInfo {
    var parts = std.mem.tokenizeScalar(u8, line, ' ');

    const pid_str = parts.next() orelse return null;
    const user = parts.next() orelse return null;
    const cpu_str = parts.next() orelse return null;
    const mem_str = parts.next() orelse return null;
    const name = parts.next() orelse return null;

    return report.ProcessInfo{
        .pid = utils.parseInt(i32, pid_str, 0),
        .name = allocator.dupe(u8, name) catch return null,
        .cpu = utils.parseFloat(cpu_str, 0),
        .memory = @floatCast(utils.parseFloat(mem_str, 0)),
        .user = allocator.dupe(u8, user) catch return null,
    };
}
