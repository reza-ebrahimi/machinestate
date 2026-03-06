# 3. Command-Line Interface

[← Requirements](02-requirements.md) | [Index](00-index.md) | [Next: Data Model →](04-data-model.md)

---

## 3.1 Usage

```
machinestate [options]
machinestate --mcp
```

## 3.2 Flags

| Flag             | Type   | Default    | Description                                                              |
| ---------------- | ------ | ---------- | ------------------------------------------------------------------------ |
| `--format`       | string | `terminal` | Output format: `terminal`, `html`, `json`, `markdown`, `all`             |
| `--output`       | string | `""`       | Output file path (stdout if empty for all formats)                       |
| `--stream`       | bool   | `false`    | Enable continuous streaming mode (JSONL output)                          |
| `--interval`     | int    | `5`        | Interval between streaming cycles in seconds                             |
| `--duration`     | int    | `0`        | Maximum streaming duration in seconds (0 = infinite)                     |
| `--count`        | int    | `0`        | Number of streaming cycles (0 = infinite)                                |
| `--collectors`   | string | `""`       | Comma-separated collectors to stream (empty = all)                       |
| `--quiet`        | bool   | `false`    | Suppress terminal output when using `--format all`                       |
| `--json-compact` | bool   | `false`    | Output minified JSON (single line, no indentation)                       |
| `--config`       | string | `""`       | Path to YAML config file (default: `~/.config/machinestate/config.yaml`) |
| `--http`         | string | `""`       | Run HTTP server on specified port (e.g., 8080)                           |
| `--mcp`          | bool   | `false`    | Run as MCP server using stdio transport                                  |
| `--version`      | bool   | `false`    | Print version and exit                                                   |

## 3.3 Continuous Streaming Mode

When `--stream` is enabled, the program runs continuously, emitting data at configurable intervals until stopped.

### Starting Streaming

```bash
machinestate --stream                                    # Stream all collectors every 5s
machinestate --stream --interval 10                      # Stream every 10 seconds
machinestate --stream --collectors system,disk,network   # Stream specific collectors
machinestate --stream --count 10                         # Stream 10 cycles then stop
machinestate --stream --duration 3600                    # Stream for 1 hour then stop
```

### Stop Methods

1. **Ctrl+C (SIGINT/SIGTERM)** - Graceful shutdown with shutdown marker
2. **`--count N`** - Stop after N cycles
3. **`--duration S`** - Stop after S seconds

### Output Format (JSONL with Cycle Markers)

```json
{"_cycle":1,"_timestamp":"2025-12-30T10:00:00Z"}
{"collector":"os","timestamp":"2025-12-30T10:00:00Z","data":{...}}
{"collector":"system","timestamp":"2025-12-30T10:00:01Z","data":{...}}
{"collector":"disk","timestamp":"2025-12-30T10:00:01Z","data":{...}}
...
{"collector":"issues","timestamp":"2025-12-30T10:00:05Z","data":[...]}
{"_cycle_complete":1}
{"_cycle":2,"_timestamp":"2025-12-30T10:00:10Z"}
{"collector":"os","timestamp":"2025-12-30T10:00:10Z","data":{...}}
...
{"_cycle_complete":2}
{"_shutdown":true,"_total_cycles":2,"_timestamp":"2025-12-30T10:00:15Z"}
```

### Cycle Markers

| Marker                                                    | Description                      |
| --------------------------------------------------------- | -------------------------------- |
| `{"_cycle":N,"_timestamp":"..."}`                         | Start of cycle N                 |
| `{"_cycle_complete":N}`                                   | End of cycle N                   |
| `{"_shutdown":true,"_total_cycles":N,"_timestamp":"..."}` | Graceful shutdown after N cycles |

### Collector Names

`os`, `system`, `disk`, `network`, `packages`, `services`, `security`, `hardware`, `docker`, `snaps`, `gpu`, `logs`, `issues`

### Collector Filtering

When `--collectors` is specified, only those collectors run. The `issues` collector is always included if any filter is set.

```bash
# Stream only system and disk info
machinestate --stream --collectors system,disk
```

## 3.4 Exit Codes

| Code | Meaning                                             |
| ---- | --------------------------------------------------- |
| 0    | Success                                             |
| 1    | Error (invalid args, file write failure, MCP error) |

---

[← Requirements](02-requirements.md) | [Index](00-index.md) | [Next: Data Model →](04-data-model.md)
