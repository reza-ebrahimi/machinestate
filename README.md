# MachineState

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Go](https://img.shields.io/badge/Go-1.21+-00ADD8?logo=go)](https://go.dev/)
[![Zig](https://img.shields.io/badge/Zig-0.14+-F7A41D?logo=zig)](https://ziglang.org/)

A single-binary Linux system state reporter with real-time JSONL streaming and a native MCP server for direct LLM integration. Built in Go and Zig from identical Markdown specs using Claude Opus.


**Available in two implementations:**

- **Go** - Using gopsutil library
- **Zig** - Native implementation with minimal dependencies

Both produce identical JSON output and can be used interchangeably.

## Features

- **Comprehensive System Analysis**

  - CPU, memory, load average, uptime, timezone
  - Disk usage and inode status
  - Network interfaces and listening ports
  - Package updates (APT, Snap)
  - Systemd service status
  - Security checks (firewall, SSH, failed logins)
  - Hardware health (battery, temperatures, crash reports)
  - Docker containers and images
  - GPU monitoring (NVIDIA, AMD, Intel)
  - Log analysis (errors, OOM events, kernel panics)

- **Multiple Output Formats**

  - Terminal (colored ANSI)
  - HTML (dark theme, standalone)
  - JSON (for scripting/monitoring)
  - Markdown

- **Continuous Streaming**

  - Stream data per collector as JSONL
  - Configurable intervals
  - Stop conditions: cycle count or duration
  - Collector filtering

- **Issue Detection**

  - Automatic problem detection with severity levels
  - Actionable fix recommendations

- **MCP Server Integration**

  - Run as Model Context Protocol (MCP) server
  - Integrate with Claude Code
  - 14 tools for querying system state

- **HTTP Server Mode**
  - REST API endpoints
  - Prometheus metrics
  - Web dashboard

## Quick Start

### Download

```bash
# Download the latest release (Go version)
curl -LO https://github.com/reza-ebrahimi/machinestate/releases/latest/download/machinestate-go-linux-amd64
chmod +x machinestate-go-linux-amd64
sudo mv machinestate-go-linux-amd64 /usr/local/bin/machinestate
```

### Build from Source

**Go:**

```bash
cd go/
go build -o machinestate .
sudo cp machinestate /usr/local/bin/
```

**Zig:**

```bash
cd zig/
zig build -Doptimize=ReleaseFast
sudo cp zig-out/bin/machinestate /usr/local/bin/
```

### Docker

```bash
# Build and run Go version
docker build -f Dockerfile.go -t machinestate:go .
docker run -d -p 8080:8080 -v /proc:/host/proc:ro -v /sys:/host/sys:ro machinestate:go

# Or use docker-compose (runs both on ports 8080 and 8081)
docker-compose up -d
```

## Usage

```bash
# Generate terminal report (default)
machinestate

# Generate HTML report
machinestate --format html > report.html

# Generate JSON output
machinestate --format json | jq '.issues'

# Stream JSONL output
machinestate --stream

# Run HTTP server
machinestate --http 8080

# Run as MCP server (for Claude Code)
machinestate --mcp
```

### Options

| Flag           | Description                                                  |
| -------------- | ------------------------------------------------------------ |
| `--format`     | Output format: `terminal`, `html`, `json`, `markdown`, `all` |
| `--output`     | Output file path                                             |
| `--stream`     | Enable continuous streaming mode (JSONL)                     |
| `--interval`   | Streaming interval in seconds (default: 5)                   |
| `--duration`   | Max streaming duration in seconds                            |
| `--count`      | Number of streaming cycles                                   |
| `--collectors` | Comma-separated collectors to stream                         |
| `--config`     | Path to YAML config file                                     |
| `--http`       | Run HTTP server on port                                      |
| `--mcp`        | Run as MCP server                                            |
| `--version`    | Show version                                                 |

### HTTP Server

```bash
machinestate --http 8080
```

| Endpoint       | Description                      |
| -------------- | -------------------------------- |
| `/`            | Web dashboard (auto-refresh 30s) |
| `/health`      | Health check                     |
| `/api/report`  | Full system report JSON          |
| `/api/issues`  | Detected issues                  |
| `/api/system`  | CPU, memory, load                |
| `/api/disk`    | Filesystem usage                 |
| `/api/network` | Interfaces, ports                |
| `/metrics`     | Prometheus format                |

### MCP Server (Claude Code)

```bash
# Add to Claude Code
claude mcp add-json machinestate '{"type":"stdio","command":"/path/to/machinestate","args":["--mcp"]}'
```

**Available tools:** `get_system_report`, `get_issues`, `get_system_info`, `get_disk_info`, `get_network_info`, `get_package_info`, `get_service_info`, `get_security_info`, `get_hardware_info`, `get_docker_info`, `get_snap_info`, `get_gpu_info`, `get_log_info`, `stream_system_report`

## Configuration

Create `~/.config/machinestate/config.yaml`:

```yaml
disk_warning_percent: 80
disk_critical_percent: 90
memory_warning_percent: 90
battery_health_warning: 80
battery_health_critical: 50
uptime_warning_days: 30
gpu_temp_warning: 80
gpu_temp_critical: 90
```

## System Requirements

- **OS:** Linux (any distribution with systemd)
- **Tested on:** Ubuntu, Debian, Fedora, Arch Linux
- **Optional tools:** apt, snap, docker, nvidia-smi, journalctl

The tool gracefully degrades when optional tools are unavailable.

## Performance

| Metric           | Go     | Zig     |
| ---------------- | ------ | ------- |
| **Binary Size**  | 11 MiB | 4.6 MiB |
| **Startup Time** | 4.0 ms | 0.79 ms |
| **Full Report**  | ~4.2 s | ~3.1 s  |

Most execution time is spent on CPU sampling and external commands.

## Development

```bash
make all          # Build both implementations
make test         # Run tests
make validate     # Validate JSON output against schema
make benchmark    # Run performance benchmarks
make docker-build # Build Docker images
```

## License

[MIT License](LICENSE) - Copyright (c) 2026 Reza Ebrahimi
