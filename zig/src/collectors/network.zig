const std = @import("std");
const utils = @import("../utils.zig");
const report = @import("../models/report.zig");

/// Collect network information
pub fn collectNetworkInfo(allocator: std.mem.Allocator) report.NetworkInfo {
    var interfaces = std.ArrayList(report.NetworkInterface).empty;
    var listen_ports = std.ArrayList(report.ListenPort).empty;

    // Get interface list from /sys/class/net/
    collectInterfaces(allocator, &interfaces);

    // Get listening ports from /proc/net/tcp and /proc/net/tcp6
    collectListenPorts(allocator, &listen_ports);

    // Test connectivity
    const connectivity = testConnectivity();

    return report.NetworkInfo{
        .interfaces = interfaces.toOwnedSlice(allocator) catch &[_]report.NetworkInterface{},
        .listen_ports = listen_ports.toOwnedSlice(allocator) catch &[_]report.ListenPort{},
        .connectivity = connectivity,
        .public_ip = null,
    };
}

fn collectInterfaces(allocator: std.mem.Allocator, interfaces: *std.ArrayList(report.NetworkInterface)) void {
    // Read /proc/net/dev for interface stats
    var dev_buf: [8192]u8 = undefined;
    const dev_content = utils.readFileFixed("/proc/net/dev", &dev_buf) catch return;

    var lines = std.mem.splitScalar(u8, dev_content, '\n');
    _ = lines.next(); // Skip header line 1
    _ = lines.next(); // Skip header line 2

    while (lines.next()) |line| {
        if (line.len == 0) continue;

        // Parse format: "  iface: rx_bytes ... tx_bytes ..."
        const colon_pos = std.mem.indexOf(u8, line, ":") orelse continue;
        const iface_name = utils.trim(line[0..colon_pos]);

        // Skip loopback and virtual interfaces
        if (std.mem.eql(u8, iface_name, "lo")) continue;
        if (std.mem.startsWith(u8, iface_name, "veth")) continue;

        const stats_part = utils.trim(line[colon_pos + 1 ..]);
        var stats = std.mem.splitScalar(u8, stats_part, ' ');

        // Skip empty parts and get rx_bytes (first field)
        var rx_bytes: u64 = 0;
        var tx_bytes: u64 = 0;
        var field_idx: usize = 0;

        while (stats.next()) |field| {
            if (field.len == 0) continue;
            if (field_idx == 0) {
                rx_bytes = utils.parseInt(u64, field, 0);
            } else if (field_idx == 8) {
                tx_bytes = utils.parseInt(u64, field, 0);
            }
            field_idx += 1;
        }

        // Get interface state and MAC
        const state = getInterfaceState(iface_name);
        const mac = getInterfaceMAC(allocator, iface_name);
        const ips = getInterfaceIPs(allocator, iface_name);

        interfaces.append(allocator, report.NetworkInterface{
            .name = allocator.dupe(u8, iface_name) catch continue,
            .state = state,
            .mac = mac,
            .ips = ips,
            .rx_bytes = rx_bytes,
            .tx_bytes = tx_bytes,
        }) catch continue;
    }
}

fn getInterfaceState(iface_name: []const u8) []const u8 {
    var path_buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "/sys/class/net/{s}/flags", .{iface_name}) catch return "DOWN";

    var buf: [32]u8 = undefined;
    const content = utils.readFileFixed(path, &buf) catch return "DOWN";
    const flags_str = utils.trim(content);

    // Parse hex flags like "0x1003"
    const flags = std.fmt.parseInt(u32, flags_str, 0) catch return "DOWN";

    // IFF_UP = 0x1
    if ((flags & 0x1) != 0) return "UP";
    return "DOWN";
}

fn getInterfaceMAC(allocator: std.mem.Allocator, iface_name: []const u8) []const u8 {
    var path_buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "/sys/class/net/{s}/address", .{iface_name}) catch return "";

    var buf: [32]u8 = undefined;
    const content = utils.readFileFixed(path, &buf) catch return "";
    return allocator.dupe(u8, utils.trim(content)) catch "";
}

fn getInterfaceIPs(allocator: std.mem.Allocator, iface_name: []const u8) []const []const u8 {
    var ips = std.ArrayList([]const u8).empty;

    const output = utils.runCommand(allocator, &[_][]const u8{
        "ip", "-o", "addr", "show", "dev", iface_name,
    }) catch return &[_][]const u8{};

    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        // Format: "3: wlp2s0 inet 192.168.178.58/24 ..."
        // Find "inet " or "inet6 " and extract the address
        const inet_pos = std.mem.indexOf(u8, line, " inet ") orelse
            std.mem.indexOf(u8, line, " inet6 ") orelse continue;

        const start = if (std.mem.indexOf(u8, line, " inet6 ") == inet_pos)
            inet_pos + 7
        else
            inet_pos + 6;

        if (start >= line.len) continue;

        // Find the end of the address (space or end)
        var end = start;
        while (end < line.len and line[end] != ' ') : (end += 1) {}

        const addr = line[start..end];
        if (addr.len > 0) {
            ips.append(allocator, allocator.dupe(u8, addr) catch continue) catch continue;
        }
    }

    return ips.toOwnedSlice(allocator) catch &[_][]const u8{};
}

fn collectListenPorts(allocator: std.mem.Allocator, ports: *std.ArrayList(report.ListenPort)) void {
    parseNetTcp(allocator, ports, "/proc/net/tcp", "TCP");
    parseNetTcp(allocator, ports, "/proc/net/tcp6", "TCP");
    parseNetTcp(allocator, ports, "/proc/net/udp", "UDP");
    parseNetTcp(allocator, ports, "/proc/net/udp6", "UDP");
}

fn parseNetTcp(allocator: std.mem.Allocator, ports: *std.ArrayList(report.ListenPort), path: []const u8, protocol: []const u8) void {
    var buf: [65536]u8 = undefined;
    const content = utils.readFileFixed(path, &buf) catch return;

    var lines = std.mem.splitScalar(u8, content, '\n');
    _ = lines.next(); // Skip header

    while (lines.next()) |line| {
        if (line.len == 0) continue;

        // Format: sl local_address rem_address st ...
        // We want state 0A (LISTEN for TCP) or any for UDP
        var parts = std.mem.splitScalar(u8, utils.trim(line), ' ');

        _ = skipEmpty(&parts); // sl
        const local_addr = skipEmpty(&parts) orelse continue;
        _ = skipEmpty(&parts); // rem_address
        const state = skipEmpty(&parts) orelse continue;

        // For TCP, only include LISTEN state (0A)
        // For UDP, include all bound sockets
        if (std.mem.eql(u8, protocol, "TCP") and !std.mem.eql(u8, state, "0A")) continue;

        // Parse local address (hex format: IP:PORT)
        const colon_pos = std.mem.indexOf(u8, local_addr, ":") orelse continue;
        const port_hex = local_addr[colon_pos + 1 ..];
        const port = std.fmt.parseInt(u32, port_hex, 16) catch continue;

        // Skip duplicate ports
        var found = false;
        for (ports.items) |p| {
            if (p.port == port and std.mem.eql(u8, p.protocol, protocol)) {
                found = true;
                break;
            }
        }
        if (found) continue;

        ports.append(allocator, report.ListenPort{
            .protocol = allocator.dupe(u8, protocol) catch continue,
            .address = "0.0.0.0",
            .port = port,
            .process = "",
            .pid = 0,
        }) catch continue;
    }
}

fn skipEmpty(iter: *std.mem.SplitIterator(u8, .scalar)) ?[]const u8 {
    while (iter.next()) |part| {
        if (part.len > 0) return part;
    }
    return null;
}

fn testConnectivity() bool {
    // Try to connect to 8.8.8.8:53 (Google DNS)
    // Use blocking connect with a simple approach
    const sock = std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0) catch return false;
    defer std.posix.close(sock);

    var addr: std.posix.sockaddr.in = .{
        .family = std.posix.AF.INET,
        .port = std.mem.nativeToBig(u16, 53),
        .addr = std.mem.nativeToBig(u32, (8 << 24) | (8 << 16) | (8 << 8) | 8), // 8.8.8.8
    };

    // Try to connect (blocking)
    std.posix.connect(sock, @ptrCast(&addr), @sizeOf(@TypeOf(addr))) catch {
        return false;
    };

    return true;
}
