# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with this project.

## Project Overview

`ubuntu-state` is a Go CLI tool that generates comprehensive system health reports for Ubuntu/Linux systems. It collects system metrics, detects issues, and outputs reports in multiple formats (terminal, HTML, JSON, Markdown) with history tracking for comparison over time.

## Build & Run Commands

```bash
# Build the binary
go build -o ubuntu-state .

# Run with default terminal output
./ubuntu-state

# Run tests (if added)
go test ./...

# Install dependencies
go mod tidy
```

## Architecture

### Directory Structure

- `main.go` - CLI entry point using standard `flag` package
- `collectors/` - Data collection modules (one file per category)
- `models/report.go` - All data structures used across the app
- `outputs/` - Output formatters (terminal, HTML, JSON, markdown)
- `history/` - Report persistence and comparison logic
- `mcpserver/` - MCP server implementation for Claude Code integration

### Key Design Decisions

1. **Single binary** - No external dependencies at runtime; everything compiles into one executable
2. **gopsutil library** - Used for cross-platform system metrics (CPU, memory, disk, network, processes)
3. **Direct sysfs reads** - Battery and temperature data read directly from `/sys/` for reliability
4. **Shell commands** - APT, systemctl, ufw status collected via exec (Ubuntu-specific)
5. **History as JSON** - Reports saved as timestamped JSON files in `~/.local/share/ubuntu-state/history/`

### Data Flow

```
main.go
  └── collectors.CollectAll()
        ├── CollectOSInfo()
        ├── CollectSystemInfo()    # CPU, memory, load
        ├── CollectDiskInfo()      # Filesystems
        ├── CollectNetworkInfo()   # Interfaces, ports
        ├── CollectPackageInfo()   # APT status
        ├── CollectServiceInfo()   # Systemd, processes
        ├── CollectSecurityInfo()  # Firewall, SSH
        ├── CollectHardwareInfo()  # Battery, temps
        └── analyzeIssues()        # Generate issue list
  └── history.Save(report)
  └── outputs.Render*(report)      # Format output
```

### Adding New Collectors

1. Create a new file in `collectors/` (e.g., `docker.go`)
2. Add corresponding fields to `models/report.go`
3. Call the collector from `CollectAll()` in `collectors/collector.go`
4. Add issue detection logic in `analyzeIssues()` if needed
5. Update all output formatters in `outputs/`

### Adding New Output Formats

1. Create a new file in `outputs/` (e.g., `csv.go`)
2. Implement a `Render*` function that takes `*models.Report` and returns string
3. Add the format option to `main.go` switch statement

## Dependencies

- `github.com/shirou/gopsutil/v3` - System metrics (CPU, memory, disk, network, processes)
- `github.com/fatih/color` - Terminal colors
- `github.com/mark3labs/mcp-go` - MCP server implementation

## MCP Server

The tool can run as an MCP (Model Context Protocol) server for integration with Claude Code.

### Running as MCP Server

```bash
./ubuntu-state --mcp
```

### MCP Architecture

The MCP server is implemented in `mcpserver/server.go`:
- Uses stdio transport (stdin/stdout for JSON-RPC)
- Registers 12 tools that expose all collectors
- Returns JSON responses for all tools

### Available Tools

| Tool | Function Called | Parameters |
|------|-----------------|------------|
| `get_system_report` | `collectors.CollectAll()` | none |
| `get_issues` | `collectors.CollectAll()` + filter | `severity` (optional) |
| `get_system_info` | `collectors.CollectSystemInfo()` | none |
| `get_disk_info` | `collectors.CollectDiskInfo()` | `mount_point` (optional) |
| `get_network_info` | `collectors.CollectNetworkInfo()` | none |
| `get_package_info` | `collectors.CollectPackageInfo()` | none |
| `get_service_info` | `collectors.CollectServiceInfo()` | none |
| `get_security_info` | `collectors.CollectSecurityInfo()` | none |
| `get_hardware_info` | `collectors.CollectHardwareInfo()` | none |
| `list_reports` | `history.List()` | `limit` (optional) |
| `get_report` | `history.Load()` | `id` (required) |
| `compare_reports` | `history.Compare()` | `old_id`, `new_id` (required) |

### Adding New MCP Tools

1. Create a new `register*` function in `mcpserver/server.go`
2. Define the tool with `mcp.NewTool()` including description and parameters
3. Add handler function that calls the appropriate collector
4. Return JSON via `mcp.NewToolResultText(jsonString)`
5. Register in `registerTools()` function

### Testing MCP Server

```bash
# Test tools list
echo '{"jsonrpc":"2.0","method":"tools/list","id":1}' | ./ubuntu-state --mcp

# Test calling a tool
echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_issues"},"id":2}' | ./ubuntu-state --mcp
```

## Common Tasks

### Modify issue detection thresholds

Edit `collectors/collector.go` in the `analyzeIssues()` function. Thresholds are hardcoded (e.g., 80% disk = warning, 90% = critical).

### Change HTML styling

Edit the `htmlTemplate` constant in `outputs/html.go`. It's a complete standalone HTML document with embedded CSS.

### Add new CLI flags

Add flags in `main.go` using the `flag` package, then handle them in the main function.

## Testing Notes

- The tool requires Linux (`/sys/`, `/proc/`, systemctl, apt commands)
- Some collectors gracefully fail on non-Ubuntu systems
- Battery info only available on laptops with `/sys/class/power_supply/BAT*`
- Firewall check requires `ufw` to be installed
