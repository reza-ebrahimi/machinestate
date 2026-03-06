# 7. Configuration

[← Issue Detection](06-issue-detection.md) | [Index](00-index.md) | [Next: Output Formats →](08-output-formats.md)

---

## 7.1 Config File Location

**Default:** `~/.config/machinestate/config.yaml`

**Override:** `--config /path/to/config.yaml`

## 7.2 Config Schema (YAML)

```yaml
# All values are integers (percentages or counts)
disk_warning_percent: 80
disk_critical_percent: 90
memory_warning_percent: 90
battery_health_warning: 80
battery_health_critical: 50
uptime_warning_days: 30
gpu_temp_warning: 80
gpu_temp_critical: 90
```

## 7.3 Loading Behavior

1. If `--config` flag provided, load from that path
2. Else, try default path `~/.config/machinestate/config.yaml`
3. If file doesn't exist or parsing fails, use defaults
4. Missing keys use default values (partial configs supported)

---

[← Issue Detection](06-issue-detection.md) | [Index](00-index.md) | [Next: Output Formats →](08-output-formats.md)
