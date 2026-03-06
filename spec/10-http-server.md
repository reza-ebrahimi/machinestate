# 10. HTTP Server Mode

[← MCP Server](09-mcp-server.md) | [Index](00-index.md) | [Next: Deployment →](11-deployment.md)

---

## 10.1 Overview

When `--http <port>` is specified, the program runs as an HTTP server providing REST API access to all system data.

```bash
machinestate --http 8080
```

## 10.2 Server Behavior

- **Address:** Binds to `0.0.0.0:<port>` (all interfaces)
- **Protocol:** HTTP/1.1
- **CORS:** `Access-Control-Allow-Origin: *` on all responses
- **Connection:** `Connection: close` (no keep-alive)
- **Graceful Shutdown:** Responds to SIGINT/SIGTERM

## 10.3 Endpoints

| Endpoint | Method | Description | Response Type |
|----------|--------|-------------|---------------|
| `/` | GET | Web dashboard (HTML, auto-refresh 30s) | text/html |
| `/health` | GET | Health check | `{"status":"ok"}` |
| `/api/report` | GET | Full system report | Report JSON |
| `/api/issues` | GET | Detected issues | Issue[] JSON |
| `/api/system` | GET | CPU, memory, load | SystemInfo JSON |
| `/api/disk` | GET | Filesystem usage | DiskInfo JSON |
| `/api/network` | GET | Interfaces, ports | NetworkInfo JSON |
| `/api/packages` | GET | APT status | PackageInfo JSON |
| `/api/services` | GET | Systemd, processes | ServiceInfo JSON |
| `/api/security` | GET | Firewall, SSH | SecurityInfo JSON |
| `/api/hardware` | GET | Battery, temps | HardwareInfo JSON |
| `/api/docker` | GET | Containers, images | DockerInfo JSON |
| `/api/snaps` | GET | Snap packages | SnapInfo JSON |
| `/api/gpu` | GET | GPU stats | GPUInfo JSON |
| `/api/logs` | GET | Log analysis | LogInfo JSON |
| `/api/config` | GET | Current thresholds | Config JSON |
| `/metrics` | GET | Prometheus metrics | text/plain |

## 10.4 Response Formats

**JSON Endpoints (`/api/*`, `/health`):**
- Content-Type: `application/json`
- Pretty-printed with 2-space indentation

**Prometheus Metrics (`/metrics`):**
- Content-Type: `text/plain; version=0.0.4; charset=utf-8`
- Standard Prometheus exposition format

## 10.5 Prometheus Metrics

```
# HELP machinestate_cpu_usage_percent CPU usage percentage
# TYPE machinestate_cpu_usage_percent gauge
machinestate_cpu_usage_percent 12.5

# HELP machinestate_memory_used_percent Memory usage percentage
# TYPE machinestate_memory_used_percent gauge
machinestate_memory_used_percent 45.2

# HELP machinestate_memory_total_bytes Total memory in bytes
# TYPE machinestate_memory_total_bytes gauge
machinestate_memory_total_bytes 16656076800

# HELP machinestate_memory_used_bytes Used memory in bytes
# TYPE machinestate_memory_used_bytes gauge
machinestate_memory_used_bytes 7532634112

# HELP machinestate_load_average_1m Load average (1 minute)
# TYPE machinestate_load_average_1m gauge
machinestate_load_average_1m 0.52

# HELP machinestate_disk_used_percent Disk usage percentage
# TYPE machinestate_disk_used_percent gauge
machinestate_disk_used_percent{mount="/"} 52.6
machinestate_disk_used_percent{mount="/home"} 78.3

# HELP machinestate_issues_total Total issues by severity
# TYPE machinestate_issues_total gauge
machinestate_issues_total{severity="critical"} 0
machinestate_issues_total{severity="warning"} 3
machinestate_issues_total{severity="info"} 2
```

## 10.6 Error Responses

| Status | Response Body | Condition |
|--------|---------------|-----------|
| 404 Not Found | `{"error":"Not Found"}` | Unknown path |
| 405 Method Not Allowed | `{"error":"Method not allowed"}` | Non-GET request |
| 500 Internal Server Error | `{"error":"<message>"}` | Collection failed |

## 10.7 Example Usage

```bash
# Start server
machinestate --http 8080

# In another terminal:
curl http://localhost:8080/health
# {"status":"ok"}

curl http://localhost:8080/api/system | jq .cpu_usage
# 12.5

curl http://localhost:8080/metrics | grep cpu
# machinestate_cpu_usage_percent 12.5

# Full report
curl http://localhost:8080/api/report > report.json
```

---

[← MCP Server](09-mcp-server.md) | [Index](00-index.md) | [Next: Deployment →](11-deployment.md)
