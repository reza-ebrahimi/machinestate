# MachineState Specification

**Version:** 1.2.0
**Last Updated:** December 2025

This specification provides a complete technical reference for building a system state reporter compatible with `machinestate`. Any developer can use this specification to implement the system in any programming language.

## How to Use This Specification

The specification is organized into numbered files for easy navigation:

| File                                           | Description                                       |
| ---------------------------------------------- | ------------------------------------------------- |
| [01-overview.md](01-overview.md)               | Purpose and design principles                     |
| [02-requirements.md](02-requirements.md)       | System requirements and external dependencies     |
| [03-cli.md](03-cli.md)                         | Command-line interface, flags, and streaming mode |
| [04-data-model.md](04-data-model.md)           | All JSON data structures (15 types)               |
| [05-collectors.md](05-collectors.md)           | Collection order and mechanisms                   |
| [06-issue-detection.md](06-issue-detection.md) | Thresholds and detection rules                    |
| [07-configuration.md](07-configuration.md)     | Configuration file format                         |
| [08-output-formats.md](08-output-formats.md)   | Terminal, JSON, HTML, Markdown output             |
| [09-mcp-server.md](09-mcp-server.md)           | MCP protocol and 14 tools                         |
| [10-http-server.md](10-http-server.md)         | REST API and Prometheus metrics                   |
| [11-deployment.md](11-deployment.md)           | Systemd service configuration                     |
| [12-appendices.md](12-appendices.md)           | Helpers and degradation matrix                    |

## Quick Reference

### Key Design Principles

1. **Single Binary** - No runtime dependencies
2. **Read-Only** - Never modifies system state
3. **Graceful Degradation** - Missing tools fail silently
4. **Configurable Thresholds** - User-configurable issue detection
5. **Cross-Platform** - Standard Linux interfaces (/proc, /sys)

### Data Flow

```
machinestate
  ├── config.Init()
  └── collectors.CollectAll()
        ├── OS, System, Disk, Network
        ├── Packages, Services, Security
        ├── Hardware, Docker, Snaps
        ├── GPU, Logs
        └── analyzeIssues()
  └── outputs.Render*()
```

### Output Formats

- **Terminal** - Colored ANSI output with Unicode symbols
- **JSON** - Complete report as JSON (pretty or compact)
- **JSONL** - Streaming mode with per-collector output
- **HTML** - Dark-themed standalone report
- **Markdown** - GitHub-flavored markdown

### Server Modes

- **MCP Server** (`--mcp`) - JSON-RPC over stdio for Claude Code
- **HTTP Server** (`--http PORT`) - REST API with Prometheus metrics

## Implementation Notes

When implementing machinestate:

1. Start with [04-data-model.md](04-data-model.md) to define all structures
2. Implement collectors per [05-collectors.md](05-collectors.md)
3. Add issue detection per [06-issue-detection.md](06-issue-detection.md)
4. Build output formatters per [08-output-formats.md](08-output-formats.md)
5. Add MCP/HTTP servers last

All implementations MUST produce identical JSON output for cross-implementation compatibility.
