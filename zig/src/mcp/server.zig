const std = @import("std");
const json_output = @import("../outputs/json.zig");
const collectors = @import("../collectors/mod.zig");
const report = @import("../models/report.zig");

const MCP_VERSION = "2025-12-31";
const SERVER_NAME = "machinestate";
const SERVER_VERSION = "1.0.0";

pub fn runMcpServer(allocator: std.mem.Allocator) !void {
    var line_buf: [65536]u8 = undefined;

    while (true) {
        // Read a line from stdin
        const line = readLine(&line_buf) orelse break;
        if (line.len == 0) continue;

        // Parse JSON-RPC request
        const response = handleRequest(allocator, line) catch |err| {
            const error_response = makeErrorResponse(allocator, null, -32603, "Internal error", @errorName(err));
            writeResponse(error_response);
            continue;
        };
        defer allocator.free(response);

        writeResponse(response);
    }
}

fn readLine(buf: []u8) ?[]u8 {
    var total: usize = 0;
    while (total < buf.len) {
        const n = std.posix.read(std.posix.STDIN_FILENO, buf[total .. total + 1]) catch return null;
        if (n == 0) return null;
        if (buf[total] == '\n') {
            return buf[0..total];
        }
        total += 1;
    }
    return buf[0..total];
}

fn writeResponse(data: []const u8) void {
    _ = std.posix.write(std.posix.STDOUT_FILENO, data) catch {};
    _ = std.posix.write(std.posix.STDOUT_FILENO, "\n") catch {};
}

fn handleRequest(allocator: std.mem.Allocator, line: []const u8) ![]u8 {
    // Simple JSON parsing for method and id
    const method = extractJsonString(line, "\"method\"") orelse return makeErrorResponse(allocator, null, -32600, "Invalid Request", "Missing method");
    const id = extractJsonValue(line, "\"id\"");

    if (std.mem.eql(u8, method, "initialize")) {
        return handleInitialize(allocator, id);
    } else if (std.mem.eql(u8, method, "notifications/initialized")) {
        // Notification, no response needed
        return allocator.dupe(u8, "");
    } else if (std.mem.eql(u8, method, "tools/list")) {
        return handleToolsList(allocator, id);
    } else if (std.mem.eql(u8, method, "tools/call")) {
        const tool_name = extractNestedString(line, "\"params\"", "\"name\"") orelse return makeErrorResponse(allocator, id, -32602, "Invalid params", "Missing tool name");
        return handleToolCall(allocator, id, tool_name, line);
    } else {
        return makeErrorResponse(allocator, id, -32601, "Method not found", method);
    }
}

fn handleInitialize(allocator: std.mem.Allocator, id: ?[]const u8) ![]u8 {
    var alloc_writer = std.Io.Writer.Allocating.init(allocator);
    errdefer alloc_writer.deinit();
    const w = &alloc_writer.writer;

    try w.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    if (id) |i| {
        try w.writeAll(i);
    } else {
        try w.writeAll("null");
    }
    try w.writeAll(",\"result\":{\"protocolVersion\":\"");
    try w.writeAll(MCP_VERSION);
    try w.writeAll("\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"");
    try w.writeAll(SERVER_NAME);
    try w.writeAll("\",\"version\":\"");
    try w.writeAll(SERVER_VERSION);
    try w.writeAll("\"}}}");

    return alloc_writer.toOwnedSlice();
}

fn handleToolsList(allocator: std.mem.Allocator, id: ?[]const u8) ![]u8 {
    var alloc_writer = std.Io.Writer.Allocating.init(allocator);
    errdefer alloc_writer.deinit();
    const w = &alloc_writer.writer;

    try w.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    if (id) |i| {
        try w.writeAll(i);
    } else {
        try w.writeAll("null");
    }
    try w.writeAll(",\"result\":{\"tools\":[");

    const tools = [_]struct { name: []const u8, desc: []const u8 }{
        .{ .name = "get_system_report", .desc = "Get complete system state report including CPU, memory, disk, network, packages, services, security, hardware, and detected issues. This is the most comprehensive tool - use it when you need a full system overview." },
        .{ .name = "get_issues", .desc = "Get detected system issues with severity levels. Returns problems found during system analysis with recommended fixes." },
        .{ .name = "stream_system_report", .desc = "Stream system report data as each collector completes. Returns JSONL format (one JSON object per line) for real-time data as collectors finish." },
        .{ .name = "get_system_info", .desc = "Get CPU, memory, swap, load average, and uptime information." },
        .{ .name = "get_disk_info", .desc = "Get filesystem usage information including size, used, free space, and inode usage." },
        .{ .name = "get_network_info", .desc = "Get network interface status, IP addresses, listening ports, and connectivity information." },
        .{ .name = "get_package_info", .desc = "Get APT package status including available updates, security updates, broken packages, and held packages." },
        .{ .name = "get_service_info", .desc = "Get systemd service status including failed units, zombie processes, and top CPU/memory consuming processes." },
        .{ .name = "get_security_info", .desc = "Get security status including firewall state, SSH status, failed login attempts, and open ports." },
        .{ .name = "get_hardware_info", .desc = "Get hardware health including battery status/health, temperature sensors, and crash reports." },
        .{ .name = "get_docker_info", .desc = "Get Docker container and image information including running/stopped containers, images, and disk usage." },
        .{ .name = "get_snap_info", .desc = "Get Snap package information including installed snaps, disk usage, and pending refreshes." },
        .{ .name = "get_gpu_info", .desc = "Get GPU information including temperature, utilization, and memory usage for NVIDIA, AMD, or Intel GPUs." },
        .{ .name = "get_log_info", .desc = "Get log analysis for the last 24 hours including error counts, OOM events, kernel panics, and top error patterns." },
    };

    for (tools, 0..) |tool, i| {
        if (i > 0) try w.writeAll(",");
        try w.writeAll("{\"name\":\"");
        try w.writeAll(tool.name);
        try w.writeAll("\",\"description\":\"");
        try w.writeAll(tool.desc);
        try w.writeAll("\",\"inputSchema\":{\"type\":\"object\",\"properties\":{}}}");
    }

    try w.writeAll("]}}");

    return alloc_writer.toOwnedSlice();
}

fn handleToolCall(allocator: std.mem.Allocator, id: ?[]const u8, tool_name: []const u8, request: []const u8) ![]u8 {
    _ = request; // Arguments would be extracted from here

    var result: []u8 = undefined;

    if (std.mem.eql(u8, tool_name, "get_system_report")) {
        const r = try collectors.collectAll(allocator);
        result = try json_output.renderJson(allocator, &r);
    } else if (std.mem.eql(u8, tool_name, "get_issues")) {
        const r = try collectors.collectAll(allocator);
        result = try serializeIssues(allocator, r.issues);
    } else if (std.mem.eql(u8, tool_name, "stream_system_report")) {
        result = try handleStreamSystemReport(allocator);
    } else if (std.mem.eql(u8, tool_name, "get_system_info")) {
        const r = try collectors.collectAll(allocator);
        result = try serializeSystemInfo(allocator, &r.system);
    } else if (std.mem.eql(u8, tool_name, "get_disk_info")) {
        const r = try collectors.collectAll(allocator);
        result = try serializeDiskInfo(allocator, &r.disk);
    } else if (std.mem.eql(u8, tool_name, "get_network_info")) {
        const r = try collectors.collectAll(allocator);
        result = try serializeNetworkInfo(allocator, &r.network);
    } else if (std.mem.eql(u8, tool_name, "get_package_info")) {
        const r = try collectors.collectAll(allocator);
        result = try serializePackageInfo(allocator, &r.packages);
    } else if (std.mem.eql(u8, tool_name, "get_service_info")) {
        const r = try collectors.collectAll(allocator);
        result = try serializeServiceInfo(allocator, &r.services);
    } else if (std.mem.eql(u8, tool_name, "get_security_info")) {
        const r = try collectors.collectAll(allocator);
        result = try serializeSecurityInfo(allocator, &r.security);
    } else if (std.mem.eql(u8, tool_name, "get_hardware_info")) {
        const r = try collectors.collectAll(allocator);
        result = try serializeHardwareInfo(allocator, &r.hardware);
    } else if (std.mem.eql(u8, tool_name, "get_docker_info")) {
        const r = try collectors.collectAll(allocator);
        if (r.docker) |docker| {
            result = try std.json.Stringify.valueAlloc(allocator, docker, .{ .whitespace = .indent_2 });
        } else {
            result = try allocator.dupe(u8, "{\"installed\": false}");
        }
    } else if (std.mem.eql(u8, tool_name, "get_snap_info")) {
        const r = try collectors.collectAll(allocator);
        if (r.snaps) |snaps| {
            result = try std.json.Stringify.valueAlloc(allocator, snaps, .{ .whitespace = .indent_2 });
        } else {
            result = try allocator.dupe(u8, "{\"installed\": false}");
        }
    } else if (std.mem.eql(u8, tool_name, "get_gpu_info")) {
        const r = try collectors.collectAll(allocator);
        if (r.gpu) |gpu| {
            result = try std.json.Stringify.valueAlloc(allocator, gpu, .{ .whitespace = .indent_2 });
        } else {
            result = try allocator.dupe(u8, "{\"devices\": []}");
        }
    } else if (std.mem.eql(u8, tool_name, "get_log_info")) {
        const r = try collectors.collectAll(allocator);
        if (r.logs) |logs| {
            result = try std.json.Stringify.valueAlloc(allocator, logs, .{ .whitespace = .indent_2 });
        } else {
            result = try allocator.dupe(u8, "{\"available\": false}");
        }
    } else {
        return makeErrorResponse(allocator, id, -32602, "Unknown tool", tool_name);
    }
    defer allocator.free(result);

    return makeToolResult(allocator, id, result);
}

fn handleStreamSystemReport(allocator: std.mem.Allocator) ![]u8 {
    const r = try collectors.collectAll(allocator);
    const timestamp = r.timestamp;

    var alloc_writer = std.Io.Writer.Allocating.init(allocator);
    errdefer alloc_writer.deinit();
    const w = &alloc_writer.writer;

    // Emit each collector's data as a separate JSON line
    try emitCollectorLine(allocator, w, "os", timestamp, &r.os);
    try emitCollectorLine(allocator, w, "system", timestamp, &r.system);
    try emitCollectorLine(allocator, w, "disk", timestamp, &r.disk);
    try emitCollectorLine(allocator, w, "network", timestamp, &r.network);
    try emitCollectorLine(allocator, w, "packages", timestamp, &r.packages);
    try emitCollectorLine(allocator, w, "services", timestamp, &r.services);
    try emitCollectorLine(allocator, w, "security", timestamp, &r.security);
    try emitCollectorLine(allocator, w, "hardware", timestamp, &r.hardware);

    // Nullable collectors
    if (r.docker) |docker| {
        try emitCollectorLine(allocator, w, "docker", timestamp, &docker);
    }
    if (r.snaps) |snaps| {
        try emitCollectorLine(allocator, w, "snaps", timestamp, &snaps);
    }
    if (r.gpu) |gpu| {
        try emitCollectorLine(allocator, w, "gpu", timestamp, &gpu);
    }
    if (r.logs) |logs| {
        try emitCollectorLine(allocator, w, "logs", timestamp, &logs);
    }

    // Emit issues
    try emitCollectorLine(allocator, w, "issues", timestamp, r.issues);

    // Emit completion marker
    try w.writeAll("{\"_complete\":true}");

    return alloc_writer.toOwnedSlice();
}

fn emitCollectorLine(allocator: std.mem.Allocator, writer: *std.Io.Writer, collector_name: []const u8, timestamp: []const u8, data: anytype) !void {
    try writer.writeAll("{\"collector\":\"");
    try writer.writeAll(collector_name);
    try writer.writeAll("\",\"timestamp\":\"");
    try writer.writeAll(timestamp);
    try writer.writeAll("\",\"data\":");

    // Serialize the data to string, then write
    // For pointers, dereference; for slices, use directly
    const T = @TypeOf(data);
    const json_data = if (comptime @typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .one)
        try std.json.Stringify.valueAlloc(allocator, data.*, .{ .whitespace = .minified, .emit_null_optional_fields = false })
    else
        try std.json.Stringify.valueAlloc(allocator, data, .{ .whitespace = .minified, .emit_null_optional_fields = false });
    defer allocator.free(json_data);
    try writer.writeAll(json_data);

    try writer.writeAll("}\n");
}

fn makeToolResult(allocator: std.mem.Allocator, id: ?[]const u8, content: []const u8) ![]u8 {
    var alloc_writer = std.Io.Writer.Allocating.init(allocator);
    errdefer alloc_writer.deinit();
    const w = &alloc_writer.writer;

    try w.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    if (id) |i| {
        try w.writeAll(i);
    } else {
        try w.writeAll("null");
    }
    try w.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":");
    // Escape the content as JSON string
    try writeJsonString(w, content);
    try w.writeAll("}]}}");

    return alloc_writer.toOwnedSlice();
}

fn makeErrorResponse(allocator: std.mem.Allocator, id: ?[]const u8, code: i32, message: []const u8, data: []const u8) []u8 {
    var alloc_writer = std.Io.Writer.Allocating.init(allocator);
    const w = &alloc_writer.writer;

    w.writeAll("{\"jsonrpc\":\"2.0\",\"id\":") catch return "";
    if (id) |i| {
        w.writeAll(i) catch return "";
    } else {
        w.writeAll("null") catch return "";
    }
    w.print(",\"error\":{{\"code\":{d},\"message\":\"{s}\",\"data\":\"{s}\"}}}}", .{ code, message, data }) catch return "";

    return alloc_writer.toOwnedSlice() catch "";
}

fn writeJsonString(w: *std.Io.Writer, s: []const u8) !void {
    try w.writeAll("\"");
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try w.print("\\u{x:0>4}", .{c});
                } else {
                    try w.print("{c}", .{c});
                }
            },
        }
    }
    try w.writeAll("\"");
}

fn extractJsonString(json: []const u8, key: []const u8) ?[]const u8 {
    const key_pos = std.mem.indexOf(u8, json, key) orelse return null;
    const start = key_pos + key.len;

    // Find the colon and opening quote
    var i = start;
    while (i < json.len and json[i] != '"') : (i += 1) {}
    if (i >= json.len) return null;
    i += 1; // Skip opening quote

    const value_start = i;
    while (i < json.len and json[i] != '"') : (i += 1) {
        if (json[i] == '\\' and i + 1 < json.len) i += 1; // Skip escaped chars
    }

    return json[value_start..i];
}

fn extractJsonValue(json: []const u8, key: []const u8) ?[]const u8 {
    const key_pos = std.mem.indexOf(u8, json, key) orelse return null;
    const start = key_pos + key.len;

    // Find the colon
    var i = start;
    while (i < json.len and json[i] != ':') : (i += 1) {}
    if (i >= json.len) return null;
    i += 1; // Skip colon

    // Skip whitespace
    while (i < json.len and (json[i] == ' ' or json[i] == '\t')) : (i += 1) {}

    const value_start = i;
    // Find end of value (comma, }, or ])
    while (i < json.len and json[i] != ',' and json[i] != '}' and json[i] != ']') : (i += 1) {}

    return std.mem.trim(u8, json[value_start..i], " \t");
}

fn extractNestedString(json: []const u8, outer_key: []const u8, inner_key: []const u8) ?[]const u8 {
    const outer_pos = std.mem.indexOf(u8, json, outer_key) orelse return null;
    const nested = json[outer_pos..];
    return extractJsonString(nested, inner_key);
}

// Serialization helpers
fn serializeIssues(allocator: std.mem.Allocator, issues: []const report.Issue) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, issues, .{ .whitespace = .indent_2 });
}

fn serializeSystemInfo(allocator: std.mem.Allocator, sys: *const report.SystemInfo) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, sys.*, .{ .whitespace = .indent_2 });
}

fn serializeDiskInfo(allocator: std.mem.Allocator, disk: *const report.DiskInfo) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, disk.*, .{ .whitespace = .indent_2 });
}

fn serializeNetworkInfo(allocator: std.mem.Allocator, net: *const report.NetworkInfo) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, net.*, .{ .whitespace = .indent_2 });
}

fn serializePackageInfo(allocator: std.mem.Allocator, pkg: *const report.PackageInfo) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, pkg.*, .{ .whitespace = .indent_2 });
}

fn serializeServiceInfo(allocator: std.mem.Allocator, svc: *const report.ServiceInfo) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, svc.*, .{ .whitespace = .indent_2 });
}

fn serializeSecurityInfo(allocator: std.mem.Allocator, sec: *const report.SecurityInfo) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, sec.*, .{ .whitespace = .indent_2 });
}

fn serializeHardwareInfo(allocator: std.mem.Allocator, hw: *const report.HardwareInfo) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, hw.*, .{ .whitespace = .indent_2 });
}
