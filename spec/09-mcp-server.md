# 9. MCP Server Protocol

[← Output Formats](08-output-formats.md) | [Index](00-index.md) | [Next: HTTP Server →](10-http-server.md)

---

## 9.1 Transport

**Type:** stdio (JSON-RPC 2.0 over stdin/stdout)

**Encoding:** UTF-8

**Framing:** Newline-delimited JSON

## 9.2 Initialization

Server announces capabilities via `initialize` response:

- Server name: "machinestate"
- Version: "1.0.0"
- Capabilities: tools (no subscriptions)

## 9.3 Available Tools (14)

### Primary Tools

| Tool | Description | Parameters |
|------|-------------|------------|
| `get_system_report` | Complete system snapshot | None |
| `get_issues` | Detected issues | `severity` (optional): "critical", "warning", "info" |
| `stream_system_report` | Stream data as JSONL per collector | `collectors` (optional): array of collector names to include |

### Granular Collectors

| Tool | Description | Parameters |
|------|-------------|------------|
| `get_system_info` | CPU, memory, load | None |
| `get_disk_info` | Filesystem usage | `mount_point` (optional): filter to specific mount |
| `get_network_info` | Interfaces, ports | None |
| `get_package_info` | APT status | None |
| `get_service_info` | Systemd, processes | None |
| `get_security_info` | Firewall, SSH | None |
| `get_hardware_info` | Battery, temps | None |
| `get_docker_info` | Containers, images | None |
| `get_snap_info` | Snap packages | None |
| `get_gpu_info` | GPU stats | None |
| `get_log_info` | Log analysis | None |

## 9.4 Response Format

All tools return JSON-RPC result with:

- `content`: Array with single text content item
- `content[0].type`: "text"
- `content[0].text`: JSON string (pretty-printed, 2-space indent)

Error responses use `mcp.NewToolResultError(message)` format.

## 9.5 Example Session

```json
// Request
{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_issues","arguments":{"severity":"critical"}},"id":1}

// Response
{"jsonrpc":"2.0","result":{"content":[{"type":"text","text":"[...]"}]},"id":1}
```

## 9.6 Streaming Tool Response

The `stream_system_report` tool returns JSONL (newline-separated JSON objects):

```json
{"collector":"os","timestamp":"...","data":{...}}
{"collector":"system","timestamp":"...","data":{...}}
...
{"_complete":true}
```

---

[← Output Formats](08-output-formats.md) | [Index](00-index.md) | [Next: HTTP Server →](10-http-server.md)
