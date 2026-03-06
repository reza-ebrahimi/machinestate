const std = @import("std");
const posix = std.posix;
const Allocator = std.mem.Allocator;

const collectors = @import("../collectors/mod.zig");
const json_output = @import("../outputs/json.zig");
const html_output = @import("../outputs/html.zig");
const report = @import("../models/report.zig");

fn writeStdout(data: []const u8) void {
    _ = posix.write(posix.STDOUT_FILENO, data) catch {};
}

fn writeStderr(data: []const u8) void {
    _ = posix.write(posix.STDERR_FILENO, data) catch {};
}

// Send HTTP response to socket
fn sendResponse(fd: posix.socket_t, status: []const u8, content_type: []const u8, body: []const u8) void {
    var buf: [4096]u8 = undefined;
    const header = std.fmt.bufPrint(&buf, "HTTP/1.1 {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n", .{ status, content_type, body.len }) catch return;
    _ = posix.write(fd, header) catch return;
    _ = posix.write(fd, body) catch return;
}

fn sendJson(fd: posix.socket_t, body: []const u8) void {
    sendResponse(fd, "200 OK", "application/json", body);
}

fn sendPlainText(fd: posix.socket_t, body: []const u8) void {
    sendResponse(fd, "200 OK", "text/plain; version=0.0.4; charset=utf-8", body);
}

fn sendHtml(fd: posix.socket_t, body: []const u8) void {
    sendResponse(fd, "200 OK", "text/html; charset=utf-8", body);
}

// Auto-refresh meta tag to inject
const auto_refresh_meta = "<meta http-equiv=\"refresh\" content=\"30\">";

fn sendNotFound(fd: posix.socket_t) void {
    sendResponse(fd, "404 Not Found", "application/json", "{\"error\":\"Not Found\"}");
}

fn sendError(fd: posix.socket_t, message: []const u8) void {
    var buf: [256]u8 = undefined;
    const body = std.fmt.bufPrint(&buf, "{{\"error\":\"{s}\"}}", .{message}) catch "{\"error\":\"Internal error\"}";
    sendResponse(fd, "500 Internal Server Error", "application/json", body);
}

// Parse HTTP request to get method and path
fn parseRequest(buffer: []const u8) ?struct { method: []const u8, path: []const u8 } {
    const line_end = std.mem.indexOf(u8, buffer, "\r\n") orelse std.mem.indexOf(u8, buffer, "\n") orelse return null;
    const first_line = buffer[0..line_end];

    var parts = std.mem.splitScalar(u8, first_line, ' ');
    const method = parts.next() orelse return null;
    const full_path = parts.next() orelse return null;

    const path = if (std.mem.indexOf(u8, full_path, "?")) |idx| full_path[0..idx] else full_path;

    return .{ .method = method, .path = path };
}

// Route handlers
fn handleHealth(allocator: Allocator, fd: posix.socket_t) void {
    _ = allocator;
    sendJson(fd, "{\"status\":\"ok\"}");
}

fn handleReport(allocator: Allocator, fd: posix.socket_t) void {
    const report_data = collectors.collectAll(allocator) catch {
        sendError(fd, "Failed to collect report");
        return;
    };
    const json_str = json_output.toJson(allocator, report_data) catch {
        sendError(fd, "Failed to generate report");
        return;
    };
    defer allocator.free(json_str);
    sendJson(fd, json_str);
}

fn handleSystem(allocator: Allocator, fd: posix.socket_t) void {
    const system_info = collectors.collectSystemInfo(allocator);
    const json_str = json_output.toJson(allocator, system_info) catch {
        sendError(fd, "Failed to generate system info");
        return;
    };
    defer allocator.free(json_str);
    sendJson(fd, json_str);
}

fn handleDisk(allocator: Allocator, fd: posix.socket_t) void {
    const disk_info = collectors.collectDiskInfo(allocator);
    const json_str = json_output.toJson(allocator, disk_info) catch {
        sendError(fd, "Failed to generate disk info");
        return;
    };
    defer allocator.free(json_str);
    sendJson(fd, json_str);
}

fn handleNetwork(allocator: Allocator, fd: posix.socket_t) void {
    const network_info = collectors.collectNetworkInfo(allocator);
    const json_str = json_output.toJson(allocator, network_info) catch {
        sendError(fd, "Failed to generate network info");
        return;
    };
    defer allocator.free(json_str);
    sendJson(fd, json_str);
}

fn handlePackages(allocator: Allocator, fd: posix.socket_t) void {
    const package_info = collectors.collectPackageInfo(allocator);
    const json_str = json_output.toJson(allocator, package_info) catch {
        sendError(fd, "Failed to generate package info");
        return;
    };
    defer allocator.free(json_str);
    sendJson(fd, json_str);
}

fn handleServices(allocator: Allocator, fd: posix.socket_t) void {
    const service_info = collectors.collectServiceInfo(allocator);
    const json_str = json_output.toJson(allocator, service_info) catch {
        sendError(fd, "Failed to generate service info");
        return;
    };
    defer allocator.free(json_str);
    sendJson(fd, json_str);
}

fn handleSecurity(allocator: Allocator, fd: posix.socket_t) void {
    const security_info = collectors.collectSecurityInfo(allocator);
    const json_str = json_output.toJson(allocator, security_info) catch {
        sendError(fd, "Failed to generate security info");
        return;
    };
    defer allocator.free(json_str);
    sendJson(fd, json_str);
}

fn handleHardware(allocator: Allocator, fd: posix.socket_t) void {
    const hardware_info = collectors.collectHardwareInfo(allocator);
    const json_str = json_output.toJson(allocator, hardware_info) catch {
        sendError(fd, "Failed to generate hardware info");
        return;
    };
    defer allocator.free(json_str);
    sendJson(fd, json_str);
}

fn handleDocker(allocator: Allocator, fd: posix.socket_t) void {
    const docker_info = collectors.collectDockerInfo(allocator);
    const json_str = json_output.toJson(allocator, docker_info) catch {
        sendError(fd, "Failed to generate docker info");
        return;
    };
    defer allocator.free(json_str);
    sendJson(fd, json_str);
}

fn handleSnaps(allocator: Allocator, fd: posix.socket_t) void {
    const snap_info = collectors.collectSnapInfo(allocator);
    const json_str = json_output.toJson(allocator, snap_info) catch {
        sendError(fd, "Failed to generate snap info");
        return;
    };
    defer allocator.free(json_str);
    sendJson(fd, json_str);
}

fn handleGpu(allocator: Allocator, fd: posix.socket_t) void {
    const gpu_info = collectors.collectGPUInfo(allocator);
    const json_str = json_output.toJson(allocator, gpu_info) catch {
        sendError(fd, "Failed to generate GPU info");
        return;
    };
    defer allocator.free(json_str);
    sendJson(fd, json_str);
}

fn handleLogs(allocator: Allocator, fd: posix.socket_t) void {
    const log_info = collectors.collectLogInfo(allocator);
    const json_str = json_output.toJson(allocator, log_info) catch {
        sendError(fd, "Failed to generate log info");
        return;
    };
    defer allocator.free(json_str);
    sendJson(fd, json_str);
}

fn handleIssues(allocator: Allocator, fd: posix.socket_t) void {
    const report_data = collectors.collectAll(allocator) catch {
        sendError(fd, "Failed to collect issues");
        return;
    };
    const json_str = json_output.toJson(allocator, report_data.issues) catch {
        sendError(fd, "Failed to generate issues");
        return;
    };
    defer allocator.free(json_str);
    sendJson(fd, json_str);
}

fn handleConfig(allocator: Allocator, fd: posix.socket_t) void {
    _ = allocator;
    sendJson(fd,
        \\{
        \\  "disk_warning_percent": 80,
        \\  "disk_critical_percent": 90,
        \\  "memory_warning_percent": 90,
        \\  "battery_health_warning": 80,
        \\  "battery_health_critical": 50,
        \\  "uptime_warning_days": 30,
        \\  "gpu_temp_warning": 80,
        \\  "gpu_temp_critical": 90
        \\}
    );
}

fn handleDashboard(allocator: Allocator, fd: posix.socket_t) void {
    const report_data = collectors.collectAll(allocator) catch {
        sendError(fd, "Failed to collect data");
        return;
    };
    const html_str = html_output.renderHtml(allocator, &report_data) catch {
        sendError(fd, "Failed to generate dashboard");
        return;
    };
    defer allocator.free(html_str);

    // Inject auto-refresh meta tag after <head>
    if (std.mem.indexOf(u8, html_str, "<head>")) |idx| {
        const prefix = html_str[0 .. idx + 6]; // includes "<head>"
        const suffix = html_str[idx + 6 ..];
        const refreshed = std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ prefix, auto_refresh_meta, suffix }) catch {
            sendHtml(fd, html_str);
            return;
        };
        defer allocator.free(refreshed);
        sendHtml(fd, refreshed);
    } else {
        sendHtml(fd, html_str);
    }
}

fn handleMetrics(allocator: Allocator, fd: posix.socket_t) void {
    const report_data = collectors.collectAll(allocator) catch {
        sendError(fd, "Failed to collect metrics");
        return;
    };

    // Use fixed buffer for Prometheus metrics
    var buf: [8192]u8 = undefined;
    var pos: usize = 0;

    // Helper to append to buffer
    const append = struct {
        fn f(b: []u8, p: *usize, data: []const u8) void {
            if (p.* + data.len <= b.len) {
                @memcpy(b[p.*..][0..data.len], data);
                p.* += data.len;
            }
        }
    }.f;

    // System metrics
    append(&buf, &pos, "# HELP machinestate_cpu_usage_percent CPU usage percentage\n");
    append(&buf, &pos, "# TYPE machinestate_cpu_usage_percent gauge\n");
    var tmp: [64]u8 = undefined;
    var len = std.fmt.bufPrint(&tmp, "machinestate_cpu_usage_percent {d:.2}\n", .{report_data.system.cpu_usage}) catch return;
    append(&buf, &pos, len);

    append(&buf, &pos, "# HELP machinestate_memory_used_percent Memory usage percentage\n");
    append(&buf, &pos, "# TYPE machinestate_memory_used_percent gauge\n");
    len = std.fmt.bufPrint(&tmp, "machinestate_memory_used_percent {d:.2}\n", .{report_data.system.memory_percent}) catch return;
    append(&buf, &pos, len);

    append(&buf, &pos, "# HELP machinestate_memory_total_bytes Total memory in bytes\n");
    append(&buf, &pos, "# TYPE machinestate_memory_total_bytes gauge\n");
    len = std.fmt.bufPrint(&tmp, "machinestate_memory_total_bytes {d}\n", .{report_data.system.memory_total}) catch return;
    append(&buf, &pos, len);

    append(&buf, &pos, "# HELP machinestate_memory_used_bytes Used memory in bytes\n");
    append(&buf, &pos, "# TYPE machinestate_memory_used_bytes gauge\n");
    len = std.fmt.bufPrint(&tmp, "machinestate_memory_used_bytes {d}\n", .{report_data.system.memory_used}) catch return;
    append(&buf, &pos, len);

    append(&buf, &pos, "# HELP machinestate_load_average_1m Load average (1 minute)\n");
    append(&buf, &pos, "# TYPE machinestate_load_average_1m gauge\n");
    len = std.fmt.bufPrint(&tmp, "machinestate_load_average_1m {d:.2}\n", .{report_data.system.load_avg_1}) catch return;
    append(&buf, &pos, len);

    // Disk metrics
    append(&buf, &pos, "# HELP machinestate_disk_used_percent Disk usage percentage\n");
    append(&buf, &pos, "# TYPE machinestate_disk_used_percent gauge\n");
    for (report_data.disk.filesystems) |fs| {
        var disk_tmp: [128]u8 = undefined;
        const disk_len = std.fmt.bufPrint(&disk_tmp, "machinestate_disk_used_percent{{mount=\"{s}\"}} {d:.2}\n", .{ fs.mount_point, fs.used_percent }) catch continue;
        append(&buf, &pos, disk_len);
    }

    // Issues count
    var critical: u32 = 0;
    var warning: u32 = 0;
    var info: u32 = 0;
    for (report_data.issues) |issue| {
        if (std.mem.eql(u8, issue.severity, "critical")) {
            critical += 1;
        } else if (std.mem.eql(u8, issue.severity, "warning")) {
            warning += 1;
        } else {
            info += 1;
        }
    }
    append(&buf, &pos, "# HELP machinestate_issues_total Total issues by severity\n");
    append(&buf, &pos, "# TYPE machinestate_issues_total gauge\n");
    len = std.fmt.bufPrint(&tmp, "machinestate_issues_total{{severity=\"critical\"}} {d}\n", .{critical}) catch return;
    append(&buf, &pos, len);
    len = std.fmt.bufPrint(&tmp, "machinestate_issues_total{{severity=\"warning\"}} {d}\n", .{warning}) catch return;
    append(&buf, &pos, len);
    len = std.fmt.bufPrint(&tmp, "machinestate_issues_total{{severity=\"info\"}} {d}\n", .{info}) catch return;
    append(&buf, &pos, len);

    sendPlainText(fd, buf[0..pos]);
}

// Handle a single connection
fn handleConnection(allocator: Allocator, client_fd: posix.socket_t) void {
    defer posix.close(client_fd);

    var buffer: [8192]u8 = undefined;
    const bytes_read = posix.read(client_fd, &buffer) catch return;
    if (bytes_read == 0) return;

    const request = parseRequest(buffer[0..bytes_read]) orelse {
        sendError(client_fd, "Invalid request");
        return;
    };

    if (!std.mem.eql(u8, request.method, "GET")) {
        sendResponse(client_fd, "405 Method Not Allowed", "application/json", "{\"error\":\"Method not allowed\"}");
        return;
    }

    // Route to handler
    if (std.mem.eql(u8, request.path, "/")) {
        handleDashboard(allocator, client_fd);
    } else if (std.mem.eql(u8, request.path, "/health")) {
        handleHealth(allocator, client_fd);
    } else if (std.mem.eql(u8, request.path, "/api/report")) {
        handleReport(allocator, client_fd);
    } else if (std.mem.eql(u8, request.path, "/api/system")) {
        handleSystem(allocator, client_fd);
    } else if (std.mem.eql(u8, request.path, "/api/disk")) {
        handleDisk(allocator, client_fd);
    } else if (std.mem.eql(u8, request.path, "/api/network")) {
        handleNetwork(allocator, client_fd);
    } else if (std.mem.eql(u8, request.path, "/api/packages")) {
        handlePackages(allocator, client_fd);
    } else if (std.mem.eql(u8, request.path, "/api/services")) {
        handleServices(allocator, client_fd);
    } else if (std.mem.eql(u8, request.path, "/api/security")) {
        handleSecurity(allocator, client_fd);
    } else if (std.mem.eql(u8, request.path, "/api/hardware")) {
        handleHardware(allocator, client_fd);
    } else if (std.mem.eql(u8, request.path, "/api/docker")) {
        handleDocker(allocator, client_fd);
    } else if (std.mem.eql(u8, request.path, "/api/snaps")) {
        handleSnaps(allocator, client_fd);
    } else if (std.mem.eql(u8, request.path, "/api/gpu")) {
        handleGpu(allocator, client_fd);
    } else if (std.mem.eql(u8, request.path, "/api/logs")) {
        handleLogs(allocator, client_fd);
    } else if (std.mem.eql(u8, request.path, "/api/issues")) {
        handleIssues(allocator, client_fd);
    } else if (std.mem.eql(u8, request.path, "/api/config")) {
        handleConfig(allocator, client_fd);
    } else if (std.mem.eql(u8, request.path, "/metrics")) {
        handleMetrics(allocator, client_fd);
    } else {
        sendNotFound(client_fd);
    }
}

pub fn run(allocator: Allocator, port_str: []const u8) !void {
    const port = std.fmt.parseInt(u16, port_str, 10) catch {
        writeStderr("Invalid port: ");
        writeStderr(port_str);
        writeStderr("\n");
        return error.InvalidPort;
    };

    // Create socket
    const server_fd = try posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
    defer posix.close(server_fd);

    // Set SO_REUSEADDR
    const optval: u32 = 1;
    try posix.setsockopt(server_fd, posix.SOL.SOCKET, posix.SO.REUSEADDR, std.mem.asBytes(&optval));

    // Bind
    var addr: posix.sockaddr.in = .{
        .family = posix.AF.INET,
        .port = std.mem.nativeToBig(u16, port),
        .addr = 0, // INADDR_ANY
    };
    try posix.bind(server_fd, @ptrCast(&addr), @sizeOf(posix.sockaddr.in));

    // Listen
    try posix.listen(server_fd, 128);

    var port_buf: [16]u8 = undefined;
    const port_num_str = std.fmt.bufPrint(&port_buf, "{d}", .{port}) catch "8080";
    writeStdout("HTTP server listening on http://localhost:");
    writeStdout(port_num_str);
    writeStdout("\n");
    writeStdout("Endpoints:\n");
    writeStdout("  GET /              - Web dashboard (HTML, auto-refresh)\n");
    writeStdout("  GET /health        - Health check\n");
    writeStdout("  GET /api/report    - Full system report\n");
    writeStdout("  GET /api/issues    - Detected issues\n");
    writeStdout("  GET /api/system    - CPU, memory, load\n");
    writeStdout("  GET /api/disk      - Filesystem usage\n");
    writeStdout("  GET /api/network   - Interfaces, ports\n");
    writeStdout("  GET /api/packages  - APT status\n");
    writeStdout("  GET /api/services  - Systemd, processes\n");
    writeStdout("  GET /api/security  - Firewall, SSH\n");
    writeStdout("  GET /api/hardware  - Battery, temps\n");
    writeStdout("  GET /api/docker    - Containers, images\n");
    writeStdout("  GET /api/snaps     - Snap packages\n");
    writeStdout("  GET /api/gpu       - GPU stats\n");
    writeStdout("  GET /api/logs      - Log analysis\n");
    writeStdout("  GET /api/config    - Current thresholds\n");
    writeStdout("  GET /metrics       - Prometheus metrics\n");
    writeStdout("\nPress Ctrl+C to stop\n");

    // Accept loop
    while (true) {
        const client_fd = posix.accept(server_fd, null, null, 0) catch continue;
        handleConnection(allocator, client_fd);
    }
}
