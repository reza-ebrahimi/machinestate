const std = @import("std");
const report = @import("../models/report.zig");
const system = @import("system.zig");
const disk = @import("disk.zig");
const network = @import("network.zig");
const packages = @import("packages.zig");
const services = @import("services.zig");
const security = @import("security.zig");
const hardware = @import("hardware.zig");
const docker = @import("docker.zig");
const snaps = @import("snaps.zig");
const gpu = @import("gpu.zig");
const logs = @import("logs.zig");

// Re-export individual collector functions for HTTP server
pub const collectSystemInfo = system.collectSystemInfo;
pub const collectDiskInfo = disk.collectDiskInfo;
pub const collectNetworkInfo = network.collectNetworkInfo;
pub const collectPackageInfo = packages.collectPackageInfo;
pub const collectServiceInfo = services.collectServiceInfo;
pub const collectSecurityInfo = security.collectSecurityInfo;
pub const collectHardwareInfo = hardware.collectHardwareInfo;
pub const collectDockerInfo = docker.collectDockerInfo;
pub const collectSnapInfo = snaps.collectSnapInfo;
pub const collectGPUInfo = gpu.collectGPUInfo;
pub const collectLogInfo = logs.collectLogInfo;

/// Collect all system information and return a complete report
pub fn collectAll(allocator: std.mem.Allocator) !report.Report {
    var r = report.emptyReport();

    // Get hostname
    var hostname_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname_slice = std.posix.gethostname(&hostname_buf) catch "unknown";
    r.hostname = try allocator.dupe(u8, hostname_slice);

    // Get timestamp in RFC3339 format
    const ts = std.posix.clock_gettime(.REALTIME) catch std.posix.timespec{ .sec = 0, .nsec = 0 };
    var ts_buf: [30]u8 = undefined;
    r.timestamp = try allocator.dupe(u8, formatTimestamp(ts.sec, &ts_buf));

    // Collect OS info
    r.os = system.collectOSInfo(allocator);

    // Collect system metrics (CPU, memory, load, etc.)
    r.system = system.collectSystemInfo(allocator);

    // Collect disk info
    r.disk = disk.collectDiskInfo(allocator);

    // Collect network info
    r.network = network.collectNetworkInfo(allocator);

    // Collect package info
    r.packages = packages.collectPackageInfo(allocator);

    // Collect service info
    r.services = services.collectServiceInfo(allocator);

    // Collect security info
    r.security = security.collectSecurityInfo(allocator);

    // Collect hardware info
    r.hardware = hardware.collectHardwareInfo(allocator);

    // Collect docker info (optional)
    r.docker = docker.collectDockerInfo(allocator);

    // Collect snap info (optional)
    r.snaps = snaps.collectSnapInfo(allocator);

    // Collect GPU info (optional)
    r.gpu = gpu.collectGPUInfo(allocator);

    // Collect log info (optional)
    r.logs = logs.collectLogInfo(allocator);

    // Analyze issues based on collected data
    r.issues = try analyzeIssues(allocator, &r);

    return r;
}

fn formatTimestamp(timestamp: i64, buf: []u8) []const u8 {
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
    const year_day = epoch_seconds.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    const hours = day_seconds.getHoursIntoDay();
    const minutes = day_seconds.getMinutesIntoHour();
    const seconds = day_seconds.getSecondsIntoMinute();

    const year: u16 = @intCast(year_day.year);
    const month: u8 = @intFromEnum(month_day.month);
    const day: u8 = month_day.day_index + 1;

    const result = std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year,
        month,
        day,
        hours,
        minutes,
        seconds,
    }) catch return "1970-01-01T00:00:00Z";

    return result;
}

fn analyzeIssues(allocator: std.mem.Allocator, r: *const report.Report) ![]const report.Issue {
    var issues = std.ArrayList(report.Issue).empty;

    // Default thresholds
    const disk_warning_percent: f64 = 80;
    const disk_critical_percent: f64 = 90;

    // Check disk usage
    for (r.disk.filesystems) |fs| {
        if (fs.used_percent >= disk_critical_percent) {
            try issues.append(allocator, report.Issue{
                .severity = report.Severity.critical,
                .category = "Disk",
                .title = try std.fmt.allocPrint(allocator, "Disk space critical: {s}", .{fs.mount_point}),
                .description = try std.fmt.allocPrint(allocator, "Filesystem usage is at {d:.1}%", .{fs.used_percent}),
                .fix = "Free up disk space or expand the partition",
            });
        } else if (fs.used_percent >= disk_warning_percent) {
            try issues.append(allocator, report.Issue{
                .severity = report.Severity.warning,
                .category = "Disk",
                .title = try std.fmt.allocPrint(allocator, "Disk space warning: {s}", .{fs.mount_point}),
                .description = try std.fmt.allocPrint(allocator, "Filesystem usage is at {d:.1}%", .{fs.used_percent}),
                .fix = "Consider cleaning up unused files",
            });
        }

        if (fs.inodes_percent >= 90) {
            try issues.append(allocator, report.Issue{
                .severity = report.Severity.warning,
                .category = "Disk",
                .title = try std.fmt.allocPrint(allocator, "Inodes running low: {s}", .{fs.mount_point}),
                .description = try std.fmt.allocPrint(allocator, "Inode usage is at {d:.1}%", .{fs.inodes_percent}),
                .fix = "Remove small files or directories with many files",
            });
        }
    }

    // Check memory
    if (r.system.memory_percent >= 90) {
        try issues.append(allocator, report.Issue{
            .severity = report.Severity.warning,
            .category = "Memory",
            .title = "High memory usage",
            .description = try std.fmt.allocPrint(allocator, "Memory usage is at {d:.1}%", .{r.system.memory_percent}),
            .fix = "Close unused applications or add more RAM",
        });
    }

    // Check swap
    if (r.system.swap_percent >= 80) {
        try issues.append(allocator, report.Issue{
            .severity = report.Severity.warning,
            .category = "Memory",
            .title = "High swap usage",
            .description = try std.fmt.allocPrint(allocator, "Swap usage is at {d:.1}%", .{r.system.swap_percent}),
            .fix = "Consider adding more RAM if swap is frequently used",
        });
    }

    // Check load average
    if (r.system.cpu_cores > 0) {
        const load_per_core = r.system.load_avg_1 / @as(f64, @floatFromInt(r.system.cpu_cores));
        if (load_per_core >= 2.0) {
            try issues.append(allocator, report.Issue{
                .severity = report.Severity.critical,
                .category = "CPU",
                .title = "System overloaded",
                .description = "Load average is very high relative to CPU cores",
                .fix = "Identify and stop resource-intensive processes",
            });
        } else if (load_per_core >= 1.0) {
            try issues.append(allocator, report.Issue{
                .severity = report.Severity.warning,
                .category = "CPU",
                .title = "High system load",
                .description = "Load average is elevated",
                .fix = "Monitor CPU-intensive processes",
            });
        }
    }

    // Check failed services
    if (r.services.failed_units.len > 0) {
        try issues.append(allocator, report.Issue{
            .severity = report.Severity.warning,
            .category = "Services",
            .title = "Failed systemd services",
            .description = try std.fmt.allocPrint(allocator, "There are {d} failed service(s)", .{r.services.failed_units.len}),
            .fix = "Run: systemctl status <service> to investigate",
        });
    }

    // Check zombie processes
    if (r.services.zombie_count > 0) {
        try issues.append(allocator, report.Issue{
            .severity = report.Severity.info,
            .category = "Processes",
            .title = "Zombie processes detected",
            .description = try std.fmt.allocPrint(allocator, "Found {d} zombie process(es)", .{r.services.zombie_count}),
            .fix = "Usually harmless; parent process should clean them up",
        });
    }

    // Check pending updates
    if (r.packages.updates_available > 50) {
        try issues.append(allocator, report.Issue{
            .severity = report.Severity.warning,
            .category = "Packages",
            .title = "Many pending updates",
            .description = try std.fmt.allocPrint(allocator, "{d} packages need updating", .{r.packages.updates_available}),
            .fix = "Run: sudo apt update && sudo apt upgrade",
        });
    } else if (r.packages.updates_available > 0) {
        try issues.append(allocator, report.Issue{
            .severity = report.Severity.info,
            .category = "Packages",
            .title = "Updates available",
            .description = try std.fmt.allocPrint(allocator, "{d} packages can be updated", .{r.packages.updates_available}),
            .fix = "Run: sudo apt update && sudo apt upgrade",
        });
    }

    // Check security updates
    if (r.packages.security_updates > 0) {
        try issues.append(allocator, report.Issue{
            .severity = report.Severity.warning,
            .category = "Security",
            .title = "Security updates pending",
            .description = try std.fmt.allocPrint(allocator, "{d} security updates available", .{r.packages.security_updates}),
            .fix = "Run: sudo apt update && sudo apt upgrade",
        });
    }

    // Check firewall
    if (!r.security.firewall_active) {
        try issues.append(allocator, report.Issue{
            .severity = report.Severity.warning,
            .category = "Security",
            .title = "Firewall not active",
            .description = "UFW firewall is not enabled",
            .fix = "Run: sudo ufw enable",
        });
    }

    // Check battery health
    if (r.hardware.battery) |bat| {
        if (bat.health < 50) {
            try issues.append(allocator, report.Issue{
                .severity = report.Severity.critical,
                .category = "Hardware",
                .title = "Battery health degraded",
                .description = try std.fmt.allocPrint(allocator, "Battery health is at {d:.1}%", .{bat.health}),
                .fix = "Consider replacing the battery",
            });
        } else if (bat.health < 80) {
            try issues.append(allocator, report.Issue{
                .severity = report.Severity.warning,
                .category = "Hardware",
                .title = "Battery wear detected",
                .description = try std.fmt.allocPrint(allocator, "Battery health is at {d:.1}%", .{bat.health}),
                .fix = "Battery showing normal wear; monitor over time",
            });
        }
    }

    // Check temperatures
    if (r.hardware.temperatures) |temps| {
        for (temps) |temp| {
            if (temp.critical) |crit| {
                if (temp.current >= crit) {
                    try issues.append(allocator, report.Issue{
                        .severity = report.Severity.critical,
                        .category = "Hardware",
                        .title = try std.fmt.allocPrint(allocator, "Critical temperature: {s}", .{temp.label}),
                        .description = try std.fmt.allocPrint(allocator, "Temperature is {d:.1}°C (critical threshold)", .{temp.current}),
                        .fix = "Check cooling system; reduce load",
                    });
                    continue;
                }
            }
            if (temp.high) |high| {
                if (temp.current >= high) {
                    try issues.append(allocator, report.Issue{
                        .severity = report.Severity.warning,
                        .category = "Hardware",
                        .title = try std.fmt.allocPrint(allocator, "High temperature: {s}", .{temp.label}),
                        .description = try std.fmt.allocPrint(allocator, "Temperature is {d:.1}°C", .{temp.current}),
                        .fix = "Monitor temperature; check cooling",
                    });
                    continue;
                }
            }
            if (temp.current >= 85) {
                try issues.append(allocator, report.Issue{
                    .severity = report.Severity.warning,
                    .category = "Hardware",
                    .title = try std.fmt.allocPrint(allocator, "Elevated temperature: {s}", .{temp.label}),
                    .description = try std.fmt.allocPrint(allocator, "Temperature is {d:.1}°C", .{temp.current}),
                    .fix = "Check cooling system",
                });
            }
        }
    }

    // Check crash reports
    if (r.hardware.crash_reports) |crashes| {
        if (crashes.len > 0) {
            try issues.append(allocator, report.Issue{
                .severity = report.Severity.warning,
                .category = "System",
                .title = "Crash reports present",
                .description = try std.fmt.allocPrint(allocator, "{d} crash report(s) in /var/crash", .{crashes.len}),
                .fix = "Review with: apport-cli /var/crash/<file>; then remove old reports",
            });
        }
    }

    // Check network connectivity
    if (!r.network.connectivity) {
        try issues.append(allocator, report.Issue{
            .severity = report.Severity.warning,
            .category = "Network",
            .title = "No internet connectivity",
            .description = "Unable to reach external DNS servers",
            .fix = "Check network configuration and connection",
        });
    }

    // Check reboot required
    if (r.system.reboot_required) {
        try issues.append(allocator, report.Issue{
            .severity = report.Severity.warning,
            .category = "System",
            .title = "Reboot required",
            .description = "System updates require a reboot to take effect",
            .fix = "Schedule a system reboot when convenient",
        });
    }

    // Check uptime (> 30 days)
    const uptime_days = @divFloor(r.system.uptime, 86400000000000);
    if (uptime_days > 30) {
        try issues.append(allocator, report.Issue{
            .severity = report.Severity.warning,
            .category = "System",
            .title = "Long uptime",
            .description = try std.fmt.allocPrint(allocator, "System has been running for {d} days without reboot", .{uptime_days}),
            .fix = "Consider scheduling a reboot to apply kernel updates",
        });
    }

    // Check Docker dangling images
    if (r.docker) |dock| {
        if (dock.available and dock.dangling_images_size > 1024 * 1024 * 1024) {
            try issues.append(allocator, report.Issue{
                .severity = report.Severity.warning,
                .category = "Docker",
                .title = "Large dangling images",
                .description = "Dangling Docker images are using significant disk space",
                .fix = "Run: docker image prune to clean up",
            });
        }
    }

    // Check GPU temperature
    if (r.gpu) |g| {
        if (g.gpus) |gpus| {
            for (gpus) |gpu_dev| {
                if (gpu_dev.temperature >= 90) {
                    try issues.append(allocator, report.Issue{
                        .severity = report.Severity.critical,
                        .category = "Hardware",
                        .title = try std.fmt.allocPrint(allocator, "GPU temperature critical: {s}", .{gpu_dev.name}),
                        .description = try std.fmt.allocPrint(allocator, "GPU temperature is at {d}°C", .{gpu_dev.temperature}),
                        .fix = "Check GPU cooling; reduce workload",
                    });
                } else if (gpu_dev.temperature >= 80) {
                    try issues.append(allocator, report.Issue{
                        .severity = report.Severity.warning,
                        .category = "Hardware",
                        .title = try std.fmt.allocPrint(allocator, "GPU temperature high: {s}", .{gpu_dev.name}),
                        .description = try std.fmt.allocPrint(allocator, "GPU temperature is at {d}°C", .{gpu_dev.temperature}),
                        .fix = "Monitor GPU temperature; ensure adequate cooling",
                    });
                }
            }
        }
    }

    // Check for OOM events
    if (r.logs) |lg| {
        if (lg.stats.oom_events > 0) {
            try issues.append(allocator, report.Issue{
                .severity = report.Severity.warning,
                .category = "Memory",
                .title = "OOM events detected",
                .description = try std.fmt.allocPrint(allocator, "{d} out-of-memory event(s) in the last 24 hours", .{lg.stats.oom_events}),
                .fix = "Review memory usage; consider adding RAM or reducing memory-intensive applications",
            });
        }

        // Check for kernel panics
        if (lg.stats.kernel_panics > 0) {
            try issues.append(allocator, report.Issue{
                .severity = report.Severity.critical,
                .category = "System",
                .title = "Kernel panics detected",
                .description = try std.fmt.allocPrint(allocator, "{d} kernel panic(s) in the last 24 hours", .{lg.stats.kernel_panics}),
                .fix = "Review system logs; check hardware and drivers",
            });
        }
    }

    return issues.toOwnedSlice(allocator);
}

test "formatTimestamp" {
    var buf: [30]u8 = undefined;
    const ts = formatTimestamp(1735560000, &buf);
    try std.testing.expect(ts.len > 0);
    try std.testing.expect(ts[4] == '-');
    try std.testing.expect(ts[10] == 'T');
}
