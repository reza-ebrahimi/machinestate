const std = @import("std");
const report = @import("../models/report.zig");

// ANSI color codes
const Color = struct {
    const reset = "\x1b[0m";
    const bold = "\x1b[1m";
    const dim = "\x1b[90m";
    const red = "\x1b[31m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const cyan = "\x1b[36m";
    const bright_red = "\x1b[1;91m";
    const white = "\x1b[37m";
};

// Unicode symbols
const Symbols = struct {
    const check = "\u{2713}";
    const cross = "\u{2717}";
    const warning = "\u{26A0}";
    const info = "\u{2139}";
};

/// Render report as colored terminal output
pub fn renderTerminal(allocator: std.mem.Allocator, r: *const report.Report) ![]u8 {
    var alloc_writer = std.Io.Writer.Allocating.init(allocator);
    errdefer alloc_writer.deinit();
    const writer = &alloc_writer.writer;

    // Header
    try writer.writeAll("\n");
    try writer.print("{s}═══════════════════════════════════════════════════════════════{s}\n", .{ Color.cyan, Color.reset });
    try writer.print("{s}                      MACHINESTATE REPORT                       {s}\n", .{ Color.cyan, Color.reset });
    try writer.print("{s}═══════════════════════════════════════════════════════════════{s}\n", .{ Color.cyan, Color.reset });

    // Basic info
    try writer.print("\n{s}Hostname:{s}  {s}\n", .{ Color.bold, Color.reset, r.hostname });
    try writer.print("{s}Generated:{s} {s}\n", .{ Color.bold, Color.reset, r.timestamp });

    // OS Section
    try renderSection(writer, "OS INFO");
    try writer.print("  Name:         {s}\n", .{r.os.name});
    try writer.print("  Version:      {s}\n", .{r.os.version});
    try writer.print("  Kernel:       {s}\n", .{r.os.kernel});
    try writer.print("  Architecture: {s}\n", .{r.os.architecture});

    // System Section
    try renderSection(writer, "SYSTEM");
    try writer.print("  Uptime:     {s}\n", .{r.system.uptime_human});
    try writer.print("  Timezone:   {s}\n", .{r.system.timezone});
    try writer.print("  CPU Cores:  {d}\n", .{r.system.cpu_cores});
    try writer.print("  CPU Usage:  {d:.1}%\n", .{r.system.cpu_usage});
    try writer.print("  Load Avg:   {d:.2} / {d:.2} / {d:.2}\n", .{ r.system.load_avg_1, r.system.load_avg_5, r.system.load_avg_15 });

    // Memory
    try writer.print("\n  {s}Memory:{s}\n", .{ Color.bold, Color.reset });
    try renderProgressBar(writer, "  ", r.system.memory_percent, getStatusColor(r.system.memory_percent, 70, 90));
    try writer.print("    {s} / {s} ({d:.1}%)\n", .{
        formatBytes(r.system.memory_used),
        formatBytes(r.system.memory_total),
        r.system.memory_percent,
    });

    // Swap
    if (r.system.swap_total > 0) {
        try writer.print("\n  {s}Swap:{s}\n", .{ Color.bold, Color.reset });
        try renderProgressBar(writer, "  ", r.system.swap_percent, getStatusColor(r.system.swap_percent, 50, 80));
        try writer.print("    {s} / {s} ({d:.1}%)\n", .{
            formatBytes(r.system.swap_used),
            formatBytes(r.system.swap_total),
            r.system.swap_percent,
        });
    }

    // Reboot Required
    if (r.system.reboot_required) {
        try writer.print("\n  {s}{s} Reboot Required{s}\n", .{ Color.yellow, Symbols.warning, Color.reset });
    }

    // Disk Section
    try renderSection(writer, "DISK");
    for (r.disk.filesystems) |fs| {
        const color = getStatusColor(fs.used_percent, 70, 90);
        try writer.print("  {s}{s}{s}: ", .{ Color.bold, fs.mount_point, Color.reset });
        try writer.print("{s}{d:.1}%{s} ", .{ color, fs.used_percent, Color.reset });
        try writer.print("({s} / {s})\n", .{ formatBytes(fs.used), formatBytes(fs.total) });
    }

    // Network Section
    try renderSection(writer, "NETWORK");
    for (r.network.interfaces) |iface| {
        const state_color = if (std.mem.eql(u8, iface.state, "UP")) Color.green else Color.dim;
        try writer.print("  {s}: {s}{s}{s} ({s})\n", .{ iface.name, state_color, iface.state, Color.reset, iface.mac });
        try writer.print("    RX: {s}  TX: {s}\n", .{ formatBytes(iface.rx_bytes), formatBytes(iface.tx_bytes) });
    }

    if (r.network.connectivity) {
        try writer.print("\n  {s}{s} Internet Connected{s}\n", .{ Color.green, Symbols.check, Color.reset });
    } else {
        try writer.print("\n  {s}{s} No Internet{s}\n", .{ Color.red, Symbols.cross, Color.reset });
    }

    if (r.network.listen_ports.len > 0) {
        try writer.print("\n  Listening Ports: ", .{});
        var first = true;
        for (r.network.listen_ports) |port| {
            if (!first) try writer.writeAll(", ");
            try writer.print("{d}/{s}", .{ port.port, port.protocol });
            first = false;
        }
        try writer.writeAll("\n");
    }

    // Security Section
    try renderSection(writer, "SECURITY");
    if (r.security.firewall_active) {
        try writer.print("  {s}{s} Firewall Active{s}\n", .{ Color.green, Symbols.check, Color.reset });
    } else {
        try writer.print("  {s}{s} Firewall Inactive{s}\n", .{ Color.yellow, Symbols.warning, Color.reset });
    }
    if (r.security.open_ports.len > 0) {
        try writer.print("  Open Ports (0.0.0.0): {d}\n", .{r.security.open_ports.len});
    }
    if (r.security.failed_logins_24h > 0) {
        try writer.print("  {s}{s} Failed Logins (24h): {d}{s}\n", .{ Color.yellow, Symbols.warning, r.security.failed_logins_24h, Color.reset });
    }

    // Hardware Section (if battery present)
    if (r.hardware.battery) |bat| {
        try renderSection(writer, "HARDWARE");
        try writer.print("  {s}Battery:{s}\n", .{ Color.bold, Color.reset });
        try writer.print("    Status:   {s}\n", .{bat.status});
        try writer.print("    Capacity: {d:.0}%\n", .{bat.capacity});
        const health_color = getStatusColor(100 - bat.health, 20, 50);
        try writer.print("    Health:   {s}{d:.1}%{s}\n", .{ health_color, bat.health, Color.reset });
        try writer.print("    Cycles:   {d}\n", .{bat.cycle_count});
    }

    if (r.hardware.temperatures) |temps| {
        if (temps.len > 0) {
            try writer.print("\n  {s}Temperatures:{s}\n", .{ Color.bold, Color.reset });
            for (temps) |temp| {
                if (temp.current > 0) {
                    const temp_color = if (temp.current >= 85) Color.red else if (temp.current >= 70) Color.yellow else Color.green;
                    try writer.print("    {s}: {s}{d:.0}C{s}\n", .{ temp.label, temp_color, temp.current, Color.reset });
                }
            }
        }
    }

    // Packages Section
    if (r.packages.updates_available > 0 or r.packages.security_updates > 0) {
        try renderSection(writer, "PACKAGES");
        if (r.packages.updates_available > 0) {
            try writer.print("  Updates Available: {d}\n", .{r.packages.updates_available});
        }
        if (r.packages.security_updates > 0) {
            try writer.print("  {s}{s} Security Updates: {d}{s}\n", .{ Color.yellow, Symbols.warning, r.packages.security_updates, Color.reset });
        }
    }

    // Services Section
    try renderSection(writer, "SERVICES");
    try writer.print("  Failed Services: {d}\n", .{r.services.failed_units.len});
    if (r.services.failed_units.len > 0) {
        for (r.services.failed_units) |unit| {
            try writer.print("    - {s}\n", .{unit});
        }
    }
    if (r.services.zombie_count > 0) {
        try writer.print("  {s}{s} Zombie Processes: {d}{s}\n", .{ Color.yellow, Symbols.warning, r.services.zombie_count, Color.reset });
    }
    if (r.services.top_cpu.len > 0) {
        try writer.print("\n  {s}Top CPU:{s}\n", .{ Color.bold, Color.reset });
        for (r.services.top_cpu) |proc| {
            try writer.print("    {s: <20} {d:5.1}% CPU  ({s})\n", .{ proc.name, proc.cpu, proc.user });
        }
    }

    // Docker Section
    if (r.docker) |docker| {
        if (docker.available) {
            try renderSection(writer, "DOCKER");
            if (docker.daemon_running) {
                try writer.print("  {s}{s} Daemon Running{s}\n", .{ Color.green, Symbols.check, Color.reset });
                try writer.print("  Containers: {d} running, {d} stopped\n", .{ docker.running_count, docker.stopped_count });
                try writer.print("  Images: {d} ({s})\n", .{ docker.image_count, formatBytes(@intCast(docker.total_image_size)) });
                if (docker.dangling_images_size > 0) {
                    try writer.print("  {s}{s} Dangling Images: {s}{s}\n", .{ Color.yellow, Symbols.warning, formatBytes(@intCast(docker.dangling_images_size)), Color.reset });
                }
            } else {
                try writer.print("  {s}{s} Daemon Not Running{s}\n", .{ Color.red, Symbols.cross, Color.reset });
            }
        }
    }

    // Snaps Section
    if (r.snaps) |snaps| {
        if (snaps.available) {
            try renderSection(writer, "SNAPS");
            if (snaps.snaps) |snap_list| {
                try writer.print("  Installed: {d} snaps\n", .{snap_list.len});
            }
            try writer.print("  Disk Usage: {s}\n", .{formatBytes(@intCast(snaps.total_disk_usage))});
            if (snaps.pending_refreshes > 0) {
                try writer.print("  {s}{s} Pending Refreshes: {d}{s}\n", .{ Color.yellow, Symbols.warning, snaps.pending_refreshes, Color.reset });
            }
        }
    }

    // GPU Section
    if (r.gpu) |gpu| {
        if (gpu.available) {
            if (gpu.gpus) |gpus| {
                try renderSection(writer, "GPU");
                for (gpus) |g| {
                    try writer.print("  {s}\n", .{g.name});
                    if (g.temperature > 0) {
                        const temp_color = if (g.temperature >= 90) Color.red else if (g.temperature >= 80) Color.yellow else Color.green;
                        try writer.print("    Temperature: {s}{d}C{s}\n", .{ temp_color, g.temperature, Color.reset });
                    }
                    if (g.utilization > 0) {
                        try writer.print("    Utilization: {d}%\n", .{g.utilization});
                    }
                    if (g.memory_total > 0) {
                        try writer.print("    Memory: {s} / {s}\n", .{ formatBytes(@intCast(g.memory_used)), formatBytes(@intCast(g.memory_total)) });
                    }
                }
            }
        }
    }

    // Logs Section
    if (r.logs) |logs| {
        if (logs.available) {
            try renderSection(writer, "LOGS (24h)");
            if (logs.stats.critical_count > 0) {
                try writer.print("  {s}{s} Critical: {d}{s}\n", .{ Color.red, Symbols.cross, logs.stats.critical_count, Color.reset });
            }
            try writer.print("  Errors: {d}\n", .{logs.stats.error_count});
            if (logs.stats.oom_events > 0) {
                try writer.print("  {s}{s} OOM Events: {d}{s}\n", .{ Color.red, Symbols.cross, logs.stats.oom_events, Color.reset });
            }
            if (logs.stats.kernel_panics > 0) {
                try writer.print("  {s}{s} Kernel Panics: {d}{s}\n", .{ Color.bright_red, Symbols.cross, logs.stats.kernel_panics, Color.reset });
            }
            if (logs.stats.segfaults > 0) {
                try writer.print("  {s}{s} Segfaults: {d}{s}\n", .{ Color.yellow, Symbols.warning, logs.stats.segfaults, Color.reset });
            }
            if (logs.stats.top_errors) |top_errors| {
                if (top_errors.len > 0) {
                    try writer.print("\n  {s}Top Error Patterns:{s}\n", .{ Color.bold, Color.reset });
                    for (top_errors) |err| {
                        try writer.print("    [{d}] {s}...\n", .{ err.count, err.pattern });
                    }
                }
            }
        }
    }

    // Issues Section
    if (r.issues.len > 0) {
        try renderSection(writer, "ISSUES");

        // Count by severity
        var critical: usize = 0;
        var warnings: usize = 0;
        var infos: usize = 0;
        for (r.issues) |issue| {
            if (std.mem.eql(u8, issue.severity, "critical")) {
                critical += 1;
            } else if (std.mem.eql(u8, issue.severity, "warning")) {
                warnings += 1;
            } else {
                infos += 1;
            }
        }

        try writer.print("  Summary: ", .{});
        if (critical > 0) try writer.print("{s}{d} critical{s} ", .{ Color.bright_red, critical, Color.reset });
        if (warnings > 0) try writer.print("{s}{d} warnings{s} ", .{ Color.yellow, warnings, Color.reset });
        if (infos > 0) try writer.print("{s}{d} info{s}", .{ Color.dim, infos, Color.reset });
        try writer.writeAll("\n\n");

        for (r.issues) |issue| {
            const sev_color = if (std.mem.eql(u8, issue.severity, "critical"))
                Color.bright_red
            else if (std.mem.eql(u8, issue.severity, "warning"))
                Color.yellow
            else
                Color.dim;

            const symbol = if (std.mem.eql(u8, issue.severity, "critical"))
                Symbols.cross
            else if (std.mem.eql(u8, issue.severity, "warning"))
                Symbols.warning
            else
                Symbols.info;

            try writer.print("  {s}{s} [{s}] {s}{s}\n", .{ sev_color, symbol, issue.category, issue.title, Color.reset });
            try writer.print("    {s}\n", .{issue.description});
            if (issue.fix) |fix| {
                try writer.print("    {s}Fix: {s}{s}\n", .{ Color.dim, fix, Color.reset });
            }
            try writer.writeAll("\n");
        }
    }

    // Footer
    try writer.print("{s}═══════════════════════════════════════════════════════════════{s}\n", .{ Color.cyan, Color.reset });

    return alloc_writer.toOwnedSlice();
}

fn renderSection(writer: *std.Io.Writer, title: []const u8) !void {
    try writer.print("\n{s}── {s} ──{s}\n", .{ Color.cyan, title, Color.reset });
}

fn renderProgressBar(writer: *std.Io.Writer, prefix: []const u8, percent: f64, color: []const u8) !void {
    const width: usize = 30;
    const filled: usize = @intFromFloat(percent / 100.0 * @as(f64, @floatFromInt(width)));

    try writer.print("{s}[", .{prefix});
    var i: usize = 0;
    while (i < width) : (i += 1) {
        if (i < filled) {
            try writer.print("{s}█{s}", .{ color, Color.reset });
        } else {
            try writer.writeAll("░");
        }
    }
    try writer.writeAll("] ");
}

fn getStatusColor(percent: f64, warn_threshold: f64, crit_threshold: f64) []const u8 {
    if (percent >= crit_threshold) return Color.red;
    if (percent >= warn_threshold) return Color.yellow;
    return Color.green;
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

    _ = std.fmt.bufPrint(&buf, "{d:.1} {s}", .{ value, units[unit_idx] }) catch {
        @memcpy(buf[0..3], "N/A");
    };
    return buf;
}
