const std = @import("std");
const utils = @import("../utils.zig");
const report = @import("../models/report.zig");

pub fn collectSecurityInfo(allocator: std.mem.Allocator) report.SecurityInfo {
    var open_ports = std.ArrayList([]const u8).empty;
    var firewall_active = false;
    var firewall_status: []const u8 = "";
    var ssh_enabled = false;

    // Check UFW status
    const ufw_output = utils.runCommand(allocator, &[_][]const u8{
        "ufw", "status",
    }) catch "";

    if (ufw_output.len > 0) {
        firewall_status = allocator.dupe(u8, utils.trim(ufw_output)) catch "";
        firewall_active = std.mem.indexOf(u8, firewall_status, "Status: active") != null;
    } else {
        firewall_status = allocator.dupe(u8, "UFW not installed or not accessible") catch "";
    }

    // Check for ports listening on all interfaces
    const ss_output = utils.runCommand(allocator, &[_][]const u8{
        "ss", "-tulpn",
    }) catch "";

    if (ss_output.len > 0) {
        var lines = std.mem.splitScalar(u8, ss_output, '\n');
        while (lines.next()) |line| {
            if (std.mem.indexOf(u8, line, "0.0.0.0:") != null or
                std.mem.indexOf(u8, line, "*:") != null)
            {
                var fields = std.mem.tokenizeScalar(u8, line, ' ');
                var idx: usize = 0;
                while (fields.next()) |field| : (idx += 1) {
                    if (idx == 4) {
                        open_ports.append(allocator, allocator.dupe(u8, field) catch continue) catch continue;
                        break;
                    }
                }
            }
        }
    }

    // Count failed logins
    const failed_logins = countFailedLogins();

    // Check if SSH is enabled
    const ssh_output = utils.runCommand(allocator, &[_][]const u8{
        "systemctl", "is-active", "ssh",
    }) catch "";

    if (std.mem.eql(u8, utils.trim(ssh_output), "active")) {
        ssh_enabled = true;
    }

    return report.SecurityInfo{
        .firewall_active = firewall_active,
        .firewall_status = firewall_status,
        .failed_logins_24h = failed_logins,
        .open_ports = open_ports.toOwnedSlice(allocator) catch &[_][]const u8{},
        .ssh_enabled = ssh_enabled,
    };
}

fn countFailedLogins() i32 {
    var buf: [65536]u8 = undefined;
    const content = utils.readFileFixed("/var/log/auth.log", &buf) catch return 0;

    var count: i32 = 0;
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "Failed password") != null or
            std.mem.indexOf(u8, line, "authentication failure") != null)
        {
            count += 1;
        }
    }

    return count;
}
