const std = @import("std");
const utils = @import("../utils.zig");
const report = @import("../models/report.zig");

pub fn collectPackageInfo(allocator: std.mem.Allocator) report.PackageInfo {
    var updates_list = std.ArrayList([]const u8).empty;
    var held_packages = std.ArrayList([]const u8).empty;
    var updates_available: i32 = 0;
    var security_updates: i32 = 0;
    var broken_packages: i32 = 0;

    // Get upgradable packages
    const apt_output = utils.runCommand(allocator, &[_][]const u8{
        "apt", "list", "--upgradable",
    }) catch "";

    if (apt_output.len > 0) {
        var lines = std.mem.splitScalar(u8, apt_output, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            if (std.mem.startsWith(u8, line, "Listing")) continue;

            if (std.mem.indexOf(u8, line, "/") != null) {
                const slash_pos = std.mem.indexOf(u8, line, "/") orelse continue;
                const pkg_name = line[0..slash_pos];
                if (pkg_name.len > 0) {
                    updates_list.append(allocator, allocator.dupe(u8, pkg_name) catch continue) catch continue;
                    updates_available += 1;

                    if (std.mem.indexOf(u8, line, "security") != null) {
                        security_updates += 1;
                    }
                }
            }
        }
    }

    // Check for broken packages
    const dpkg_output = utils.runCommand(allocator, &[_][]const u8{
        "dpkg", "--audit",
    }) catch "";

    if (dpkg_output.len > 0) {
        var lines = std.mem.splitScalar(u8, dpkg_output, '\n');
        while (lines.next()) |line| {
            if (utils.trim(line).len > 0) {
                broken_packages += 1;
            }
        }
    }

    // Check for held packages
    const hold_output = utils.runCommand(allocator, &[_][]const u8{
        "apt-mark", "showhold",
    }) catch "";

    if (hold_output.len > 0) {
        var lines = std.mem.splitScalar(u8, hold_output, '\n');
        while (lines.next()) |line| {
            const pkg = utils.trim(line);
            if (pkg.len > 0) {
                held_packages.append(allocator, allocator.dupe(u8, pkg) catch continue) catch continue;
            }
        }
    }

    const updates_slice: ?[]const []const u8 = if (updates_list.items.len == 0)
        null
    else
        updates_list.toOwnedSlice(allocator) catch null;

    const held_slice: ?[]const []const u8 = if (held_packages.items.len == 0)
        null
    else
        held_packages.toOwnedSlice(allocator) catch null;

    return report.PackageInfo{
        .updates_available = updates_available,
        .updates_list = updates_slice,
        .security_updates = security_updates,
        .broken_packages = broken_packages,
        .held_packages = held_slice,
    };
}
