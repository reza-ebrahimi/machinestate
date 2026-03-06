const std = @import("std");
const report = @import("../models/report.zig");

/// Render report as standalone HTML (matching Go implementation)
pub fn renderHtml(allocator: std.mem.Allocator, r: *const report.Report) ![]u8 {
    var alloc_writer = std.Io.Writer.Allocating.init(allocator);
    errdefer alloc_writer.deinit();
    const w = &alloc_writer.writer;

    // Count issues by severity
    var critical_count: u32 = 0;
    var warning_count: u32 = 0;
    var info_count: u32 = 0;
    for (r.issues) |issue| {
        if (std.mem.eql(u8, issue.severity, "critical")) {
            critical_count += 1;
        } else if (std.mem.eql(u8, issue.severity, "warning")) {
            warning_count += 1;
        } else {
            info_count += 1;
        }
    }

    // HTML header with embedded CSS (matching Go's styling)
    try w.writeAll(
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\    <meta charset="UTF-8">
        \\    <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\
    );
    try w.print("    <title>System State Report - {s}</title>\n", .{r.hostname});
    try w.writeAll(
        \\    <style>
        \\        :root {
        \\            --bg: #0d1117;
        \\            --card-bg: #161b22;
        \\            --border: #30363d;
        \\            --text: #c9d1d9;
        \\            --text-dim: #8b949e;
        \\            --accent: #58a6ff;
        \\            --success: #3fb950;
        \\            --warning: #d29922;
        \\            --error: #f85149;
        \\            --critical: #ff7b72;
        \\        }
        \\        * { box-sizing: border-box; margin: 0; padding: 0; }
        \\        body {
        \\            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
        \\            background: var(--bg);
        \\            color: var(--text);
        \\            line-height: 1.6;
        \\            padding: 20px;
        \\        }
        \\        .container { max-width: 1200px; margin: 0 auto; }
        \\        h1 {
        \\            text-align: center;
        \\            padding: 20px;
        \\            border-bottom: 1px solid var(--border);
        \\            margin-bottom: 20px;
        \\        }
        \\        .header-info {
        \\            display: grid;
        \\            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
        \\            gap: 10px;
        \\            margin-bottom: 20px;
        \\            padding: 15px;
        \\            background: var(--card-bg);
        \\            border-radius: 8px;
        \\            border: 1px solid var(--border);
        \\        }
        \\        .header-info div { color: var(--text-dim); }
        \\        .header-info span { color: var(--text); font-weight: 500; }
        \\        .issues-summary {
        \\            display: flex;
        \\            gap: 15px;
        \\            margin-bottom: 20px;
        \\            flex-wrap: wrap;
        \\        }
        \\        .issue-badge {
        \\            padding: 10px 20px;
        \\            border-radius: 8px;
        \\            font-weight: 600;
        \\        }
        \\        .issue-badge.critical { background: rgba(248, 81, 73, 0.2); color: var(--critical); border: 1px solid var(--critical); }
        \\        .issue-badge.warning { background: rgba(210, 153, 34, 0.2); color: var(--warning); border: 1px solid var(--warning); }
        \\        .issue-badge.info { background: rgba(88, 166, 255, 0.2); color: var(--accent); border: 1px solid var(--accent); }
        \\        .issue-badge.success { background: rgba(63, 185, 80, 0.2); color: var(--success); border: 1px solid var(--success); }
        \\        .section {
        \\            background: var(--card-bg);
        \\            border: 1px solid var(--border);
        \\            border-radius: 8px;
        \\            margin-bottom: 20px;
        \\            overflow: hidden;
        \\        }
        \\        .section-title {
        \\            background: rgba(88, 166, 255, 0.1);
        \\            padding: 12px 20px;
        \\            font-weight: 600;
        \\            color: var(--accent);
        \\            border-bottom: 1px solid var(--border);
        \\        }
        \\        .section-content { padding: 15px 20px; }
        \\        table {
        \\            width: 100%;
        \\            border-collapse: collapse;
        \\        }
        \\        th, td {
        \\            padding: 10px 15px;
        \\            text-align: left;
        \\            border-bottom: 1px solid var(--border);
        \\        }
        \\        th { color: var(--text-dim); font-weight: 500; }
        \\        tr:last-child td { border-bottom: none; }
        \\        .status-up { color: var(--success); }
        \\        .status-down { color: var(--text-dim); }
        \\        .status-ok { color: var(--success); }
        \\        .status-warn { color: var(--warning); }
        \\        .status-error { color: var(--error); }
        \\        .progress-bar {
        \\            background: var(--border);
        \\            border-radius: 4px;
        \\            height: 8px;
        \\            overflow: hidden;
        \\            width: 100px;
        \\            display: inline-block;
        \\            vertical-align: middle;
        \\            margin-left: 10px;
        \\        }
        \\        .progress-fill {
        \\            height: 100%;
        \\            border-radius: 4px;
        \\        }
        \\        .progress-ok { background: var(--success); }
        \\        .progress-warn { background: var(--warning); }
        \\        .progress-error { background: var(--error); }
        \\        .issue-card {
        \\            padding: 15px;
        \\            margin-bottom: 10px;
        \\            border-radius: 6px;
        \\            border-left: 4px solid;
        \\        }
        \\        .issue-card.critical { border-color: var(--critical); background: rgba(248, 81, 73, 0.1); }
        \\        .issue-card.warning { border-color: var(--warning); background: rgba(210, 153, 34, 0.1); }
        \\        .issue-card.info { border-color: var(--accent); background: rgba(88, 166, 255, 0.1); }
        \\        .issue-title { font-weight: 600; margin-bottom: 5px; }
        \\        .issue-category { color: var(--text-dim); font-size: 0.9em; }
        \\        .issue-fix { color: var(--success); margin-top: 8px; font-family: monospace; font-size: 0.9em; }
        \\        .grid-2 { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        \\        .kv-row { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid var(--border); }
        \\        .kv-row:last-child { border-bottom: none; }
        \\        .kv-key { color: var(--text-dim); }
        \\        .kv-value { font-weight: 500; }
        \\        footer {
        \\            text-align: center;
        \\            padding: 20px;
        \\            color: var(--text-dim);
        \\            font-size: 0.9em;
        \\        }
        \\    </style>
        \\</head>
        \\<body>
        \\    <div class="container">
        \\        <h1>System State Report</h1>
        \\
        \\
    );

    // Header info card
    try w.writeAll("        <div class=\"header-info\">\n");
    try w.print("            <div>Hostname: <span>{s}</span></div>\n", .{r.hostname});
    try w.print("            <div>OS: <span>{s}</span></div>\n", .{r.os.name});
    try w.print("            <div>Kernel: <span>{s}</span></div>\n", .{r.os.kernel});
    try w.print("            <div>Uptime: <span>{s}</span></div>\n", .{r.system.uptime_human});
    try w.print("            <div>Report Time: <span>{s}</span></div>\n", .{r.timestamp});
    try w.writeAll("        </div>\n\n");

    // Issues summary badges
    try w.writeAll("        <div class=\"issues-summary\">\n");
    if (critical_count > 0) {
        try w.print("            <div class=\"issue-badge critical\">{d} Critical</div>\n", .{critical_count});
    }
    if (warning_count > 0) {
        try w.print("            <div class=\"issue-badge warning\">{d} Warnings</div>\n", .{warning_count});
    }
    if (info_count > 0) {
        try w.print("            <div class=\"issue-badge info\">{d} Info</div>\n", .{info_count});
    }
    if (critical_count == 0 and warning_count == 0 and info_count == 0) {
        try w.writeAll("            <div class=\"issue-badge success\">✓ No Issues Detected</div>\n");
    }
    try w.writeAll("        </div>\n\n");

    // System + Packages in 2-column grid
    try w.writeAll("        <div class=\"grid-2\">\n");

    // System section
    try w.writeAll("            <div class=\"section\">\n");
    try w.writeAll("                <div class=\"section-title\">System</div>\n");
    try w.writeAll("                <div class=\"section-content\">\n");
    try w.print(
        \\                    <div class="kv-row">
        \\                        <span class="kv-key">Load Average</span>
        \\                        <span class="kv-value">{d:.2} / {d:.2} / {d:.2}</span>
        \\                    </div>
        \\
    , .{ r.system.load_avg_1, r.system.load_avg_5, r.system.load_avg_15 });
    try w.print(
        \\                    <div class="kv-row">
        \\                        <span class="kv-key">CPU</span>
        \\                        <span class="kv-value">{d} cores @ {d:.1}%</span>
        \\                    </div>
        \\
    , .{ r.system.cpu_cores, r.system.cpu_usage });

    // Memory with progress bar
    const mem_status = if (r.system.memory_percent >= 90) "status-error" else if (r.system.memory_percent >= 80) "status-warn" else "status-ok";
    const mem_progress = if (r.system.memory_percent >= 90) "progress-error" else if (r.system.memory_percent >= 80) "progress-warn" else "progress-ok";
    try w.print(
        \\                    <div class="kv-row">
        \\                        <span class="kv-key">Memory</span>
        \\                        <span class="kv-value {s}">
        \\                            {s} / {s} ({d:.1}%)
        \\                            <div class="progress-bar"><div class="progress-fill {s}" style="width: {d:.0}%"></div></div>
        \\                        </span>
        \\                    </div>
        \\
    , .{ mem_status, formatBytes(r.system.memory_used), formatBytes(r.system.memory_total), r.system.memory_percent, mem_progress, r.system.memory_percent });

    // Swap
    if (r.system.swap_total > 0) {
        try w.print(
            \\                    <div class="kv-row">
            \\                        <span class="kv-key">Swap</span>
            \\                        <span class="kv-value">{s} / {s} ({d:.1}%)</span>
            \\                    </div>
            \\
        , .{ formatBytes(r.system.swap_used), formatBytes(r.system.swap_total), r.system.swap_percent });
    }
    try w.writeAll("                </div>\n");
    try w.writeAll("            </div>\n\n");

    // Packages section
    try w.writeAll("            <div class=\"section\">\n");
    try w.writeAll("                <div class=\"section-title\">Packages</div>\n");
    try w.writeAll("                <div class=\"section-content\">\n");
    const updates_status = if (r.packages.updates_available > 0) "status-warn" else "status-ok";
    try w.print(
        \\                    <div class="kv-row">
        \\                        <span class="kv-key">Updates Available</span>
        \\                        <span class="kv-value {s}">{d}</span>
        \\                    </div>
        \\
    , .{ updates_status, r.packages.updates_available });
    if (r.packages.security_updates > 0) {
        try w.print(
            \\                    <div class="kv-row">
            \\                        <span class="kv-key">Security Updates</span>
            \\                        <span class="kv-value status-error">{d}</span>
            \\                    </div>
            \\
        , .{r.packages.security_updates});
    }
    const broken_status = if (r.packages.broken_packages > 0) "status-error" else "status-ok";
    try w.print(
        \\                    <div class="kv-row">
        \\                        <span class="kv-key">Broken Packages</span>
        \\                        <span class="kv-value {s}">{d}</span>
        \\                    </div>
        \\
    , .{ broken_status, r.packages.broken_packages });
    try w.writeAll("                </div>\n");
    try w.writeAll("            </div>\n");
    try w.writeAll("        </div>\n\n");

    // Disk section
    try w.writeAll("        <div class=\"section\">\n");
    try w.writeAll("            <div class=\"section-title\">Disk</div>\n");
    try w.writeAll("            <div class=\"section-content\">\n");
    try w.writeAll("                <table>\n");
    try w.writeAll("                    <thead>\n");
    try w.writeAll("                        <tr>\n");
    try w.writeAll("                            <th>Mount Point</th>\n");
    try w.writeAll("                            <th>Size</th>\n");
    try w.writeAll("                            <th>Used</th>\n");
    try w.writeAll("                            <th>Free</th>\n");
    try w.writeAll("                            <th>Usage</th>\n");
    try w.writeAll("                        </tr>\n");
    try w.writeAll("                    </thead>\n");
    try w.writeAll("                    <tbody>\n");
    for (r.disk.filesystems) |fs| {
        const disk_status = if (fs.used_percent >= 90) "status-error" else if (fs.used_percent >= 80) "status-warn" else "status-ok";
        const disk_progress = if (fs.used_percent >= 90) "progress-error" else if (fs.used_percent >= 80) "progress-warn" else "progress-ok";
        try w.print(
            \\                        <tr>
            \\                            <td>{s}</td>
            \\                            <td>{s}</td>
            \\                            <td>{s}</td>
            \\                            <td>{s}</td>
            \\                            <td>
            \\                                <span class="{s}">{d:.1}%</span>
            \\                                <div class="progress-bar"><div class="progress-fill {s}" style="width: {d:.0}%"></div></div>
            \\                            </td>
            \\                        </tr>
            \\
        , .{ fs.mount_point, formatBytes(fs.total), formatBytes(fs.used), formatBytes(fs.free), disk_status, fs.used_percent, disk_progress, fs.used_percent });
    }
    try w.writeAll("                    </tbody>\n");
    try w.writeAll("                </table>\n");
    try w.writeAll("            </div>\n");
    try w.writeAll("        </div>\n\n");

    // Network section
    try w.writeAll("        <div class=\"section\">\n");
    try w.writeAll("            <div class=\"section-title\">Network</div>\n");
    try w.writeAll("            <div class=\"section-content\">\n");
    try w.writeAll("                <table>\n");
    try w.writeAll("                    <thead>\n");
    try w.writeAll("                        <tr>\n");
    try w.writeAll("                            <th>Interface</th>\n");
    try w.writeAll("                            <th>State</th>\n");
    try w.writeAll("                            <th>IP Addresses</th>\n");
    try w.writeAll("                            <th>RX</th>\n");
    try w.writeAll("                            <th>TX</th>\n");
    try w.writeAll("                        </tr>\n");
    try w.writeAll("                    </thead>\n");
    try w.writeAll("                    <tbody>\n");
    for (r.network.interfaces) |iface| {
        const state_class = if (std.mem.eql(u8, iface.state, "UP")) "status-up" else "status-down";
        try w.print("                        <tr>\n", .{});
        try w.print("                            <td>{s}</td>\n", .{iface.name});
        try w.print("                            <td class=\"{s}\">{s}</td>\n", .{ state_class, iface.state });
        try w.writeAll("                            <td>");
        // Join IPs
        for (iface.ips, 0..) |ip, i| {
            if (i > 0) try w.writeAll(", ");
            try w.writeAll(ip);
        }
        try w.writeAll("</td>\n");
        try w.print("                            <td>{s}</td>\n", .{formatBytes(iface.rx_bytes)});
        try w.print("                            <td>{s}</td>\n", .{formatBytes(iface.tx_bytes)});
        try w.writeAll("                        </tr>\n");
    }
    try w.writeAll("                    </tbody>\n");
    try w.writeAll("                </table>\n");
    try w.writeAll("                <div style=\"margin-top: 15px;\">\n");
    try w.writeAll("                    <span class=\"kv-key\">Internet: </span>\n");
    if (r.network.connectivity) {
        try w.writeAll("                    <span class=\"status-ok\">Connected</span>\n");
    } else {
        try w.writeAll("                    <span class=\"status-error\">Disconnected</span>\n");
    }
    try w.writeAll("                </div>\n");
    try w.writeAll("            </div>\n");
    try w.writeAll("        </div>\n\n");

    // Security + Services in 2-column grid
    try w.writeAll("        <div class=\"grid-2\">\n");

    // Security section
    try w.writeAll("            <div class=\"section\">\n");
    try w.writeAll("                <div class=\"section-title\">Security</div>\n");
    try w.writeAll("                <div class=\"section-content\">\n");
    const firewall_status = if (r.security.firewall_active) "status-ok" else "status-error";
    const firewall_text = if (r.security.firewall_active) "Active" else "Inactive";
    try w.print(
        \\                    <div class="kv-row">
        \\                        <span class="kv-key">Firewall</span>
        \\                        <span class="kv-value {s}">{s}</span>
        \\                    </div>
        \\
    , .{ firewall_status, firewall_text });
    const ssh_text = if (r.security.ssh_enabled) "Enabled" else "Disabled";
    try w.print(
        \\                    <div class="kv-row">
        \\                        <span class="kv-key">SSH</span>
        \\                        <span class="kv-value">{s}</span>
        \\                    </div>
        \\
    , .{ssh_text});
    if (r.security.failed_logins_24h > 0) {
        try w.print(
            \\                    <div class="kv-row">
            \\                        <span class="kv-key">Failed Logins (24h)</span>
            \\                        <span class="kv-value status-warn">{d}</span>
            \\                    </div>
            \\
        , .{r.security.failed_logins_24h});
    }
    const open_ports_count = r.security.open_ports.len;
    try w.print(
        \\                    <div class="kv-row">
        \\                        <span class="kv-key">Open Ports (0.0.0.0)</span>
        \\                        <span class="kv-value">{d}</span>
        \\                    </div>
        \\
    , .{open_ports_count});
    try w.writeAll("                </div>\n");
    try w.writeAll("            </div>\n\n");

    // Services section
    try w.writeAll("            <div class=\"section\">\n");
    try w.writeAll("                <div class=\"section-title\">Services</div>\n");
    try w.writeAll("                <div class=\"section-content\">\n");
    const failed_count = r.services.failed_units.len;
    const failed_status = if (failed_count > 0) "status-error" else "status-ok";
    try w.print(
        \\                    <div class="kv-row">
        \\                        <span class="kv-key">Failed Services</span>
        \\                        <span class="kv-value {s}">{d}</span>
        \\                    </div>
        \\
    , .{ failed_status, failed_count });
    const zombie_status = if (r.services.zombie_count > 0) "status-warn" else "status-ok";
    try w.print(
        \\                    <div class="kv-row">
        \\                        <span class="kv-key">Zombie Processes</span>
        \\                        <span class="kv-value {s}">{d}</span>
        \\                    </div>
        \\
    , .{ zombie_status, r.services.zombie_count });
    try w.writeAll("                </div>\n");
    try w.writeAll("            </div>\n");
    try w.writeAll("        </div>\n\n");

    // Battery section (if present)
    if (r.hardware.battery) |battery| {
        try w.writeAll("        <div class=\"section\">\n");
        try w.writeAll("            <div class=\"section-title\">Battery</div>\n");
        try w.writeAll("            <div class=\"section-content\">\n");
        try w.print(
            \\                <div class="kv-row">
            \\                    <span class="kv-key">Status</span>
            \\                    <span class="kv-value">{s}</span>
            \\                </div>
            \\
        , .{battery.status});
        try w.print(
            \\                <div class="kv-row">
            \\                    <span class="kv-key">Capacity</span>
            \\                    <span class="kv-value">{d:.0}%</span>
            \\                </div>
            \\
        , .{battery.capacity});
        const health_status = if (battery.health < 50) "status-error" else if (battery.health < 80) "status-warn" else "status-ok";
        try w.print(
            \\                <div class="kv-row">
            \\                    <span class="kv-key">Health</span>
            \\                    <span class="kv-value {s}">{d:.1}%</span>
            \\                </div>
            \\
        , .{ health_status, battery.health });
        try w.print(
            \\                <div class="kv-row">
            \\                    <span class="kv-key">Cycle Count</span>
            \\                    <span class="kv-value">{d}</span>
            \\                </div>
            \\
        , .{battery.cycle_count});
        try w.writeAll("            </div>\n");
        try w.writeAll("        </div>\n\n");
    }

    // Temperatures section
    if (r.hardware.temperatures) |temps| {
        if (temps.len > 0) {
            try w.writeAll("        <div class=\"section\">\n");
            try w.writeAll("            <div class=\"section-title\">Temperatures</div>\n");
            try w.writeAll("            <div class=\"section-content\">\n");
            try w.writeAll("                <table>\n");
            try w.writeAll("                    <thead>\n");
            try w.writeAll("                        <tr>\n");
            try w.writeAll("                            <th>Sensor</th>\n");
            try w.writeAll("                            <th>Current</th>\n");
            try w.writeAll("                            <th>High</th>\n");
            try w.writeAll("                            <th>Critical</th>\n");
            try w.writeAll("                        </tr>\n");
            try w.writeAll("                    </thead>\n");
            try w.writeAll("                    <tbody>\n");
            for (temps) |temp| {
                const temp_status = if (temp.current >= 85) "status-error" else if (temp.current >= 70) "status-warn" else "status-ok";
                try w.writeAll("                        <tr>\n");
                try w.print("                            <td>{s}</td>\n", .{temp.label});
                try w.print("                            <td class=\"{s}\">{d:.1}°C</td>\n", .{ temp_status, temp.current });
                if (temp.high) |high| {
                    if (high > 0) {
                        try w.print("                            <td>{d:.1}°C</td>\n", .{high});
                    } else {
                        try w.writeAll("                            <td>-</td>\n");
                    }
                } else {
                    try w.writeAll("                            <td>-</td>\n");
                }
                if (temp.critical) |critical| {
                    if (critical > 0) {
                        try w.print("                            <td>{d:.1}°C</td>\n", .{critical});
                    } else {
                        try w.writeAll("                            <td>-</td>\n");
                    }
                } else {
                    try w.writeAll("                            <td>-</td>\n");
                }
                try w.writeAll("                        </tr>\n");
            }
            try w.writeAll("                    </tbody>\n");
            try w.writeAll("                </table>\n");
            try w.writeAll("            </div>\n");
            try w.writeAll("        </div>\n\n");
        }
    }

    // Docker section
    if (r.docker) |docker| {
        if (docker.available) {
            try w.writeAll("        <div class=\"section\">\n");
            try w.writeAll("            <div class=\"section-title\">Docker</div>\n");
            try w.writeAll("            <div class=\"section-content\">\n");
            const docker_status = if (docker.daemon_running) "status-ok" else "status-error";
            const docker_text = if (docker.daemon_running) "Running" else "Not Running";
            try w.print(
                \\                <div class="kv-row">
                \\                    <span class="kv-key">Status</span>
                \\                    <span class="kv-value {s}">{s}</span>
                \\                </div>
                \\
            , .{ docker_status, docker_text });
            if (docker.daemon_running) {
                try w.print(
                    \\                <div class="kv-row">
                    \\                    <span class="kv-key">Running Containers</span>
                    \\                    <span class="kv-value">{d}</span>
                    \\                </div>
                    \\
                , .{docker.running_count});
                try w.print(
                    \\                <div class="kv-row">
                    \\                    <span class="kv-key">Stopped Containers</span>
                    \\                    <span class="kv-value">{d}</span>
                    \\                </div>
                    \\
                , .{docker.stopped_count});
                try w.print(
                    \\                <div class="kv-row">
                    \\                    <span class="kv-key">Images</span>
                    \\                    <span class="kv-value">{d}</span>
                    \\                </div>
                    \\
                , .{docker.image_count});
                try w.print(
                    \\                <div class="kv-row">
                    \\                    <span class="kv-key">Total Image Size</span>
                    \\                    <span class="kv-value">{s}</span>
                    \\                </div>
                    \\
                , .{formatBytes(@intCast(docker.total_image_size))});
                if (docker.dangling_images_size > 0) {
                    try w.print(
                        \\                <div class="kv-row">
                        \\                    <span class="kv-key">Dangling Images</span>
                        \\                    <span class="kv-value status-warn">{s}</span>
                        \\                </div>
                        \\
                    , .{formatBytes(@intCast(docker.dangling_images_size))});
                }
            }
            try w.writeAll("            </div>\n");
            try w.writeAll("        </div>\n\n");
        }
    }

    // Snaps section
    if (r.snaps) |snaps| {
        if (snaps.available) {
            try w.writeAll("        <div class=\"section\">\n");
            try w.writeAll("            <div class=\"section-title\">Snaps</div>\n");
            try w.writeAll("            <div class=\"section-content\">\n");
            const snap_count = if (snaps.snaps) |s| s.len else 0;
            try w.print(
                \\                <div class="kv-row">
                \\                    <span class="kv-key">Installed</span>
                \\                    <span class="kv-value">{d}</span>
                \\                </div>
                \\
            , .{snap_count});
            try w.print(
                \\                <div class="kv-row">
                \\                    <span class="kv-key">Total Disk Usage</span>
                \\                    <span class="kv-value">{s}</span>
                \\                </div>
                \\
            , .{formatBytes(@intCast(snaps.total_disk_usage))});
            if (snaps.pending_refreshes > 0) {
                try w.print(
                    \\                <div class="kv-row">
                    \\                    <span class="kv-key">Pending Refreshes</span>
                    \\                    <span class="kv-value status-warn">{d}</span>
                    \\                </div>
                    \\
                , .{snaps.pending_refreshes});
            }
            try w.writeAll("            </div>\n");
            try w.writeAll("        </div>\n\n");
        }
    }

    // GPU section
    if (r.gpu) |gpu| {
        if (gpu.available) {
            if (gpu.gpus) |gpus| {
                try w.writeAll("        <div class=\"section\">\n");
                try w.writeAll("            <div class=\"section-title\">GPU</div>\n");
                try w.writeAll("            <div class=\"section-content\">\n");
                for (gpus) |g| {
                    try w.writeAll("                <div style=\"margin-bottom: 15px; padding-bottom: 15px; border-bottom: 1px solid var(--border);\">\n");
                    try w.print("                    <div style=\"font-weight: 600; margin-bottom: 10px;\">{s}</div>\n", .{g.name});
                    if (g.temperature > 0) {
                        const gpu_temp_status = if (g.temperature >= 90) "status-error" else if (g.temperature >= 80) "status-warn" else "status-ok";
                        try w.print(
                            \\                    <div class="kv-row">
                            \\                        <span class="kv-key">Temperature</span>
                            \\                        <span class="kv-value {s}">{d}°C</span>
                            \\                    </div>
                            \\
                        , .{ gpu_temp_status, g.temperature });
                    }
                    if (g.utilization > 0) {
                        try w.print(
                            \\                    <div class="kv-row">
                            \\                        <span class="kv-key">Utilization</span>
                            \\                        <span class="kv-value">{d}%</span>
                            \\                    </div>
                            \\
                        , .{g.utilization});
                    }
                    if (g.memory_total > 0) {
                        try w.print(
                            \\                    <div class="kv-row">
                            \\                        <span class="kv-key">Memory</span>
                            \\                        <span class="kv-value">{s} / {s}</span>
                            \\                    </div>
                            \\
                        , .{ formatBytes(@intCast(g.memory_used)), formatBytes(@intCast(g.memory_total)) });
                    }
                    if (g.power_draw > 0) {
                        try w.print(
                            \\                    <div class="kv-row">
                            \\                        <span class="kv-key">Power</span>
                            \\                        <span class="kv-value">{d:.1}W</span>
                            \\                    </div>
                            \\
                        , .{g.power_draw});
                    }
                    try w.writeAll("                </div>\n");
                }
                try w.writeAll("            </div>\n");
                try w.writeAll("        </div>\n\n");
            }
        }
    }

    // Logs section
    if (r.logs) |logs| {
        if (logs.available) {
            try w.writeAll("        <div class=\"section\">\n");
            try w.writeAll("            <div class=\"section-title\">Logs (24h)</div>\n");
            try w.writeAll("            <div class=\"section-content\">\n");
            const error_status = if (logs.stats.error_count > 0) "status-warn" else "status-ok";
            try w.print(
                \\                <div class="kv-row">
                \\                    <span class="kv-key">Errors</span>
                \\                    <span class="kv-value {s}">{d}</span>
                \\                </div>
                \\
            , .{ error_status, logs.stats.error_count });
            try w.print(
                \\                <div class="kv-row">
                \\                    <span class="kv-key">Warnings</span>
                \\                    <span class="kv-value">{d}</span>
                \\                </div>
                \\
            , .{logs.stats.warning_count});
            if (logs.stats.critical_count > 0) {
                try w.print(
                    \\                <div class="kv-row">
                    \\                    <span class="kv-key">Critical</span>
                    \\                    <span class="kv-value status-error">{d}</span>
                    \\                </div>
                    \\
                , .{logs.stats.critical_count});
            }
            if (logs.stats.oom_events > 0) {
                try w.print(
                    \\                <div class="kv-row">
                    \\                    <span class="kv-key">OOM Events</span>
                    \\                    <span class="kv-value status-error">{d}</span>
                    \\                </div>
                    \\
                , .{logs.stats.oom_events});
            }
            if (logs.stats.kernel_panics > 0) {
                try w.print(
                    \\                <div class="kv-row">
                    \\                    <span class="kv-key">Kernel Panics</span>
                    \\                    <span class="kv-value status-error">{d}</span>
                    \\                </div>
                    \\
                , .{logs.stats.kernel_panics});
            }
            if (logs.stats.segfaults > 0) {
                try w.print(
                    \\                <div class="kv-row">
                    \\                    <span class="kv-key">Segfaults</span>
                    \\                    <span class="kv-value status-error">{d}</span>
                    \\                </div>
                    \\
                , .{logs.stats.segfaults});
            }
            try w.writeAll("            </div>\n");
            try w.writeAll("        </div>\n\n");
        }
    }

    // Issues section
    if (r.issues.len > 0) {
        try w.writeAll("        <div class=\"section\">\n");
        try w.writeAll("            <div class=\"section-title\">Issues</div>\n");
        try w.writeAll("            <div class=\"section-content\">\n");
        for (r.issues) |issue| {
            try w.print("                <div class=\"issue-card {s}\">\n", .{issue.severity});
            try w.print("                    <div class=\"issue-title\">{s}</div>\n", .{issue.title});
            try w.print("                    <div class=\"issue-category\">{s}</div>\n", .{issue.category});
            try w.print("                    <div>{s}</div>\n", .{issue.description});
            if (issue.fix) |fix| {
                try w.print("                    <div class=\"issue-fix\">Fix: {s}</div>\n", .{fix});
            }
            try w.writeAll("                </div>\n");
        }
        try w.writeAll("            </div>\n");
        try w.writeAll("        </div>\n\n");
    }

    // Footer
    try w.writeAll(
        \\        <footer>
        \\            Generated by machinestate
        \\        </footer>
        \\    </div>
        \\</body>
        \\</html>
        \\
    );

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
