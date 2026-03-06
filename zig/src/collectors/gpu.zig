const std = @import("std");
const utils = @import("../utils.zig");
const report = @import("../models/report.zig");

pub fn collectGPUInfo(allocator: std.mem.Allocator) ?report.GPUInfo {
    var devices = std.ArrayList(report.GPUDevice).empty;

    // Try NVIDIA first
    if (collectNvidiaGPU(allocator)) |gpu| {
        devices.append(allocator, gpu) catch {};
    }

    // Try AMD
    if (collectAMDGPU(allocator)) |gpu| {
        devices.append(allocator, gpu) catch {};
    }

    // Fallback to lspci for detection
    if (devices.items.len == 0) {
        collectLspciGPUs(allocator, &devices);
    }

    if (devices.items.len == 0) {
        return report.GPUInfo{
            .available = false,
        };
    }

    return report.GPUInfo{
        .available = true,
        .gpus = devices.toOwnedSlice(allocator) catch null,
    };
}

fn collectNvidiaGPU(allocator: std.mem.Allocator) ?report.GPUDevice {
    if (!utils.commandExists("nvidia-smi")) {
        return null;
    }

    const output = utils.runCommand(allocator, &[_][]const u8{
        "nvidia-smi",
        "--query-gpu=name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw",
        "--format=csv,noheader,nounits",
    }) catch return null;

    const line = utils.trim(output);
    if (line.len == 0) return null;

    var parts = std.mem.splitSequence(u8, line, ", ");

    const name = parts.next() orelse return null;
    const temp_str = parts.next() orelse "0";
    const util_str = parts.next() orelse "0";
    const mem_used_str = parts.next() orelse "0";
    const mem_total_str = parts.next() orelse "0";
    const power_str = parts.next() orelse "0";

    return report.GPUDevice{
        .index = 0,
        .name = allocator.dupe(u8, name) catch return null,
        .vendor = "nvidia",
        .temperature = utils.parseInt(i32, temp_str, 0),
        .utilization = utils.parseInt(i32, util_str, 0),
        .memory_used = utils.parseInt(i64, mem_used_str, 0) * 1024 * 1024,
        .memory_total = utils.parseInt(i64, mem_total_str, 0) * 1024 * 1024,
        .power_draw = utils.parseFloat(power_str, 0),
    };
}

fn collectAMDGPU(allocator: std.mem.Allocator) ?report.GPUDevice {
    if (!utils.commandExists("rocm-smi")) {
        return null;
    }

    var temp: i32 = 0;
    var util: i32 = 0;

    const temp_output = utils.runCommand(allocator, &[_][]const u8{
        "rocm-smi", "--showtemp",
    }) catch "";

    if (temp_output.len > 0) {
        var lines = std.mem.splitScalar(u8, temp_output, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "Temperature")) |_| {
                for (line, 0..) |c, i| {
                    if (c >= '0' and c <= '9') {
                        var end = i;
                        while (end < line.len and (line[end] >= '0' and line[end] <= '9')) : (end += 1) {}
                        temp = utils.parseInt(i32, line[i..end], 0);
                        break;
                    }
                }
            }
        }
    }

    const util_output = utils.runCommand(allocator, &[_][]const u8{
        "rocm-smi", "--showuse",
    }) catch "";

    if (util_output.len > 0) {
        var lines = std.mem.splitScalar(u8, util_output, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "GPU use")) |_| {
                for (line, 0..) |c, i| {
                    if (c >= '0' and c <= '9') {
                        var end = i;
                        while (end < line.len and (line[end] >= '0' and line[end] <= '9')) : (end += 1) {}
                        util = utils.parseInt(i32, line[i..end], 0);
                        break;
                    }
                }
            }
        }
    }

    if (temp == 0 and util == 0) return null;

    return report.GPUDevice{
        .index = 0,
        .name = allocator.dupe(u8, "AMD GPU") catch "AMD GPU",
        .vendor = "amd",
        .temperature = temp,
        .utilization = util,
    };
}

fn collectLspciGPUs(allocator: std.mem.Allocator, devices: *std.ArrayList(report.GPUDevice)) void {
    if (!utils.commandExists("lspci")) return;

    const output = utils.runCommand(allocator, &[_][]const u8{
        "lspci",
    }) catch return;

    var lines = std.mem.splitScalar(u8, output, '\n');
    var idx: i32 = 0;

    while (lines.next()) |line| {
        const lower = line;
        if (std.mem.indexOf(u8, lower, "VGA") != null or
            std.mem.indexOf(u8, lower, "3D") != null or
            std.mem.indexOf(u8, lower, "Display") != null)
        {
            // Format: "02:00.0 VGA compatible controller: Intel Corporation..."
            // Split by ":" and take third part
            var colon_count: usize = 0;
            var name_start: usize = 0;
            for (line, 0..) |c, i| {
                if (c == ':') {
                    colon_count += 1;
                    if (colon_count == 2) {
                        name_start = i + 1;
                        break;
                    }
                }
            }

            if (name_start == 0 or name_start >= line.len) continue;
            const name = utils.trim(line[name_start..]);
            if (name.len == 0) continue;

            const vendor: []const u8 = if (std.mem.indexOf(u8, lower, "nvidia") != null or std.mem.indexOf(u8, lower, "NVIDIA") != null)
                "nvidia"
            else if (std.mem.indexOf(u8, lower, "amd") != null or std.mem.indexOf(u8, lower, "AMD") != null or std.mem.indexOf(u8, lower, "radeon") != null)
                "amd"
            else if (std.mem.indexOf(u8, lower, "intel") != null or std.mem.indexOf(u8, lower, "Intel") != null)
                "intel"
            else
                "unknown";

            devices.append(allocator, report.GPUDevice{
                .index = idx,
                .name = allocator.dupe(u8, name) catch continue,
                .vendor = vendor,
            }) catch continue;

            idx += 1;
        }
    }
}
