# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-12-30

### Added

- Initial public release
- Dual implementation in Go and Zig
- 12 system collectors:
  - OS information (name, version, kernel, architecture)
  - System metrics (CPU, memory, swap, load, uptime)
  - Disk usage (filesystems, inodes)
  - Network (interfaces, ports, connectivity)
  - Packages (APT updates, security updates)
  - Services (systemd units, zombie processes, top processes)
  - Security (firewall, SSH, failed logins)
  - Hardware (battery, temperatures, crash reports)
  - Docker (containers, images, disk usage)
  - Snap packages
  - GPU (NVIDIA, AMD, Intel)
  - Logs (24h analysis, error patterns)
- Automatic issue detection with severity levels (critical, warning, info)
- Multiple output formats:
  - Terminal (colored ANSI)
  - JSON (structured data)
  - HTML (standalone dark-theme report)
  - Markdown (GitHub-flavored)
- Continuous streaming mode (JSONL output)
- HTTP server mode with REST API
- Prometheus metrics endpoint
- MCP (Model Context Protocol) server for Claude Code integration
- 14 MCP tools for granular data access
- YAML configuration for thresholds
- Debian packaging support
- Docker support with docker-compose
- Cross-compilation for amd64/arm64 (GNU and musl)
- JSON Schema validation

### Technical Highlights

- Single binary, no runtime dependencies
- Graceful degradation when tools are unavailable
- Identical JSON output from both implementations
- Sub-second startup time (Zig: ~0.8ms, Go: ~4ms)
- Compact binaries (Zig: ~4.6MB, Go: ~11MB)
