# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with this project.

## Project Overview

`machinestate` is a system health reporter for Ubuntu/Linux systems that generates comprehensive system state reports. It collects system metrics, detects issues, and outputs reports in multiple formats with continuous streaming support.

**Two implementations:**
- `go/` - Go implementation using gopsutil library
- `zig/` - Zig implementation with native system calls

Both implementations follow the specification in `spec/` and produce identical JSON output.

## Build Commands

### Using Makefile (Recommended)

```bash
make all          # Build both Go and Zig implementations
make go           # Build Go only
make zig          # Build Zig release
make debug        # Build Zig debug
make test         # Run unit tests for both
make validate     # Validate JSON output against schema
make validate-mcp # Validate all 14 MCP tools against their schemas
make benchmark    # Run performance benchmarks (requires hyperfine)
make clean        # Remove build artifacts
make install      # Install to /usr/local/bin

# Cross-compilation
make build-amd64       # Build for x86_64 (GNU libc)
make build-arm64       # Build for ARM64 (GNU libc)
make build-amd64-musl  # Build for x86_64 (musl - static)
make build-arm64-musl  # Build for ARM64 (musl - static)
make build-all-arch    # Build all architectures
make release           # Build all and copy to dist/

# Docker
make docker-build-go   # Build Go Docker image
make docker-build-zig  # Build Zig Docker image
make docker-build      # Build both images
make docker-run-go     # Run Go container (port 8080)
make docker-run-zig    # Run Zig container (port 8081)
make docker-compose-up # Run both via docker-compose
```

### Direct Commands

**Go:**
```bash
cd go/
go build -o machinestate .
go test ./...
```

**Zig:**
```bash
cd zig/
zig build                        # Debug build
zig build -Doptimize=ReleaseFast # Release build
zig build test                   # Run tests
```

## Architecture

### Directory Structure

```
machinestate/
├── spec/                # Technical specification (source of truth)
│   ├── 00-index.md      # Index with navigation
│   ├── 01-overview.md   # Purpose and design principles
│   ├── 02-requirements.md # System requirements
│   ├── 03-cli.md        # Command-line interface
│   ├── 04-data-model.md # All JSON data structures
│   ├── 05-collectors.md # Collection mechanisms
│   ├── 06-issue-detection.md # Detection rules
│   ├── 07-configuration.md # Config file format
│   ├── 08-output-formats.md # Output rendering
│   ├── 09-mcp-server.md # MCP protocol
│   ├── 10-http-server.md # REST API
│   ├── 11-deployment.md # Systemd service
│   └── 12-appendices.md # Helpers and matrices
├── CLAUDE.md            # This file - development guidance
├── Makefile             # Build automation for both implementations
├── Dockerfile.go        # Docker image for Go implementation
├── Dockerfile.zig       # Docker image for Zig implementation
├── docker-compose.yml   # Run both implementations
├── .dockerignore        # Docker build exclusions
├── schema/
│   ├── report.schema.json  # JSON Schema for full report validation
│   └── mcp/                # Individual schemas for MCP tool outputs
├── go/                  # Go implementation
│   ├── main.go          # CLI entry point
│   ├── config/          # Configuration loading (YAML)
│   ├── collectors/      # Data collection modules
│   ├── models/          # Data structures
│   ├── outputs/         # Output formatters
│   ├── mcpserver/       # MCP server
│   └── httpserver/      # HTTP server with REST API
├── zig/                 # Zig implementation
│   ├── build.zig        # Build configuration
│   └── src/
│       ├── main.zig     # CLI entry point
│       ├── utils.zig    # Utility functions
│       ├── collectors/  # Data collection modules
│       ├── models/      # Data structures
│       ├── outputs/     # Output formatters
│       ├── mcp/         # MCP server
│       └── http/        # HTTP server with REST API
└── debian/              # Debian packaging
    ├── control          # Package definitions
    ├── rules            # Build script
    ├── changelog        # Version history
    ├── copyright        # License
    └── machinestate.1   # Man page
```

### Key Design Decisions

1. **Single binary** - No external dependencies at runtime
2. **Graceful degradation** - Missing tools/features fail silently with empty data
3. **Identical JSON output** - Both implementations produce byte-identical JSON
4. **spec/ is source of truth** - All implementations follow this specification

### Data Flow

```
main
  └── config.Init()               # Load config from YAML
  └── collectors.CollectAll()
        ├── CollectOSInfo()
        ├── CollectSystemInfo()    # CPU, memory, load, timezone
        ├── CollectDiskInfo()      # Filesystems
        ├── CollectNetworkInfo()   # Interfaces, ports
        ├── CollectPackageInfo()   # APT status
        ├── CollectServiceInfo()   # Systemd, processes
        ├── CollectSecurityInfo()  # Firewall, SSH
        ├── CollectHardwareInfo()  # Battery, temps
        ├── CollectDockerInfo()    # Docker containers, images
        ├── CollectSnapInfo()      # Snap packages
        ├── CollectGPUInfo()       # GPU temp, memory, utilization
        ├── CollectLogInfo()       # Log analysis (24h)
        └── analyzeIssues()        # Generate issue list
  └── outputs.Render*(report)      # Format output
```

## Adding New Collectors

1. Create collector file in `collectors/` directory
2. Add corresponding fields to models/report
3. Call collector from CollectAll()
4. Add issue detection in analyzeIssues() if needed
5. Update output formatters
6. **Update spec/** with new data model and collection details

## MCP Server

Both implementations can run as MCP servers for Claude Code integration.

### Running as MCP Server

```bash
./machinestate --mcp
```

### Testing MCP Server

```bash
# Test tools list
echo '{"jsonrpc":"2.0","method":"tools/list","id":1}' | ./machinestate --mcp

# Test calling a tool
echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_issues"},"id":2}' | ./machinestate --mcp
```

### Available Tools (14)

| Tool | Description |
|------|-------------|
| `get_system_report` | Complete system snapshot |
| `get_issues` | Detected issues (optional severity filter) |
| `stream_system_report` | Stream data as JSONL per collector |
| `get_system_info` | CPU, memory, load |
| `get_disk_info` | Filesystem usage (optional mount_point filter) |
| `get_network_info` | Interfaces, ports |
| `get_package_info` | APT status |
| `get_service_info` | Systemd, processes |
| `get_security_info` | Firewall, SSH |
| `get_hardware_info` | Battery, temps |
| `get_docker_info` | Containers, images |
| `get_snap_info` | Snap packages |
| `get_gpu_info` | GPU stats |
| `get_log_info` | Log analysis |

## HTTP Server

Both implementations can run as HTTP servers providing REST API access.

### Running HTTP Server

```bash
./machinestate --http 8080
```

### Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | Web dashboard (HTML, auto-refresh 30s) |
| `/health` | GET | Health check (`{"status":"ok"}`) |
| `/api/report` | GET | Full system report JSON |
| `/api/issues` | GET | Detected issues |
| `/api/system` | GET | CPU, memory, load |
| `/api/disk` | GET | Filesystem usage |
| `/api/network` | GET | Interfaces, ports |
| `/api/packages` | GET | APT status |
| `/api/services` | GET | Systemd, processes |
| `/api/security` | GET | Firewall, SSH |
| `/api/hardware` | GET | Battery, temps |
| `/api/docker` | GET | Containers, images |
| `/api/snaps` | GET | Snap packages |
| `/api/gpu` | GET | GPU stats |
| `/api/logs` | GET | Log analysis |
| `/api/config` | GET | Current thresholds |
| `/metrics` | GET | Prometheus format metrics |

### Testing HTTP Server

```bash
# Start server
./machinestate --http 8080

# Test endpoints
curl http://localhost:8080/health
curl http://localhost:8080/api/report | jq .
curl http://localhost:8080/metrics
```

## Configuration

Thresholds configurable via `~/.config/machinestate/config.yaml`:

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

## CLI Flags

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--format` | string | `terminal` | Output: `terminal`, `html`, `json`, `markdown`, `all` |
| `--output` | string | `""` | Output file path (stdout if empty) |
| `--stream` | bool | `false` | Enable continuous streaming mode |
| `--interval` | int | `5` | Interval between cycles (seconds) |
| `--duration` | int | `0` | Max streaming duration (seconds, 0 = infinite) |
| `--count` | int | `0` | Number of streaming cycles (0 = infinite) |
| `--collectors` | string | `""` | Comma-separated collectors to stream |
| `--quiet` | bool | `false` | Suppress terminal output for `--format all` |
| `--json-compact` | bool | `false` | Minified JSON output |
| `--config` | string | `""` | YAML config file path |
| `--http` | string | `""` | Run HTTP server on port (e.g., 8080) |
| `--mcp` | bool | `false` | Run as MCP server |
| `--version` | bool | `false` | Show version |

### Streaming Examples

```bash
machinestate --stream                                    # Stream every 5s
machinestate --stream --interval 10                      # Stream every 10s
machinestate --stream --collectors system,disk           # Filter collectors
machinestate --stream --count 10                         # 10 cycles then stop
machinestate --stream --duration 3600                    # Run for 1 hour
```

## Testing Notes

- Requires Linux (`/sys/`, `/proc/`, systemctl, apt commands)
- Some collectors gracefully fail on non-Ubuntu systems
- Battery info only available on laptops with `/sys/class/power_supply/BAT*`
- Docker collector requires `docker` CLI
- Snap collector requires `snap` CLI
- GPU collector requires `nvidia-smi` (NVIDIA) or `rocm-smi` (AMD), falls back to `lspci`
- Log collector requires `journalctl`

## Schema Validation

Both implementations must produce JSON output conforming to `schema/report.schema.json`.

```bash
# Validate full report JSON output (requires uv)
make validate

# Validate all 14 MCP tools against their schemas
make validate-mcp

# Manual validation
./go/machinestate --format json | uvx check-jsonschema --schemafile schema/report.schema.json -
./zig/zig-out/bin/machinestate --format json | uvx check-jsonschema --schemafile schema/report.schema.json -
```

The schema validates:
- All required fields are present
- Field types are correct (string, integer, number, boolean, array, object)
- Enum values (severity: critical/warning/info, protocol: TCP/UDP)
- Value constraints (percentages 0-100, counts >= 0)
- Nullable fields (docker, snaps, gpu, logs can be null)

When adding new fields:
1. Update the data model in both implementations
2. Update `schema/report.schema.json`
3. Update `spec/04-data-model.md` and `spec/05-collectors.md`
4. Run `make validate` to verify

## Zig-Specific Notes

- Uses popen() for command execution (simpler than fork/exec)
- Uses ArenaAllocator for memory management
- Links libc for popen, access, and other C functions
- JSON serialization uses std.json with custom options for snake_case field names
- Signal handling uses self-pipe pattern for graceful Ctrl+C shutdown during streaming
- HTTP server uses raw POSIX sockets (std.posix) for Zig 0.16 compatibility

## Debian Packaging

Both implementations can be packaged as .deb files:

```bash
# Build packages (requires debhelper, golang-go)
cd machinestate
dpkg-buildpackage -us -uc -b

# Install Go version
sudo dpkg -i ../machinestate-go_1.0.0_amd64.deb

# Or install Zig version
sudo dpkg -i ../machinestate-zig_1.0.0_amd64.deb

# Man page available after install
man machinestate
```

## Systemd Service

After installing the Debian package, a systemd service is available:

```bash
# Enable and start the service
sudo systemctl enable machinestate
sudo systemctl start machinestate

# Check status
sudo systemctl status machinestate

# View logs
journalctl -u machinestate -f
```

### Configuration

The service reads configuration from `/etc/default/machinestate`:

```bash
# Port for HTTP server (default: 8080)
MACHINESTATE_PORT=8080
```

After changing the port, restart the service:
```bash
sudo systemctl restart machinestate
```

## Docker

Both implementations are available as Docker images.

### Building Images

```bash
# Build Go image
docker build -f Dockerfile.go -t machinestate:go .

# Build Zig image
docker build -f Dockerfile.zig -t machinestate:zig .

# Or use Makefile
make docker-build-go   # Build Go image
make docker-build-zig  # Build Zig image
make docker-build      # Build both
```

### Running Containers

```bash
# Run Go version on port 8080
docker run -d --name machinestate-go \
  -p 8080:8080 \
  -v /proc:/host/proc:ro \
  -v /sys:/host/sys:ro \
  machinestate:go

# Run Zig version on port 8081
docker run -d --name machinestate-zig \
  -p 8081:8080 \
  -v /proc:/host/proc:ro \
  -v /sys:/host/sys:ro \
  machinestate:zig

# Or use Makefile
make docker-run-go     # Run Go on port 8080
make docker-run-zig    # Run Zig on port 8081
```

### Docker Compose

Run both implementations simultaneously:

```bash
# Start both services (Go on 8080, Zig on 8081)
docker-compose up -d

# Stop both
docker-compose down

# Or use Makefile
make docker-compose-up
make docker-compose-down
```

### Testing

```bash
# Health check
curl http://localhost:8080/health

# Dashboard
open http://localhost:8080/

# API
curl http://localhost:8080/api/issues | jq .
```

### Notes

- Containers require `/proc` and `/sys` mounted for system metrics
- Runs as root to access system information
- Some collectors (apt, systemctl, docker) may return empty data in container
- Health check endpoint: `/health`
