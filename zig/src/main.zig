const std = @import("std");
const report = @import("models/report.zig");
const json_output = @import("outputs/json.zig");
const terminal_output = @import("outputs/terminal.zig");
const html_output = @import("outputs/html.zig");
const markdown_output = @import("outputs/markdown.zig");
const collectors = @import("collectors/mod.zig");
const mcp_server = @import("mcp/server.zig");
const http_server = @import("http/server.zig");

const version = "1.0.0";

// Signal handling for graceful Ctrl+C shutdown
var signal_pipe: [2]std.posix.fd_t = .{ -1, -1 };
var signal_received: bool = false;

fn signalHandler(_: std.posix.SIG) callconv(.c) void {
    signal_received = true;
    // Write to pipe to wake up poll()
    if (signal_pipe[1] != -1) {
        _ = std.posix.write(signal_pipe[1], "x") catch {};
    }
}

const Format = enum {
    terminal,
    json,
    html,
    markdown,
    all,
};

const Args = struct {
    format: Format = .terminal,
    output: ?[]const u8 = null,
    quiet: bool = false,
    json_compact: bool = false,
    stream: bool = false,
    interval: u64 = 5, // seconds
    duration: u64 = 0, // seconds (0 = infinite)
    count: u64 = 0, // cycles (0 = infinite)
    collectors_filter: ?[]const u8 = null,
    config: ?[]const u8 = null,
    http_port: ?[]const u8 = null,
    mcp: bool = false,
    show_version: bool = false,
    show_help: bool = false,
    // Error tracking for flags that require values
    missing_arg: ?[]const u8 = null,
};

fn writeStdout(data: []const u8) void {
    _ = std.posix.write(std.posix.STDOUT_FILENO, data) catch {};
}

fn writeStderr(data: []const u8) void {
    _ = std.posix.write(std.posix.STDERR_FILENO, data) catch {};
}

fn printUsage() void {
    writeStdout(
        \\Usage: machinestate [options]
        \\       machinestate --stream
        \\       machinestate --http 8080
        \\       machinestate --mcp
        \\
        \\Options:
        \\  --format <fmt>       Output format: terminal, html, json, markdown, all (default: terminal)
        \\  --output <path>      Output file path (stdout if empty)
        \\  --quiet              Suppress terminal output when using --format all
        \\  --json-compact       Output minified JSON (single line)
        \\  --stream             Enable continuous streaming mode (JSONL output)
        \\  --interval <sec>     Interval between streaming cycles in seconds (default: 5)
        \\  --duration <sec>     Maximum streaming duration in seconds (0 = infinite)
        \\  --count <num>        Number of streaming cycles (0 = infinite)
        \\  --collectors <list>  Comma-separated collectors to stream (empty = all)
        \\  --config <path>      Path to YAML config file
        \\  --http <port>        Run HTTP server on specified port (e.g., 8080)
        \\  --mcp                Run as MCP server using stdio transport
        \\  --version            Print version and exit
        \\  --help               Show this help message
        \\
        \\Examples:
        \\  machinestate                                    Terminal output (default)
        \\  machinestate --format json                      JSON output to stdout
        \\  machinestate --stream                           Stream all collectors every 5s
        \\  machinestate --stream --interval 10             Stream every 10 seconds
        \\  machinestate --stream --collectors system,disk  Stream specific collectors
        \\  machinestate --stream --count 10                Stream 10 cycles then stop
        \\  machinestate --stream --duration 3600           Stream for 1 hour (3600s)
        \\  machinestate --http 8080                        Start HTTP server on port 8080
        \\
        \\MCP Server:
        \\  Configure in Claude Code with:
        \\  claude mcp add-json machinestate '{"type":"stdio","command":"/path/to/machinestate","args":["--mcp"]}'
        \\
    );
}

fn parseArgs() Args {
    var args = Args{};
    var arg_iter = std.process.ArgIterator.init();

    // Skip program name
    _ = arg_iter.skip();

    while (arg_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            args.show_version = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            args.show_help = true;
        } else if (std.mem.eql(u8, arg, "--format")) {
            if (arg_iter.next()) |fmt| {
                if (std.mem.eql(u8, fmt, "terminal")) {
                    args.format = .terminal;
                } else if (std.mem.eql(u8, fmt, "json")) {
                    args.format = .json;
                } else if (std.mem.eql(u8, fmt, "html")) {
                    args.format = .html;
                } else if (std.mem.eql(u8, fmt, "markdown")) {
                    args.format = .markdown;
                } else if (std.mem.eql(u8, fmt, "all")) {
                    args.format = .all;
                }
            } else {
                args.missing_arg = "--format";
            }
        } else if (std.mem.eql(u8, arg, "--output")) {
            if (arg_iter.next()) |val| {
                args.output = val;
            } else {
                args.missing_arg = "--output";
            }
        } else if (std.mem.eql(u8, arg, "--quiet")) {
            args.quiet = true;
        } else if (std.mem.eql(u8, arg, "--json-compact")) {
            args.json_compact = true;
        } else if (std.mem.eql(u8, arg, "--stream")) {
            args.stream = true;
        } else if (std.mem.eql(u8, arg, "--interval")) {
            if (arg_iter.next()) |val| {
                args.interval = std.fmt.parseInt(u64, val, 10) catch 5;
            } else {
                args.missing_arg = "--interval";
            }
        } else if (std.mem.eql(u8, arg, "--duration")) {
            if (arg_iter.next()) |val| {
                args.duration = std.fmt.parseInt(u64, val, 10) catch 0;
            } else {
                args.missing_arg = "--duration";
            }
        } else if (std.mem.eql(u8, arg, "--count")) {
            if (arg_iter.next()) |val| {
                args.count = std.fmt.parseInt(u64, val, 10) catch 0;
            } else {
                args.missing_arg = "--count";
            }
        } else if (std.mem.eql(u8, arg, "--collectors")) {
            if (arg_iter.next()) |val| {
                args.collectors_filter = val;
            } else {
                args.missing_arg = "--collectors";
            }
        } else if (std.mem.eql(u8, arg, "--config")) {
            if (arg_iter.next()) |val| {
                args.config = val;
            } else {
                args.missing_arg = "--config";
            }
        } else if (std.mem.eql(u8, arg, "--http")) {
            if (arg_iter.next()) |val| {
                args.http_port = val;
            } else {
                args.missing_arg = "--http";
            }
        } else if (std.mem.eql(u8, arg, "--mcp")) {
            args.mcp = true;
        }
    }

    return args;
}

pub fn main() !void {
    // Use arena allocator to batch-free all allocations at the end
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = parseArgs();

    // Handle missing arguments for flags that require values
    if (args.missing_arg) |flag| {
        writeStderr("Error: ");
        writeStderr(flag);
        writeStderr(" requires an argument\n\n");
        printUsage();
        return;
    }

    // Handle --version
    if (args.show_version) {
        writeStdout("machinestate version ");
        writeStdout(version);
        writeStdout("\n");
        return;
    }

    // Handle --help
    if (args.show_help) {
        printUsage();
        return;
    }

    // Handle --mcp
    if (args.mcp) {
        mcp_server.runMcpServer(allocator) catch |err| {
            writeStderr("MCP server error: ");
            _ = err;
            return;
        };
        return;
    }

    // Handle --http
    if (args.http_port) |port| {
        http_server.run(allocator, port) catch {
            writeStderr("HTTP server error\n");
            return;
        };
        return;
    }

    // Handle streaming mode
    if (args.stream) {
        try runContinuousStreaming(allocator, args.interval, args.duration, args.count, args.collectors_filter);
        return;
    }

    // Collect system state
    const r = try collectors.collectAll(allocator);

    // Render output based on format
    switch (args.format) {
        .json => {
            const output = if (args.json_compact)
                try json_output.renderJsonCompact(allocator, &r)
            else
                try json_output.renderJson(allocator, &r);
            defer allocator.free(output);

            if (args.output) |path| {
                const fd = try std.posix.open(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
                defer std.posix.close(fd);
                _ = try std.posix.write(fd, output);
                _ = try std.posix.write(fd, "\n");
            } else {
                writeStdout(output);
                writeStdout("\n");
            }
        },
        .terminal => {
            const output = try terminal_output.renderTerminal(allocator, &r);
            defer allocator.free(output);

            if (args.output) |path| {
                const fd = try std.posix.open(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
                defer std.posix.close(fd);
                _ = try std.posix.write(fd, output);
            } else {
                writeStdout(output);
            }
        },
        .html => {
            const output = try html_output.renderHtml(allocator, &r);
            defer allocator.free(output);

            if (args.output) |path| {
                const fd = try std.posix.open(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
                defer std.posix.close(fd);
                _ = try std.posix.write(fd, output);
            } else {
                writeStdout(output);
            }
        },
        .markdown => {
            const output = try markdown_output.renderMarkdown(allocator, &r);
            defer allocator.free(output);

            if (args.output) |path| {
                const fd = try std.posix.open(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
                defer std.posix.close(fd);
                _ = try std.posix.write(fd, output);
            } else {
                writeStdout(output);
            }
        },
        .all => {
            // Output all formats with appropriate extensions
            const base_path = args.output orelse "report";
            var path_buf: [512]u8 = undefined;

            // JSON
            const json_path = std.fmt.bufPrint(&path_buf, "{s}.json", .{base_path}) catch base_path;
            const json_out = try json_output.renderJson(allocator, &r);
            defer allocator.free(json_out);
            const json_fd = try std.posix.open(json_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
            _ = try std.posix.write(json_fd, json_out);
            std.posix.close(json_fd);

            // HTML
            var html_path_buf: [512]u8 = undefined;
            const html_path = std.fmt.bufPrint(&html_path_buf, "{s}.html", .{base_path}) catch base_path;
            const html_out = try html_output.renderHtml(allocator, &r);
            defer allocator.free(html_out);
            const html_fd = try std.posix.open(html_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
            _ = try std.posix.write(html_fd, html_out);
            std.posix.close(html_fd);

            // Markdown
            var md_path_buf: [512]u8 = undefined;
            const md_path = std.fmt.bufPrint(&md_path_buf, "{s}.md", .{base_path}) catch base_path;
            const md_out = try markdown_output.renderMarkdown(allocator, &r);
            defer allocator.free(md_out);
            const md_fd = try std.posix.open(md_path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
            _ = try std.posix.write(md_fd, md_out);
            std.posix.close(md_fd);

            // Terminal (to stdout unless --quiet)
            if (!args.quiet) {
                const term_out = try terminal_output.renderTerminal(allocator, &r);
                defer allocator.free(term_out);
                writeStdout(term_out);
            }
        },
    }
}

// runContinuousStreaming runs the streaming loop with signal handling
fn runContinuousStreaming(allocator: std.mem.Allocator, interval: u64, duration: u64, max_count: u64, collectors_filter: ?[]const u8) !void {
    // Parse collector filter
    const filter = parseCollectorFilter(collectors_filter);

    // Create signal pipe for graceful shutdown
    signal_pipe = std.posix.pipe() catch {
        // Fallback to simple loop without signal handling
        return runContinuousStreamingSimple(allocator, interval, duration, max_count, filter);
    };
    defer {
        std.posix.close(signal_pipe[0]);
        std.posix.close(signal_pipe[1]);
        signal_pipe = .{ -1, -1 };
    }

    // Register SIGINT handler
    var act: std.posix.Sigaction = .{
        .handler = .{ .handler = signalHandler },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &act, null);
    std.posix.sigaction(std.posix.SIG.TERM, &act, null);

    // Track start time and cycle count
    const start_ts = std.posix.clock_gettime(.REALTIME) catch return error.TimeFailed;
    const start_time: i64 = start_ts.sec;
    var cycle: u64 = 0;

    // Main streaming loop
    while (!signal_received) {
        cycle += 1;

        // Emit cycle start marker
        emitCycleStart(allocator, cycle);

        // Collect and emit data
        try outputStreamingCycle(allocator, filter);

        // Emit cycle complete marker
        emitCycleComplete(cycle);

        // Check count limit
        if (max_count > 0 and cycle >= max_count) {
            break;
        }

        // Check duration limit
        if (duration > 0) {
            const current_ts = std.posix.clock_gettime(.REALTIME) catch break;
            const elapsed = @as(u64, @intCast(current_ts.sec - start_time));
            if (elapsed >= duration) {
                break;
            }
        }

        // Poll on signal pipe with timeout (instead of nanosleep)
        var fds = [_]std.posix.pollfd{.{
            .fd = signal_pipe[0],
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const timeout_ms: i32 = @intCast(interval * 1000);
        _ = std.posix.poll(&fds, timeout_ms) catch {};

        // Check if signal was received during poll
        if (signal_received) break;
    }

    // Emit shutdown marker
    emitShutdownMarker(allocator, cycle);
}

// Fallback streaming without signal handling (if pipe creation fails)
fn runContinuousStreamingSimple(allocator: std.mem.Allocator, interval: u64, duration: u64, max_count: u64, filter: CollectorFilter) !void {
    const start_ts = std.posix.clock_gettime(.REALTIME) catch return error.TimeFailed;
    const start_time: i64 = start_ts.sec;
    var cycle: u64 = 0;

    while (true) {
        cycle += 1;
        emitCycleStart(allocator, cycle);
        try outputStreamingCycle(allocator, filter);
        emitCycleComplete(cycle);

        if (max_count > 0 and cycle >= max_count) break;
        if (duration > 0) {
            const current_ts = std.posix.clock_gettime(.REALTIME) catch break;
            const elapsed = @as(u64, @intCast(current_ts.sec - start_time));
            if (elapsed >= duration) break;
        }
        std.posix.nanosleep(interval, 0);
    }
    emitShutdownMarker(allocator, cycle);
}

const CollectorFilter = struct {
    os: bool = false,
    system: bool = false,
    disk: bool = false,
    network: bool = false,
    packages: bool = false,
    services: bool = false,
    security: bool = false,
    hardware: bool = false,
    docker: bool = false,
    snaps: bool = false,
    gpu: bool = false,
    logs: bool = false,
    issues: bool = false,
    has_filter: bool = false,
};

fn parseCollectorFilter(collectors_str: ?[]const u8) CollectorFilter {
    var filter = CollectorFilter{};

    const str = collectors_str orelse return filter;
    if (str.len == 0) return filter;

    filter.has_filter = true;

    // Parse comma-separated list
    var iter = std.mem.splitSequence(u8, str, ",");
    while (iter.next()) |part| {
        const name = std.mem.trim(u8, part, " ");
        if (std.mem.eql(u8, name, "os")) filter.os = true else if (std.mem.eql(u8, name, "system")) filter.system = true else if (std.mem.eql(u8, name, "disk")) filter.disk = true else if (std.mem.eql(u8, name, "network")) filter.network = true else if (std.mem.eql(u8, name, "packages")) filter.packages = true else if (std.mem.eql(u8, name, "services")) filter.services = true else if (std.mem.eql(u8, name, "security")) filter.security = true else if (std.mem.eql(u8, name, "hardware")) filter.hardware = true else if (std.mem.eql(u8, name, "docker")) filter.docker = true else if (std.mem.eql(u8, name, "snaps")) filter.snaps = true else if (std.mem.eql(u8, name, "gpu")) filter.gpu = true else if (std.mem.eql(u8, name, "logs")) filter.logs = true else if (std.mem.eql(u8, name, "issues")) filter.issues = true;
    }

    // Always include issues if filter is active
    if (filter.has_filter) {
        filter.issues = true;
    }

    return filter;
}

fn emitCycleStart(allocator: std.mem.Allocator, cycle: u64) void {
    var buf: [256]u8 = undefined;
    const timestamp = getTimestamp(allocator) catch "unknown";
    const line = std.fmt.bufPrint(&buf, "{{\"_cycle\":{d},\"_timestamp\":\"{s}\"}}\n", .{ cycle, timestamp }) catch return;
    writeStdout(line);
}

fn emitCycleComplete(cycle: u64) void {
    var buf: [64]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "{{\"_cycle_complete\":{d}}}\n", .{cycle}) catch return;
    writeStdout(line);
}

fn emitShutdownMarker(allocator: std.mem.Allocator, total_cycles: u64) void {
    var buf: [256]u8 = undefined;
    const timestamp = getTimestamp(allocator) catch "unknown";
    const line = std.fmt.bufPrint(&buf, "{{\"_shutdown\":true,\"_total_cycles\":{d},\"_timestamp\":\"{s}\"}}\n", .{ total_cycles, timestamp }) catch return;
    writeStdout(line);
}

fn getTimestamp(allocator: std.mem.Allocator) ![]const u8 {
    const ts = std.posix.clock_gettime(.REALTIME) catch return allocator.dupe(u8, "unknown");
    const epoch_seconds: u64 = @intCast(ts.sec);
    const epoch_day = std.time.epoch.EpochSeconds{ .secs = epoch_seconds };
    const day_seconds = epoch_day.getDaySeconds();
    const year_day = epoch_day.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    return std.fmt.allocPrint(allocator, "{d}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year_day.year,
        @intFromEnum(month_day.month),
        month_day.day_index + 1, // day_index is 0-based
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    });
}

// outputStreamingCycle emits JSONL for one collection cycle with optional filtering
fn outputStreamingCycle(allocator: std.mem.Allocator, filter: anytype) !void {
    const r = try collectors.collectAll(allocator);
    const timestamp = r.timestamp;

    // Emit each collector's data as a separate JSON line (with filter)
    if (!filter.has_filter or filter.os) try emitCollectorResult(allocator, "os", timestamp, &r.os);
    if (!filter.has_filter or filter.system) try emitCollectorResult(allocator, "system", timestamp, &r.system);
    if (!filter.has_filter or filter.disk) try emitCollectorResult(allocator, "disk", timestamp, &r.disk);
    if (!filter.has_filter or filter.network) try emitCollectorResult(allocator, "network", timestamp, &r.network);
    if (!filter.has_filter or filter.packages) try emitCollectorResult(allocator, "packages", timestamp, &r.packages);
    if (!filter.has_filter or filter.services) try emitCollectorResult(allocator, "services", timestamp, &r.services);
    if (!filter.has_filter or filter.security) try emitCollectorResult(allocator, "security", timestamp, &r.security);
    if (!filter.has_filter or filter.hardware) try emitCollectorResult(allocator, "hardware", timestamp, &r.hardware);

    // Nullable collectors
    if (!filter.has_filter or filter.docker) {
        if (r.docker) |docker| {
            try emitCollectorResult(allocator, "docker", timestamp, &docker);
        }
    }
    if (!filter.has_filter or filter.snaps) {
        if (r.snaps) |snaps| {
            try emitCollectorResult(allocator, "snaps", timestamp, &snaps);
        }
    }
    if (!filter.has_filter or filter.gpu) {
        if (r.gpu) |gpu| {
            try emitCollectorResult(allocator, "gpu", timestamp, &gpu);
        }
    }
    if (!filter.has_filter or filter.logs) {
        if (r.logs) |logs| {
            try emitCollectorResult(allocator, "logs", timestamp, &logs);
        }
    }

    // Emit issues (always if filter active since we force it)
    if (!filter.has_filter or filter.issues) {
        try emitCollectorResult(allocator, "issues", timestamp, r.issues);
    }
}

fn emitCollectorResult(allocator: std.mem.Allocator, collector_name: []const u8, timestamp: []const u8, data: anytype) !void {
    var alloc_writer = std.Io.Writer.Allocating.init(allocator);
    defer alloc_writer.deinit();
    const w = &alloc_writer.writer;

    try w.writeAll("{\"collector\":\"");
    try w.writeAll(collector_name);
    try w.writeAll("\",\"timestamp\":\"");
    try w.writeAll(timestamp);
    try w.writeAll("\",\"data\":");

    // Serialize the data to string, then write
    // For pointers, dereference; for slices, use directly
    const T = @TypeOf(data);
    const json_data = if (comptime @typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .one)
        try std.json.Stringify.valueAlloc(allocator, data.*, .{ .whitespace = .minified, .emit_null_optional_fields = false })
    else
        try std.json.Stringify.valueAlloc(allocator, data, .{ .whitespace = .minified, .emit_null_optional_fields = false });
    defer allocator.free(json_data);
    try w.writeAll(json_data);

    try w.writeAll("}");

    const line = try alloc_writer.toOwnedSlice();
    defer allocator.free(line);

    writeStdout(line);
    writeStdout("\n");
}
