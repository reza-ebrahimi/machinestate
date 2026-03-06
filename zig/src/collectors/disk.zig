const std = @import("std");
const utils = @import("../utils.zig");
const report = @import("../models/report.zig");

// Linux statvfs structure (from statfs syscall)
const Statfs = extern struct {
    f_type: c_long,
    f_bsize: c_long,
    f_blocks: c_ulong,
    f_bfree: c_ulong,
    f_bavail: c_ulong,
    f_files: c_ulong,
    f_ffree: c_ulong,
    f_fsid: [2]c_int,
    f_namelen: c_long,
    f_frsize: c_long,
    f_flags: c_long,
    f_spare: [4]c_long,
};

extern "c" fn statfs(path: [*:0]const u8, buf: *Statfs) c_int;

// Filesystem types to exclude (virtual filesystems)
const excluded_fs_types = [_][]const u8{
    "proc",
    "sysfs",
    "devfs",
    "devpts",
    "devtmpfs",
    "tmpfs",
    "securityfs",
    "cgroup",
    "cgroup2",
    "pstore",
    "debugfs",
    "hugetlbfs",
    "mqueue",
    "fusectl",
    "configfs",
    "binfmt_misc",
    "autofs",
    "efivarfs",
    "squashfs",
    "overlay",
    "nsfs",
    "tracefs",
    "ramfs",
};

/// Collect disk/filesystem information by parsing /proc/mounts and calling statfs
pub fn collectDiskInfo(allocator: std.mem.Allocator) report.DiskInfo {
    var filesystems = std.ArrayList(report.Filesystem).empty;

    // Parse /proc/mounts
    var mounts_buf: [65536]u8 = undefined;
    const mounts_content = utils.readFileFixed("/proc/mounts", &mounts_buf) catch {
        return report.DiskInfo{ .filesystems = filesystems.toOwnedSlice(allocator) catch &[_]report.Filesystem{} };
    };

    var lines = std.mem.splitScalar(u8, mounts_content, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        // Parse mount line: device mount_point fs_type options dump pass
        var parts = std.mem.splitScalar(u8, line, ' ');
        const device = parts.next() orelse continue;
        const mount_point = parts.next() orelse continue;
        const fs_type = parts.next() orelse continue;

        // Skip excluded filesystem types
        if (isExcludedFsType(fs_type)) continue;

        // Skip /snap/* mounts
        if (std.mem.startsWith(u8, mount_point, "/snap/")) continue;

        // Get filesystem stats using statfs
        if (getFilesystemStats(allocator, device, mount_point, fs_type)) |fs| {
            filesystems.append(allocator, fs) catch continue;
        }
    }

    return report.DiskInfo{
        .filesystems = filesystems.toOwnedSlice(allocator) catch &[_]report.Filesystem{},
    };
}

fn isExcludedFsType(fs_type: []const u8) bool {
    for (excluded_fs_types) |excluded| {
        if (std.mem.eql(u8, fs_type, excluded)) {
            return true;
        }
    }
    return false;
}

fn getFilesystemStats(allocator: std.mem.Allocator, device: []const u8, mount_point: []const u8, fs_type: []const u8) ?report.Filesystem {
    // Create null-terminated path for statfs
    var path_buf: [4096]u8 = undefined;
    if (mount_point.len >= path_buf.len - 1) return null;

    @memcpy(path_buf[0..mount_point.len], mount_point);
    path_buf[mount_point.len] = 0;

    var stat: Statfs = undefined;
    const result = statfs(@ptrCast(&path_buf), &stat);
    if (result != 0) return null;

    const block_size: u64 = @intCast(@max(stat.f_frsize, stat.f_bsize));
    const total_blocks: u64 = @intCast(stat.f_blocks);
    const free_blocks: u64 = @intCast(stat.f_bfree);
    const avail_blocks: u64 = @intCast(stat.f_bavail);

    const total = total_blocks * block_size;
    const free = avail_blocks * block_size;
    const used = total - (free_blocks * block_size);

    // Skip filesystems with 0 total (virtual)
    if (total == 0) return null;

    const used_percent: f64 = @as(f64, @floatFromInt(used)) / @as(f64, @floatFromInt(total)) * 100.0;

    // Inode info
    const inodes_total: u64 = @intCast(stat.f_files);
    const inodes_free: u64 = @intCast(stat.f_ffree);
    const inodes_used = inodes_total - inodes_free;

    const inodes_percent: f64 = if (inodes_total > 0)
        @as(f64, @floatFromInt(inodes_used)) / @as(f64, @floatFromInt(inodes_total)) * 100.0
    else
        0;

    return report.Filesystem{
        .device = allocator.dupe(u8, device) catch return null,
        .mount_point = allocator.dupe(u8, mount_point) catch return null,
        .fs_type = allocator.dupe(u8, fs_type) catch return null,
        .total = total,
        .used = used,
        .free = free,
        .used_percent = used_percent,
        .inodes_total = inodes_total,
        .inodes_used = inodes_used,
        .inodes_free = inodes_free,
        .inodes_percent = inodes_percent,
    };
}

test "isExcludedFsType" {
    try std.testing.expect(isExcludedFsType("tmpfs"));
    try std.testing.expect(isExcludedFsType("proc"));
    try std.testing.expect(isExcludedFsType("sysfs"));
    try std.testing.expect(!isExcludedFsType("ext4"));
    try std.testing.expect(!isExcludedFsType("xfs"));
}
