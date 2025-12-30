# ubuntu-state

A fast, single-binary system state reporter for Ubuntu/Linux. Generates comprehensive health reports in multiple formats with history tracking for comparison over time.

## Features

- **Comprehensive System Analysis**
  - CPU, memory, load average, uptime, timezone
  - Disk usage and inode status
  - Network interfaces and listening ports
  - Package updates (APT and Snap)
  - Systemd service status
  - Security checks (firewall, SSH, failed logins)
  - Hardware health (battery, temperatures, crash reports)
  - Docker containers and images
  - GPU monitoring (NVIDIA, AMD, Intel)
  - Log analysis (errors, OOM events, kernel panics)

- **Multiple Output Formats**
  - Terminal (colored)
  - HTML (dark theme, standalone)
  - JSON (for scripting/monitoring)
  - Markdown

- **Issue Detection**
  - Automatic problem detection with severity levels (critical, warning, info)
  - Actionable fix recommendations

- **History & Comparison**
  - Saves reports automatically
  - Compare current state with previous reports
  - Track changes over time

- **MCP Server Integration**
  - Run as Model Context Protocol (MCP) server
  - Integrate with Claude Code and other MCP clients
  - 16 tools for querying system state programmatically

- **Configurable Thresholds**
  - YAML config file support
  - Customize warning/critical thresholds
  - Set via `--config` flag

## Installation

### From Source

```bash
# Clone or download the project
cd ubuntu-state

# Build
go build -o ubuntu-state .

# Install globally (optional)
sudo cp ubuntu-state /usr/local/bin/
```

### Requirements

- Go 1.21+ (for building)
- Linux (tested on Ubuntu 22.04, 24.04)

## Usage

### Basic Usage

```bash
# Generate terminal report (default)
ubuntu-state

# Generate HTML report
ubuntu-state --format html

# Generate JSON output
ubuntu-state --format json

# Generate Markdown output
ubuntu-state --format markdown

# Generate all formats at once
ubuntu-state --format all --output ./reports/
```

### Options

| Flag | Description |
|------|-------------|
| `--format` | Output format: `terminal`, `html`, `json`, `markdown`, `all` (default: terminal) |
| `--output` | Output file path (default: stdout or auto-named for html/all) |
| `--compare` | Compare with the last saved report |
| `--no-save` | Don't save this report to history |
| `--quiet` | Suppress terminal output when using `--format all` |
| `--json-compact` | Output minified JSON (single line) |
| `--config` | Path to YAML config file (default: ~/.config/ubuntu-state/config.yaml) |
| `--mcp` | Run as MCP server (stdio transport for Claude Code) |
| `--version` | Show version |

### History Commands

```bash
# List all saved reports
ubuntu-state history list

# Show a specific saved report
ubuntu-state history show 2024-12-30T10-30-00

# Compare a saved report with current state
ubuntu-state history compare 2024-12-30T10-30-00
```

## Output Examples

### Terminal Output

```
═══════════════════════════════════════════════════════════════
                    UBUNTU SYSTEM STATE REPORT
═══════════════════════════════════════════════════════════════

  Hostname: myserver
  OS:       Ubuntu 24.04.3 LTS
  Kernel:   6.8.0-90-generic
  Uptime:   5d 12h 30m

  ✗ 1 critical issue(s)
  ⚠ 3 warning(s)

┌─ SYSTEM
  Load Average:        0.45 / 0.52 / 0.48 (1/5/15 min)
  CPU Cores:           8
  Memory:              4.6 GB / 15.5 GB (29.9%)
  ...
```

### HTML Report

The HTML report features a dark theme with:
- Color-coded status indicators
- Progress bars for disk/memory usage
- Collapsible sections
- Mobile-responsive design

## Data Collected

| Category | Metrics |
|----------|---------|
| **System** | Hostname, OS, kernel, uptime, timezone, reboot required, load average, CPU cores/usage |
| **Memory** | Total, used, free, percentage, swap usage |
| **Disk** | Mount points, size, used, free, percentage, inodes |
| **Network** | Interfaces (state, IPs, traffic), listening ports, connectivity |
| **Packages** | APT updates, security updates, broken/held packages |
| **Snaps** | Installed snaps, disk usage, pending refreshes |
| **Services** | Failed systemd units, zombie processes, top CPU/memory processes |
| **Security** | Firewall status, SSH status, failed logins (24h), open ports |
| **Hardware** | Battery (capacity, health, cycles), temperatures, crash reports |
| **Docker** | Running/stopped containers, images, disk usage, dangling images |
| **GPU** | NVIDIA/AMD/Intel GPUs: temperature, utilization, memory, power |
| **Logs** | Error counts (24h), OOM events, kernel panics, segfaults, top errors |

## History Storage

Reports are saved to `~/.local/share/ubuntu-state/history/` as JSON files. The last 100 reports are kept automatically.

## MCP Server (Claude Code Integration)

ubuntu-state can run as an MCP (Model Context Protocol) server, allowing Claude Code and other MCP clients to query system information.

### Setup

```bash
# Add to Claude Code (user scope)
claude mcp add-json ubuntu-state '{"type":"stdio","command":"/path/to/ubuntu-state","args":["--mcp"]}'

# Or add to project scope (.mcp.json in project root)
{
  "mcpServers": {
    "ubuntu-state": {
      "type": "stdio",
      "command": "/path/to/ubuntu-state",
      "args": ["--mcp"]
    }
  }
}
```

### Available MCP Tools

| Tool | Description |
|------|-------------|
| `get_system_report` | Complete system state snapshot |
| `get_issues` | Detected issues with optional severity filter |
| `get_system_info` | CPU, memory, load, uptime, timezone |
| `get_disk_info` | Filesystem usage (optional mount point filter) |
| `get_network_info` | Interfaces, ports, connectivity |
| `get_package_info` | APT updates status |
| `get_service_info` | Systemd services, processes |
| `get_security_info` | Firewall, SSH, failed logins |
| `get_hardware_info` | Battery, temps, crash reports |
| `get_docker_info` | Docker containers, images, disk usage |
| `get_snap_info` | Snap packages, disk usage, pending refreshes |
| `get_gpu_info` | GPU temperature, utilization, memory |
| `get_log_info` | Log analysis (errors, OOM, panics) |
| `list_reports` | List saved report IDs |
| `get_report` | Load a saved report by ID |
| `compare_reports` | Compare two reports |

### Usage in Claude Code

After configuring, you can ask Claude Code:
- "Get my system report"
- "What issues does my system have?"
- "Show me disk usage for /home"
- "Compare with last report"

## Scheduled Reports

### Using Cron

```bash
# Weekly report every Sunday at 3am
0 3 * * 0 /usr/local/bin/ubuntu-state --format html --output /var/reports/weekly-$(date +\%Y\%m\%d).html
```

### Using Systemd Timer

Create `/etc/systemd/system/ubuntu-state.service`:
```ini
[Unit]
Description=Ubuntu State Report

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ubuntu-state --format all --output /var/reports/ --quiet
```

Create `/etc/systemd/system/ubuntu-state.timer`:
```ini
[Unit]
Description=Weekly Ubuntu State Report

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
```

Enable:
```bash
sudo systemctl enable --now ubuntu-state.timer
```

## Project Structure

```
ubuntu-state/
├── main.go              # CLI entry point
├── config/
│   └── config.go        # Configuration loading (YAML)
├── collectors/          # Data collection modules
│   ├── collector.go     # Main collector + issue analysis
│   ├── system.go        # CPU, memory, load, timezone
│   ├── disk.go          # Filesystem info
│   ├── network.go       # Network interfaces, ports
│   ├── packages.go      # APT package status
│   ├── services.go      # Systemd services, processes
│   ├── security.go      # Firewall, SSH, logins
│   ├── hardware.go      # Battery, temps, crashes
│   ├── docker.go        # Docker containers, images
│   ├── snaps.go         # Snap packages
│   ├── gpu.go           # GPU monitoring
│   └── logs.go          # Log analysis
├── models/
│   └── report.go        # Data structures
├── outputs/
│   ├── terminal.go      # Colored terminal output
│   ├── html.go          # HTML report
│   ├── json.go          # JSON output
│   └── markdown.go      # Markdown output
├── history/
│   └── history.go       # Save/load/compare reports
└── mcpserver/
    └── server.go        # MCP server with 16 tools
```

## License

MIT License
