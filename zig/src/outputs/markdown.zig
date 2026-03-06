const std = @import("std");
const report = @import("../models/report.zig");

/// Render report as Markdown
pub fn renderMarkdown(allocator: std.mem.Allocator, r: *const report.Report) ![]u8 {
    var alloc_writer = std.Io.Writer.Allocating.init(allocator);
    errdefer alloc_writer.deinit();
    const w = &alloc_writer.writer;

    // Header
    try w.print("# MachineState Report\n\n", .{});
    try w.print("**Host:** {s}  \n", .{r.hostname});
    try w.print("**Generated:** {s}\n\n", .{r.timestamp});
    try w.writeAll("---\n\n");

    // OS Info
    try w.writeAll("## Operating System\n\n");
    try w.print("| Property | Value |\n", .{});
    try w.print("|----------|-------|\n", .{});
    try w.print("| Name | {s} |\n", .{r.os.name});
    try w.print("| Version | {s} |\n", .{r.os.version});
    try w.print("| Kernel | {s} |\n", .{r.os.kernel});
    try w.print("| Architecture | {s} |\n", .{r.os.architecture});
    try w.writeAll("\n");

    // System
    try w.writeAll("## System\n\n");
    try w.print("| Metric | Value |\n", .{});
    try w.print("|--------|-------|\n", .{});
    try w.print("| Uptime | {s} |\n", .{r.system.uptime_human});
    try w.print("| Timezone | {s} |\n", .{r.system.timezone});
    try w.print("| CPU Cores | {d} |\n", .{r.system.cpu_cores});
    try w.print("| CPU Usage | {d:.1}% |\n", .{r.system.cpu_usage});
    try w.print("| Load Average | {d:.2} / {d:.2} / {d:.2} |\n", .{ r.system.load_avg_1, r.system.load_avg_5, r.system.load_avg_15 });
    try w.print("| Memory | {s} / {s} ({d:.1}%) |\n", .{ formatBytes(r.system.memory_used), formatBytes(r.system.memory_total), r.system.memory_percent });
    if (r.system.swap_total > 0) {
        try w.print("| Swap | {s} / {s} ({d:.1}%) |\n", .{ formatBytes(r.system.swap_used), formatBytes(r.system.swap_total), r.system.swap_percent });
    }
    if (r.system.reboot_required) {
        try w.writeAll("| Reboot Required | Yes |\n");
    }
    try w.writeAll("\n");

    // Disk
    try w.writeAll("## Disk\n\n");
    try w.print("| Mount | Device | Used | Total | Usage |\n", .{});
    try w.print("|-------|--------|------|-------|-------|\n", .{});
    for (r.disk.filesystems) |fs| {
        try w.print("| {s} | {s} | {s} | {s} | {d:.1}% |\n", .{ fs.mount_point, fs.device, formatBytes(fs.used), formatBytes(fs.total), fs.used_percent });
    }
    try w.writeAll("\n");

    // Network
    try w.writeAll("## Network\n\n");
    try w.print("| Interface | State | MAC | RX | TX |\n", .{});
    try w.print("|-----------|-------|-----|----|----|", .{});
    try w.writeAll("\n");
    for (r.network.interfaces) |iface| {
        try w.print("| {s} | {s} | {s} | {s} | {s} |\n", .{ iface.name, iface.state, iface.mac, formatBytes(iface.rx_bytes), formatBytes(iface.tx_bytes) });
    }
    try w.writeAll("\n");

    try w.print("**Internet Connectivity:** {s}\n\n", .{if (r.network.connectivity) "Connected" else "Not connected"});

    if (r.network.listen_ports.len > 0) {
        try w.writeAll("**Listening Ports:** ");
        var first = true;
        for (r.network.listen_ports) |port| {
            if (!first) try w.writeAll(", ");
            try w.print("{d}/{s}", .{ port.port, port.protocol });
            first = false;
        }
        try w.writeAll("\n\n");
    }

    // Hardware
    if (r.hardware.battery != null or (r.hardware.temperatures != null and r.hardware.temperatures.?.len > 0)) {
        try w.writeAll("## Hardware\n\n");

        if (r.hardware.battery) |bat| {
            try w.writeAll("### Battery\n\n");
            try w.print("| Property | Value |\n", .{});
            try w.print("|----------|-------|\n", .{});
            try w.print("| Status | {s} |\n", .{bat.status});
            try w.print("| Capacity | {d:.0}% |\n", .{bat.capacity});
            try w.print("| Health | {d:.1}% |\n", .{bat.health});
            try w.print("| Cycles | {d} |\n", .{bat.cycle_count});
            try w.writeAll("\n");
        }

        if (r.hardware.temperatures) |temps| {
            if (temps.len > 0) {
                try w.writeAll("### Temperatures\n\n");
                try w.print("| Sensor | Temperature |\n", .{});
                try w.print("|--------|-------------|\n", .{});
                for (temps) |temp| {
                    if (temp.current > 0) {
                        try w.print("| {s} | {d:.0}C |\n", .{ temp.label, temp.current });
                    }
                }
                try w.writeAll("\n");
            }
        }
    }

    // Packages
    if (r.packages.updates_available > 0 or r.packages.security_updates > 0) {
        try w.writeAll("## Packages\n\n");
        try w.print("| Metric | Value |\n", .{});
        try w.print("|--------|-------|\n", .{});
        try w.print("| Updates Available | {d} |\n", .{r.packages.updates_available});
        if (r.packages.security_updates > 0) {
            try w.print("| Security Updates | {d} |\n", .{r.packages.security_updates});
        }
        try w.writeAll("\n");
    }

    // Services
    if (r.services.zombie_count > 0 or r.services.failed_units.len > 0) {
        try w.writeAll("## Services\n\n");
        if (r.services.zombie_count > 0) {
            try w.print("**Zombie Processes:** {d}\n\n", .{r.services.zombie_count});
        }
        if (r.services.failed_units.len > 0) {
            try w.writeAll("**Failed Units:**\n");
            for (r.services.failed_units) |unit| {
                try w.print("- {s}\n", .{unit});
            }
            try w.writeAll("\n");
        }
    }

    // Docker
    if (r.docker) |docker| {
        if (docker.available) {
            try w.writeAll("## Docker\n\n");
            try w.print("| Metric | Value |\n", .{});
            try w.print("|--------|-------|\n", .{});
            try w.print("| Daemon | {s} |\n", .{if (docker.daemon_running) "Running" else "Stopped"});
            try w.print("| Running Containers | {d} |\n", .{docker.running_count});
            try w.print("| Stopped Containers | {d} |\n", .{docker.stopped_count});
            try w.print("| Images | {d} |\n", .{docker.image_count});
            try w.print("| Total Image Size | {s} |\n", .{formatBytes(@intCast(docker.total_image_size))});
            try w.writeAll("\n");
        }
    }

    // Snaps
    if (r.snaps) |snaps| {
        if (snaps.available) {
            try w.writeAll("## Snaps\n\n");
            try w.print("| Metric | Value |\n", .{});
            try w.print("|--------|-------|\n", .{});
            if (snaps.snaps) |snap_list| {
                try w.print("| Installed | {d} |\n", .{snap_list.len});
            }
            try w.print("| Disk Usage | {s} |\n", .{formatBytes(@intCast(snaps.total_disk_usage))});
            if (snaps.pending_refreshes > 0) {
                try w.print("| Pending Refreshes | {d} |\n", .{snaps.pending_refreshes});
            }
            try w.writeAll("\n");
        }
    }

    // GPU
    if (r.gpu) |gpu| {
        if (gpu.available) {
            if (gpu.gpus) |gpus| {
                try w.writeAll("## GPU\n\n");
                for (gpus) |g| {
                    try w.print("### {s}\n\n", .{g.name});
                    try w.print("| Metric | Value |\n", .{});
                    try w.print("|--------|-------|\n", .{});
                    try w.print("| Vendor | {s} |\n", .{g.vendor});
                    if (g.temperature > 0) {
                        try w.print("| Temperature | {d}C |\n", .{g.temperature});
                    }
                    if (g.utilization > 0) {
                        try w.print("| Utilization | {d}% |\n", .{g.utilization});
                    }
                    if (g.memory_total > 0) {
                        try w.print("| Memory | {s} / {s} |\n", .{ formatBytes(@intCast(g.memory_used)), formatBytes(@intCast(g.memory_total)) });
                    }
                    try w.writeAll("\n");
                }
            }
        }
    }

    // Logs
    if (r.logs) |logs| {
        if (logs.available) {
            try w.writeAll("## Logs (24h)\n\n");
            try w.print("| Metric | Value |\n", .{});
            try w.print("|--------|-------|\n", .{});
            try w.print("| Errors | {d} |\n", .{logs.stats.error_count});
            if (logs.stats.critical_count > 0) {
                try w.print("| Critical | {d} |\n", .{logs.stats.critical_count});
            }
            if (logs.stats.oom_events > 0) {
                try w.print("| OOM Events | {d} |\n", .{logs.stats.oom_events});
            }
            if (logs.stats.kernel_panics > 0) {
                try w.print("| Kernel Panics | {d} |\n", .{logs.stats.kernel_panics});
            }
            if (logs.stats.segfaults > 0) {
                try w.print("| Segfaults | {d} |\n", .{logs.stats.segfaults});
            }
            try w.writeAll("\n");
        }
    }

    // Issues
    if (r.issues.len > 0) {
        try w.writeAll("## Issues\n\n");

        // Count by severity
        var critical: usize = 0;
        var warnings: usize = 0;
        for (r.issues) |issue| {
            if (std.mem.eql(u8, issue.severity, "critical")) {
                critical += 1;
            } else if (std.mem.eql(u8, issue.severity, "warning")) {
                warnings += 1;
            }
        }

        if (critical > 0 or warnings > 0) {
            try w.writeAll("**Summary:** ");
            if (critical > 0) try w.print("{d} critical ", .{critical});
            if (warnings > 0) try w.print("{d} warnings", .{warnings});
            try w.writeAll("\n\n");
        }

        for (r.issues) |issue| {
            const icon = if (std.mem.eql(u8, issue.severity, "critical"))
                "X"
            else if (std.mem.eql(u8, issue.severity, "warning"))
                "!"
            else
                "i";

            try w.print("### [{s}] [{s}] {s}\n\n", .{ icon, issue.category, issue.title });
            try w.print("{s}\n\n", .{issue.description});
            if (issue.fix) |fix| {
                try w.print("**Fix:** {s}\n\n", .{fix});
            }
        }
    }

    // Footer
    try w.writeAll("---\n\n");
    try w.writeAll("*Generated by machinestate*\n");

    return alloc_writer.toOwnedSlice();
}

fn formatBytes(bytes: u64) [16]u8 {
    var buf: [16]u8 = std.mem.zeroes([16]u8);
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB" };
    var value: f64 = @floatFromInt(bytes);
    var unit_idx: usize = 0;

    while (value >= 1024 and unit_idx < units.len - 1) {
        value /= 1024;
        unit_idx += 1;
    }

    _ = std.fmt.bufPrint(&buf, "{d:.1} {s}", .{ value, units[unit_idx] }) catch {};
    return buf;
}
