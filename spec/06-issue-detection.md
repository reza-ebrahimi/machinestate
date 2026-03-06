# 6. Issue Detection

[← Collectors](05-collectors.md) | [Index](00-index.md) | [Next: Configuration →](07-configuration.md)

---

## 6.1 Configurable Thresholds

| Config Key | Default | Description |
|------------|---------|-------------|
| disk_warning_percent | 80 | Disk usage warning |
| disk_critical_percent | 90 | Disk usage critical |
| memory_warning_percent | 90 | Memory usage warning |
| battery_health_warning | 80 | Battery health warning |
| battery_health_critical | 50 | Battery health critical |
| uptime_warning_days | 30 | Days without reboot |
| gpu_temp_warning | 80 | GPU temperature warning (°C) |
| gpu_temp_critical | 90 | GPU temperature critical (°C) |

## 6.2 Hardcoded Thresholds

| Threshold | Value | Description |
|-----------|-------|-------------|
| Inode warning | 90% | Inode usage |
| Swap warning | 80% | Swap usage |
| Load warning | 1.0 × cores | Load average / CPU cores |
| Load critical | 2.0 × cores | Load average / CPU cores |
| CPU temp warning | 85°C | CPU temperature |
| Docker dangling | 1 GB | Dangling images size |
| Updates warning | 50 | Pending package updates |

## 6.3 Detection Rules

| Category | Severity | Condition |
|----------|----------|-----------|
| Disk | critical | used_percent >= disk_critical_percent |
| Disk | warning | used_percent >= disk_warning_percent |
| Disk | warning | inodes_percent >= 90 |
| Memory | warning | memory_percent >= memory_warning_percent |
| Memory | warning | swap_percent >= 80 |
| CPU | critical | load_avg_1 / cpu_cores >= 2.0 |
| CPU | warning | load_avg_1 / cpu_cores >= 1.0 |
| Services | warning | failed_units.length > 0 |
| Processes | info | zombie_count > 0 |
| Packages | warning | updates_available > 50 |
| Packages | info | updates_available > 0 |
| Security | warning | security_updates > 0 |
| Security | warning | firewall_active == false |
| Hardware | critical | battery.health < battery_health_critical |
| Hardware | warning | battery.health < battery_health_warning |
| Hardware | critical | temperature >= critical_threshold |
| Hardware | warning | temperature >= high_threshold |
| Hardware | warning | temperature >= 85 (fallback) |
| Hardware | warning | crash_reports.length > 0 |
| Network | warning | connectivity == false |
| System | warning | reboot_required == true |
| System | warning | uptime_days > uptime_warning_days |
| Docker | warning | dangling_images_size > 1GB |
| GPU | critical | temperature >= gpu_temp_critical |
| GPU | warning | temperature >= gpu_temp_warning |
| Logs | warning | oom_events > 0 |
| Logs | critical | kernel_panics > 0 |

---

[← Collectors](05-collectors.md) | [Index](00-index.md) | [Next: Configuration →](07-configuration.md)
