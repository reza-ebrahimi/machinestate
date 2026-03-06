const std = @import("std");
const utils = @import("../utils.zig");
const report = @import("../models/report.zig");

/// Collect Docker information
pub fn collectDockerInfo(allocator: std.mem.Allocator) ?report.DockerInfo {
    // Check if docker command exists
    if (!utils.commandExists("docker")) {
        return report.DockerInfo{
            .available = false,
        };
    }

    // Check if Docker daemon is running
    _ = utils.runCommand(allocator, &[_][]const u8{ "docker", "info" }) catch {
        return report.DockerInfo{
            .available = true,
            .daemon_running = false,
        };
    };

    var containers = std.ArrayList(report.ContainerInfo).empty;

    // Get container list
    const ps_output = utils.runCommand(allocator, &[_][]const u8{
        "docker", "ps", "-a", "--format", "{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.State}}\t{{.CreatedAt}}",
    }) catch "";

    if (ps_output.len > 0) {
        var lines = std.mem.splitScalar(u8, ps_output, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            if (parseContainerLine(allocator, line)) |container| {
                containers.append(allocator, container) catch continue;
            }
        }
    }

    // Count running/stopped containers
    var running: i32 = 0;
    var stopped: i32 = 0;
    for (containers.items) |c| {
        if (std.mem.eql(u8, c.state, "running")) {
            running += 1;
        } else {
            stopped += 1;
        }
    }

    // Get image count
    const images_output = utils.runCommand(allocator, &[_][]const u8{
        "docker", "images", "--format", "{{.Size}}",
    }) catch "";

    var image_count: i32 = 0;
    var total_image_size: i64 = 0;
    if (images_output.len > 0) {
        var img_lines = std.mem.splitScalar(u8, images_output, '\n');
        while (img_lines.next()) |l| {
            if (l.len > 0) {
                image_count += 1;
                total_image_size += @intCast(parseSizeString(l));
            }
        }
    }

    // Get dangling images size
    var dangling_size: i64 = 0;
    const dangling_output = utils.runCommand(allocator, &[_][]const u8{
        "docker", "images", "-f", "dangling=true", "--format", "{{.Size}}",
    }) catch "";

    if (dangling_output.len > 0) {
        var lines = std.mem.splitScalar(u8, dangling_output, '\n');
        while (lines.next()) |l| {
            if (l.len > 0) {
                dangling_size += @intCast(parseSizeString(l));
            }
        }
    }

    const container_slice: ?[]const report.ContainerInfo = if (containers.items.len == 0)
        null
    else
        containers.toOwnedSlice(allocator) catch null;

    return report.DockerInfo{
        .available = true,
        .daemon_running = true,
        .containers = container_slice,
        .running_count = running,
        .stopped_count = stopped,
        .image_count = image_count,
        .total_image_size = total_image_size,
        .dangling_images_size = dangling_size,
    };
}

fn parseContainerLine(allocator: std.mem.Allocator, line: []const u8) ?report.ContainerInfo {
    var parts = std.mem.splitScalar(u8, line, '\t');

    const name = parts.next() orelse return null;
    const image = parts.next() orelse return null;
    const status = parts.next() orelse return null;
    const state = parts.next() orelse return null;
    const created = parts.next() orelse "";

    return report.ContainerInfo{
        .name = allocator.dupe(u8, name) catch return null,
        .image = allocator.dupe(u8, image) catch return null,
        .status = allocator.dupe(u8, status) catch return null,
        .state = allocator.dupe(u8, state) catch return null,
        .created = allocator.dupe(u8, created) catch "",
    };
}

fn parseSizeString(s: []const u8) u64 {
    const trimmed = utils.trim(s);
    if (trimmed.len == 0) return 0;

    var num_end: usize = 0;
    for (trimmed) |c| {
        if ((c >= '0' and c <= '9') or c == '.') {
            num_end += 1;
        } else {
            break;
        }
    }

    if (num_end == 0) return 0;

    const num = utils.parseFloat(trimmed[0..num_end], 0);
    const unit = if (num_end < trimmed.len) trimmed[num_end..] else "";

    const multiplier: f64 = if (std.mem.startsWith(u8, unit, "TB") or std.mem.startsWith(u8, unit, "T"))
        1024 * 1024 * 1024 * 1024
    else if (std.mem.startsWith(u8, unit, "GB") or std.mem.startsWith(u8, unit, "G"))
        1024 * 1024 * 1024
    else if (std.mem.startsWith(u8, unit, "MB") or std.mem.startsWith(u8, unit, "M"))
        1024 * 1024
    else if (std.mem.startsWith(u8, unit, "KB") or std.mem.startsWith(u8, unit, "K") or std.mem.startsWith(u8, unit, "kB"))
        1024
    else
        1;

    return @intFromFloat(num * multiplier);
}
