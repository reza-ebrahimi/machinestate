const std = @import("std");
const utils = @import("../utils.zig");
const report = @import("../models/report.zig");

/// Collect hardware information (battery, temperatures, crash reports)
pub fn collectHardwareInfo(allocator: std.mem.Allocator) report.HardwareInfo {
    const battery = collectBatteryInfo(allocator);
    const temperatures = collectTemperatures(allocator);
    const crash_reports = collectCrashReports(allocator);

    return report.HardwareInfo{
        .battery = battery,
        .temperatures = temperatures,
        .crash_reports = crash_reports,
    };
}

fn collectBatteryInfo(allocator: std.mem.Allocator) ?report.BatteryInfo {
    // Try BAT0, then BAT1
    const bat_paths = [_][]const u8{ "/sys/class/power_supply/BAT0", "/sys/class/power_supply/BAT1" };

    for (bat_paths) |bat_path| {
        if (readBattery(allocator, bat_path)) |info| {
            return info;
        }
    }

    return null;
}

fn readBattery(allocator: std.mem.Allocator, base_path: []const u8) ?report.BatteryInfo {
    var path_buf: [256]u8 = undefined;

    // Check if battery exists
    const status_path = std.fmt.bufPrint(&path_buf, "{s}/status", .{base_path}) catch return null;
    var status_buf: [32]u8 = undefined;
    const status = utils.readFileFixed(status_path, &status_buf) catch return null;

    // Read capacity
    const capacity_path = std.fmt.bufPrint(&path_buf, "{s}/capacity", .{base_path}) catch return null;
    var capacity_buf: [16]u8 = undefined;
    const capacity_str = utils.readFileFixed(capacity_path, &capacity_buf) catch "0";
    const capacity = utils.parseFloat(utils.trim(capacity_str), 0);

    // Read cycle count
    const cycle_path = std.fmt.bufPrint(&path_buf, "{s}/cycle_count", .{base_path}) catch return null;
    var cycle_buf: [16]u8 = undefined;
    const cycle_str = utils.readFileFixed(cycle_path, &cycle_buf) catch "0";
    const cycle_count = utils.parseInt(i32, utils.trim(cycle_str), 0);

    // Read energy values for health calculation
    const design_path = std.fmt.bufPrint(&path_buf, "{s}/energy_full_design", .{base_path}) catch return null;
    var design_buf: [32]u8 = undefined;
    const design_str = utils.readFileFixed(design_path, &design_buf) catch "0";
    const design_energy = utils.parseFloat(utils.trim(design_str), 0);

    const full_path = std.fmt.bufPrint(&path_buf, "{s}/energy_full", .{base_path}) catch return null;
    var full_buf: [32]u8 = undefined;
    const full_str = utils.readFileFixed(full_path, &full_buf) catch "0";
    const full_energy = utils.parseFloat(utils.trim(full_str), 0);

    // Calculate health as percentage
    const health: f64 = if (design_energy > 0) (full_energy / design_energy) * 100.0 else 100.0;

    // Convert to Wh
    const design_wh = design_energy / 1000000.0;
    const full_wh = full_energy / 1000000.0;

    return report.BatteryInfo{
        .present = true,
        .status = allocator.dupe(u8, utils.trim(status)) catch "",
        .capacity = capacity,
        .health = health,
        .cycle_count = cycle_count,
        .design_capacity = design_wh,
        .full_capacity = full_wh,
    };
}

fn collectTemperatures(allocator: std.mem.Allocator) ?[]const report.TemperatureInfo {
    var temps = std.ArrayList(report.TemperatureInfo).empty;

    // Read from thermal zones
    var zone: u32 = 0;
    while (zone < 20) : (zone += 1) {
        var path_buf: [128]u8 = undefined;

        // Read temperature
        const temp_path = std.fmt.bufPrint(&path_buf, "/sys/class/thermal/thermal_zone{d}/temp", .{zone}) catch continue;
        var temp_buf: [16]u8 = undefined;
        const temp_str = utils.readFileFixed(temp_path, &temp_buf) catch break;
        const temp_milli = utils.parseFloat(utils.trim(temp_str), 0);
        const temp = temp_milli / 1000.0;

        // Read zone type (label)
        const type_path = std.fmt.bufPrint(&path_buf, "/sys/class/thermal/thermal_zone{d}/type", .{zone}) catch continue;
        var type_buf: [64]u8 = undefined;
        const zone_type = utils.readFileFixed(type_path, &type_buf) catch continue;

        temps.append(allocator, report.TemperatureInfo{
            .label = allocator.dupe(u8, utils.trim(zone_type)) catch continue,
            .current = temp,
            .high = null,
            .critical = null,
        }) catch continue;
    }

    // Read from hwmon - skip for now due to complexity
    // The hwmon interface requires checking if files exist first
    // and handling potential directory entries

    if (temps.items.len == 0) return null;
    return temps.toOwnedSlice(allocator) catch null;
}

fn collectCrashReports(allocator: std.mem.Allocator) ?[]const []const u8 {
    var reports = std.ArrayList([]const u8).empty;

    const output = utils.runCommand(allocator, &[_][]const u8{
        "ls", "-1", "/var/crash/",
    }) catch return null;

    if (output.len == 0) return null;

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        const name = utils.trim(line);
        if (name.len > 0 and std.mem.endsWith(u8, name, ".crash")) {
            reports.append(allocator, allocator.dupe(u8, name) catch continue) catch continue;
        }
    }

    if (reports.items.len == 0) return null;
    return reports.toOwnedSlice(allocator) catch null;
}
