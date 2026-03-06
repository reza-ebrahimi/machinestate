const std = @import("std");

extern fn popen(command: [*:0]const u8, mode: [*:0]const u8) ?*std.c.FILE;
extern fn pclose(stream: *std.c.FILE) c_int;
extern fn fread(ptr: [*]u8, size: usize, nmemb: usize, stream: *std.c.FILE) usize;

/// Read entire file contents into an allocated buffer
pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const fd = std.posix.open(path, .{ .ACCMODE = .RDONLY }, 0) catch |err| {
        return err;
    };
    defer std.posix.close(fd);

    var buffer = std.ArrayList(u8).empty;
    errdefer buffer.deinit(allocator);

    var chunk: [4096]u8 = undefined;
    while (true) {
        const bytes_read = std.posix.read(fd, &chunk) catch |err| {
            return err;
        };
        if (bytes_read == 0) break;
        try buffer.appendSlice(allocator, chunk[0..bytes_read]);
    }

    return buffer.toOwnedSlice(allocator);
}

/// Read file contents into a fixed buffer (no allocation)
pub fn readFileFixed(path: []const u8, buf: []u8) ![]u8 {
    const fd = std.posix.open(path, .{ .ACCMODE = .RDONLY }, 0) catch |err| {
        return err;
    };
    defer std.posix.close(fd);

    var total: usize = 0;
    while (total < buf.len) {
        const bytes_read = std.posix.read(fd, buf[total..]) catch |err| {
            return err;
        };
        if (bytes_read == 0) break;
        total += bytes_read;
    }

    return buf[0..total];
}

/// Check if a file exists
pub fn fileExists(path: []const u8) bool {
    if (path.len >= 511) return false;
    var path_z: [512:0]u8 = undefined;
    @memcpy(path_z[0..path.len], path);
    path_z[path.len] = 0;

    // Use C library access() with F_OK = 0
    const result = std.c.access(@ptrCast(&path_z), 0);
    return result == 0;
}

/// Parse an integer from a string, returning default on failure
pub fn parseInt(comptime T: type, str: []const u8, default: T) T {
    return std.fmt.parseInt(T, str, 10) catch default;
}

/// Parse a float from a string, returning default on failure
pub fn parseFloat(str: []const u8, default: f64) f64 {
    return std.fmt.parseFloat(f64, str) catch default;
}

/// Trim whitespace from both ends
pub fn trim(str: []const u8) []const u8 {
    return std.mem.trim(u8, str, " \t\n\r");
}

/// Format bytes to human-readable string (KB, MB, GB, etc.)
pub fn formatBytes(allocator: std.mem.Allocator, bytes: u64) ![]u8 {
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB", "PB" };
    var value: f64 = @floatFromInt(bytes);
    var unit_idx: usize = 0;

    while (value >= 1024 and unit_idx < units.len - 1) {
        value /= 1024;
        unit_idx += 1;
    }

    var buf: [32]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{d:.1} {s}", .{ value, units[unit_idx] }) catch return error.FormatError;
    return allocator.dupe(u8, result);
}

/// Format uptime duration to human-readable string
pub fn formatUptime(allocator: std.mem.Allocator, seconds: u64) ![]u8 {
    const days = seconds / 86400;
    const hours = (seconds % 86400) / 3600;
    const minutes = (seconds % 3600) / 60;

    var buf: [64]u8 = undefined;
    const result = if (days > 0)
        std.fmt.bufPrint(&buf, "{d}d {d}h {d}m", .{ days, hours, minutes }) catch return error.FormatError
    else if (hours > 0)
        std.fmt.bufPrint(&buf, "{d}h {d}m", .{ hours, minutes }) catch return error.FormatError
    else
        std.fmt.bufPrint(&buf, "{d}m", .{minutes}) catch return error.FormatError;

    return allocator.dupe(u8, result);
}

test "formatBytes" {
    const allocator = std.testing.allocator;

    const result1 = try formatBytes(allocator, 1024);
    defer allocator.free(result1);
    try std.testing.expectEqualSlices(u8, "1.0 KB", result1);

    const result2 = try formatBytes(allocator, 1073741824);
    defer allocator.free(result2);
    try std.testing.expectEqualSlices(u8, "1.0 GB", result2);
}

test "formatUptime" {
    const allocator = std.testing.allocator;

    const result1 = try formatUptime(allocator, 3661);
    defer allocator.free(result1);
    try std.testing.expectEqualSlices(u8, "1h 1m", result1);

    const result2 = try formatUptime(allocator, 90061);
    defer allocator.free(result2);
    try std.testing.expectEqualSlices(u8, "1d 1h 1m", result2);
}

/// Run a command and capture stdout
pub fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    // Build shell command with proper quoting
    var cmd_buf: [4096]u8 = undefined;
    var len: usize = 0;

    for (argv, 0..) |arg, i| {
        if (i > 0) {
            cmd_buf[len] = ' ';
            len += 1;
        }
        cmd_buf[len] = '\'';
        len += 1;
        for (arg) |c| {
            if (c == '\'') {
                if (len + 4 >= cmd_buf.len) return error.CommandFailed;
                @memcpy(cmd_buf[len..][0..4], "'\\''");
                len += 4;
            } else {
                if (len >= cmd_buf.len - 1) return error.CommandFailed;
                cmd_buf[len] = c;
                len += 1;
            }
        }
        cmd_buf[len] = '\'';
        len += 1;
    }

    const suffix = " 2>/dev/null";
    if (len + suffix.len >= cmd_buf.len) return error.CommandFailed;
    @memcpy(cmd_buf[len..][0..suffix.len], suffix);
    len += suffix.len;
    cmd_buf[len] = 0;

    const file = popen(@ptrCast(&cmd_buf), "r") orelse return error.CommandFailed;

    var output = std.ArrayList(u8).empty;
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = fread(&buf, 1, 4096, file);
        if (n == 0) break;
        output.appendSlice(allocator, buf[0..n]) catch {
            _ = pclose(file);
            output.deinit(allocator);
            return error.CommandFailed;
        };
    }

    const status = pclose(file);
    if (status != 0) {
        output.deinit(allocator);
        return error.CommandFailed;
    }

    return output.toOwnedSlice(allocator) catch {
        output.deinit(allocator);
        return error.CommandFailed;
    };
}

/// Check if a command exists in PATH
pub fn commandExists(cmd: []const u8) bool {
    const path_env = std.posix.getenv("PATH") orelse return false;
    var path_iter = std.mem.splitScalar(u8, path_env, ':');

    var path_buf: [512]u8 = undefined;
    while (path_iter.next()) |dir| {
        const full_path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ dir, cmd }) catch continue;
        if (fileExists(full_path)) return true;
    }
    return false;
}
