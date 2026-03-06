const std = @import("std");
const report = @import("../models/report.zig");

/// Render a report as pretty-printed JSON with 2-space indentation
pub fn renderJson(allocator: std.mem.Allocator, r: *const report.Report) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, r.*, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false, // omitempty behavior
    });
}

/// Render a report as compact JSON (single line, no whitespace)
pub fn renderJsonCompact(allocator: std.mem.Allocator, r: *const report.Report) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, r.*, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false, // omitempty behavior
    });
}

/// Generic JSON serialization for any type (used by MCP server)
pub fn toJson(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, value, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    });
}

/// Generic compact JSON serialization for any type
pub fn toJsonCompact(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, value, .{
        .whitespace = .minified,
        .emit_null_optional_fields = false,
    });
}

test "renderJson produces valid JSON" {
    const allocator = std.testing.allocator;
    var r = report.emptyReport();
    r.hostname = "test-host";
    r.timestamp = "2025-12-30T10:00:00Z";

    const json_output = try renderJson(allocator, &r);
    defer allocator.free(json_output);

    // Verify it starts with {
    try std.testing.expect(json_output.len > 0);
    try std.testing.expectEqual(json_output[0], '{');
}

test "renderJsonCompact produces single-line JSON" {
    const allocator = std.testing.allocator;
    var r = report.emptyReport();
    r.hostname = "test-host";
    r.timestamp = "2025-12-30T10:00:00Z";

    const json_output = try renderJsonCompact(allocator, &r);
    defer allocator.free(json_output);

    // Verify no newlines in compact output
    for (json_output) |c| {
        try std.testing.expect(c != '\n');
    }
}
