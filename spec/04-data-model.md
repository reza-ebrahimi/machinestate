# 4. Data Model

[← CLI](03-cli.md) | [Index](00-index.md) | [Next: Collectors →](05-collectors.md)

---

All data structures use JSON serialization with `snake_case` field names.

## 4.1 Root Report Object

```json
{
  "timestamp": "2025-12-30T10:30:00Z",
  "hostname": "string",
  "os": {
    /* OSInfo */
  },
  "system": {
    /* SystemInfo */
  },
  "disk": {
    /* DiskInfo */
  },
  "network": {
    /* NetworkInfo */
  },
  "packages": {
    /* PackageInfo */
  },
  "services": {
    /* ServiceInfo */
  },
  "security": {
    /* SecurityInfo */
  },
  "hardware": {
    /* HardwareInfo */
  },
  "docker": {
    /* DockerInfo */
  },
  "snaps": {
    /* SnapInfo */
  },
  "gpu": {
    /* GPUInfo */
  },
  "logs": {
    /* LogInfo */
  },
  "issues": [
    /* Issue[] */
  ]
}
```

## 4.2 OSInfo

```json
{
  "name": "Ubuntu 24.04.3 LTS",
  "version": "24.04.3 LTS (Noble Numbat)",
  "kernel": "6.8.0-90-generic",
  "architecture": "amd64"
}
```

| Field        | Type   | Source                              |
| ------------ | ------ | ----------------------------------- |
| name         | string | `/etc/os-release` PRETTY_NAME       |
| version      | string | `/etc/os-release` VERSION           |
| kernel       | string | `uname -r` or equivalent            |
| architecture | string | Runtime architecture (amd64, arm64) |

## 4.3 SystemInfo

```json
{
  "uptime": 123456000000000,
  "uptime_human": "1d 10h 17m",
  "timezone": "Europe/Berlin",
  "reboot_required": false,
  "load_avg_1": 0.52,
  "load_avg_5": 0.48,
  "load_avg_15": 0.45,
  "cpu_cores": 8,
  "cpu_usage": 12.5,
  "memory_total": 16656076800,
  "memory_used": 6725750784,
  "memory_free": 8416555008,
  "memory_percent": 40.38,
  "swap_total": 7998533632,
  "swap_used": 0,
  "swap_percent": 0.0
}
```

| Field           | Type                | Source                                                        |
| --------------- | ------------------- | ------------------------------------------------------------- |
| uptime          | int64 (nanoseconds) | `/proc/uptime` first field × 10^9                             |
| uptime_human    | string              | Formatted as `Xd Xh Xm`                                       |
| timezone        | string              | `/etc/timezone` or `timedatectl show -p Timezone --value`     |
| reboot_required | bool                | File exists: `/var/run/reboot-required`                       |
| load_avg_1/5/15 | float64             | `/proc/loadavg` first three fields                            |
| cpu_cores       | int                 | Count of `/proc/cpuinfo` processor entries                    |
| cpu_usage       | float64             | Calculated from `/proc/stat` over 1 second                    |
| memory\_\*      | uint64 (bytes)      | `/proc/meminfo` MemTotal, MemTotal-MemAvailable, MemAvailable |
| memory_percent  | float64             | (memory_used / memory_total) × 100                            |
| swap\_\*        | uint64 (bytes)      | `/proc/meminfo` SwapTotal, SwapTotal-SwapFree                 |
| swap_percent    | float64             | (swap_used / swap_total) × 100, or 0 if no swap               |

## 4.4 DiskInfo

```json
{
  "filesystems": [
    {
      "device": "/dev/sda1",
      "mount_point": "/",
      "fs_type": "ext4",
      "total": 107374182400,
      "used": 53687091200,
      "free": 48318382080,
      "used_percent": 52.6,
      "inodes_total": 6553600,
      "inodes_used": 524288,
      "inodes_free": 6029312,
      "inodes_percent": 8.0
    }
  ]
}
```

| Field           | Type           | Source                                        |
| --------------- | -------------- | --------------------------------------------- |
| device          | string         | Mount source device                           |
| mount_point     | string         | Mount target path                             |
| fs_type         | string         | Filesystem type                               |
| total/used/free | uint64 (bytes) | `statvfs()` system call                       |
| used_percent    | float64        | (used / total) × 100                          |
| inodes\_\*      | uint64         | `statvfs()` f_files, f_files-f_ffree, f_ffree |
| inodes_percent  | float64        | (inodes_used / inodes_total) × 100            |

### Filesystem Filtering Rules

Exclude filesystems where `fs_type` is one of:

- `proc`, `sysfs`, `devfs`, `devpts`, `devtmpfs`, `tmpfs`, `securityfs`
- `cgroup`, `cgroup2`, `pstore`, `debugfs`, `hugetlbfs`
- `mqueue`, `fusectl`, `configfs`, `binfmt_misc`, `autofs`
- `efivarfs`, `squashfs`

Exclude mount points matching `/snap/*`.

## 4.5 NetworkInfo

```json
{
  "interfaces": [
    {
      "name": "eth0",
      "state": "UP",
      "mac": "00:11:22:33:44:55",
      "ips": ["192.168.1.100/24", "fe80::1/64"],
      "rx_bytes": 1073741824,
      "tx_bytes": 536870912
    }
  ],
  "listen_ports": [
    {
      "protocol": "TCP",
      "address": "0.0.0.0",
      "port": 22,
      "process": "sshd",
      "pid": 1234
    }
  ],
  "connectivity": true,
  "public_ip": "203.0.113.1"
}
```

| Field             | Type     | Source                                                                                      |
| ----------------- | -------- | ------------------------------------------------------------------------------------------- |
| interfaces        | array    | `/sys/class/net/*/` + `/proc/net/dev`                                                       |
| state             | string   | `UP` or `DOWN` from interface flags                                                         |
| mac               | string   | `/sys/class/net/<name>/address`                                                             |
| ips               | string[] | From `getifaddrs()` or `/proc/net/fib_trie`                                                 |
| rx_bytes/tx_bytes | uint64   | `/proc/net/dev`                                                                             |
| listen_ports      | array    | Parse `/proc/net/tcp`, `/proc/net/tcp6`, `/proc/net/udp`, `/proc/net/udp6` for LISTEN state |
| process           | string   | Read `/proc/<pid>/comm`                                                                     |
| connectivity      | bool     | TCP connect to `8.8.8.8:53` with 3s timeout succeeds                                        |
| public_ip         | string   | Optional, may be empty                                                                      |

### Interface Filtering

- Exclude `lo` (loopback)
- Exclude `veth*` (Docker virtual interfaces)

## 4.6 PackageInfo

```json
{
  "updates_available": 45,
  "updates_list": ["package1", "package2"],
  "security_updates": 3,
  "broken_packages": 0,
  "held_packages": ["linux-image-generic"]
}
```

| Field             | Type     | Source                                                              |
| ----------------- | -------- | ------------------------------------------------------------------- |
| updates_available | int      | Count lines from `apt list --upgradable 2>/dev/null` (minus header) |
| updates_list      | string[] | Package names from above (optional, can be omitted)                 |
| security_updates  | int      | Count lines containing `-security` or `security.ubuntu.com`         |
| broken_packages   | int      | Non-empty output line count from `dpkg --audit`                     |
| held_packages     | string[] | Lines from `apt-mark showhold`                                      |

## 4.7 ServiceInfo

```json
{
  "failed_units": ["nginx.service", "mysql.service"],
  "zombie_count": 2,
  "top_cpu": [
    {
      "pid": 1234,
      "name": "firefox",
      "cpu": 25.5,
      "memory": 8.2,
      "user": "john"
    }
  ],
  "top_memory": [
    /* same structure */
  ]
}
```

| Field        | Type           | Source                                                        |
| ------------ | -------------- | ------------------------------------------------------------- |
| failed_units | string[]       | First column from `systemctl --failed --no-pager --no-legend` |
| zombie_count | int            | Count processes where `/proc/<pid>/stat` field 3 = 'Z'        |
| top_cpu      | ProcessInfo[5] | Top 5 processes sorted by CPU% descending                     |
| top_memory   | ProcessInfo[5] | Top 5 processes sorted by memory% descending                  |

### ProcessInfo Fields

- pid: Process ID
- name: `/proc/<pid>/comm` contents
- cpu: CPU percentage (requires two samples ~1s apart)
- memory: (RSS / MemTotal) × 100
- user: UID resolved to username via `/etc/passwd`

## 4.8 SecurityInfo

```json
{
  "firewall_active": true,
  "firewall_status": "Status: active\n...",
  "failed_logins_24h": 15,
  "open_ports": ["22", "80", "443"],
  "ssh_enabled": true
}
```

| Field             | Type     | Source                                                                                |
| ----------------- | -------- | ------------------------------------------------------------------------------------- |
| firewall_active   | bool     | `ufw status` output contains "Status: active"                                         |
| firewall_status   | string   | Full `ufw status` output                                                              |
| failed_logins_24h | int      | Count "Failed password" or "authentication failure" in `/var/log/auth.log` within 24h |
| open_ports        | string[] | Ports from `ss -tulpn` where address is `0.0.0.0:*` or `*:*`                          |
| ssh_enabled       | bool     | `systemctl is-active ssh` returns "active"                                            |

### Failed Login Parsing

- Parse log timestamp format: `Mon DD HH:MM:SS` (e.g., "Dec 30 10:30:45")
- Assume current year for timestamp
- Count entries within last 86400 seconds

## 4.9 HardwareInfo

```json
{
  "battery": {
    "present": true,
    "status": "Discharging",
    "capacity": 75.0,
    "health": 85.5,
    "cycle_count": 250,
    "design_capacity": 50.0,
    "full_capacity": 42.75
  },
  "temperatures": [
    {
      "label": "CPU Package",
      "current": 55.0,
      "high": 80.0,
      "critical": 100.0
    }
  ],
  "crash_reports": ["_usr_bin_app.1000.crash"]
}
```

### Battery (from `/sys/class/power_supply/BAT0/` or `BAT1/`)

| Field           | Type    | Source File                               |
| --------------- | ------- | ----------------------------------------- |
| present         | bool    | Directory exists                          |
| status          | string  | `status` file                             |
| capacity        | float64 | `capacity` file (percentage)              |
| cycle_count     | int     | `cycle_count` file                        |
| design_capacity | float64 | `energy_full_design` ÷ 1000000 (µWh → Wh) |
| full_capacity   | float64 | `energy_full` ÷ 1000000 (µWh → Wh)        |
| health          | float64 | (full_capacity / design_capacity) × 100   |

### Temperatures

| Source                                  | Label                      | Value                  |
| --------------------------------------- | -------------------------- | ---------------------- |
| `/sys/class/thermal/thermal_zone*/temp` | Zone name from `type` file | temp ÷ 1000 (m°C → °C) |
| `/sys/class/hwmon/hwmon*/temp*_input`   | From `temp*_label` file    | value ÷ 1000           |
| High/Critical thresholds                | `temp*_max`, `temp*_crit`  | value ÷ 1000           |

### Crash Reports

- List files matching `/var/crash/*.crash`

## 4.10 DockerInfo

```json
{
  "available": true,
  "daemon_running": true,
  "containers": [
    {
      "name": "nginx",
      "image": "nginx:latest",
      "status": "Up 2 hours",
      "state": "running",
      "created": "2025-12-30 08:00:00",
      "cpu_percent": 0.5,
      "memory_percent": 2.1
    }
  ],
  "running_count": 3,
  "stopped_count": 1,
  "image_count": 10,
  "total_image_size": 5368709120,
  "dangling_images_size": 1073741824
}
```

| Field                | Type  | Source                                                         |
| -------------------- | ----- | -------------------------------------------------------------- |
| available            | bool  | `docker` command exists in PATH                                |
| daemon_running       | bool  | `docker info` exits with code 0                                |
| containers           | array | `docker ps -a --format '{{json .}}'`                           |
| running_count        | int   | Count where state = "running"                                  |
| stopped_count        | int   | `docker ps -a --filter status=exited` count                    |
| image_count          | int   | Line count from `docker images --format '{{.Size}}'`           |
| total_image_size     | int64 | Sum of parsed image sizes                                      |
| dangling_images_size | int64 | Sum from `docker images -f dangling=true --format '{{.Size}}'` |

### Container Stats (for running only)

- `docker stats <name> --no-stream --format '{{.CPUPerc}},{{.MemPerc}}'`
- Parse percentages, strip `%` suffix

### Size Parsing

- "1.23GB" → 1.23 × 1024³
- "456MB" → 456 × 1024²
- "789KB" → 789 × 1024
- "123B" → 123

## 4.11 SnapInfo

```json
{
  "available": true,
  "snaps": [
    {
      "name": "firefox",
      "version": "120.0",
      "revision": "3252",
      "publisher": "mozilla",
      "disk_usage": 268435456
    }
  ],
  "total_disk_usage": 5368709120,
  "pending_refreshes": 2
}
```

| Field             | Type   | Source                                                              |
| ----------------- | ------ | ------------------------------------------------------------------- |
| available         | bool   | `snap` command exists in PATH                                       |
| snaps             | array  | Parse `snap list --color=never` (skip header line)                  |
| name              | string | Column 1                                                            |
| version           | string | Column 2                                                            |
| revision          | string | Column 3                                                            |
| publisher         | string | Column 5                                                            |
| disk_usage        | int64  | `du -sb /snap/<name>` first field                                   |
| total_disk_usage  | int64  | Sum of all snap disk_usage values                                   |
| pending_refreshes | int    | Line count from `snap refresh --list` (0 if "All snaps up to date") |

## 4.12 GPUInfo

```json
{
  "available": true,
  "gpus": [
    {
      "index": 0,
      "name": "NVIDIA GeForce RTX 3080",
      "vendor": "nvidia",
      "temperature": 65,
      "utilization": 45,
      "memory_used": 4294967296,
      "memory_total": 10737418240,
      "power_draw": 220.5
    }
  ]
}
```

### Detection Priority

1. **NVIDIA:** `nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits`

   - Parse CSV, memory values in MiB (multiply by 1024²)

2. **AMD:** Multiple `rocm-smi` calls

   - `--showtemp --csv` for temperature
   - `--showuse --csv` for utilization
   - `--showmemuse --csv` for memory

3. **Fallback:** `lspci` output
   - Grep for "VGA", "3D", "Display"
   - Parse vendor from line (nvidia/amd/intel)
   - Only name and vendor available, other fields = 0

## 4.13 LogInfo

```json
{
  "available": true,
  "period": "24h",
  "stats": {
    "error_count": 138,
    "warning_count": 45,
    "critical_count": 5,
    "oom_events": 0,
    "kernel_panics": 0,
    "segfaults": 2,
    "top_errors": [
      {
        "pattern": "Failed to connect to...",
        "count": 25
      }
    ]
  }
}
```

| Field          | Type   | Source                                                         |
| -------------- | ------ | -------------------------------------------------------------- |
| available      | bool   | `journalctl` command exists                                    |
| period         | string | Always "24h"                                                   |
| error_count    | int    | Priority 3 messages from journalctl                            |
| warning_count  | int    | Priority 4 messages                                            |
| critical_count | int    | Priority 0-2 messages                                          |
| oom_events     | int    | Kernel messages matching "Out of memory\|oom-kill\|oom_reaper" |
| kernel_panics  | int    | Kernel messages matching "Kernel panic" (journalctl -k only)   |
| segfaults      | int    | Kernel messages matching "segfault"                            |
| top_errors     | array  | Top 5 error patterns by frequency                              |

### Log Query (JSON format for priority parsing)

```bash
journalctl --since "24 hours ago" -p err..emerg --no-pager -o json
```

Parse each JSON line for:

- `PRIORITY` field: "0"/"1"/"2" → critical_count, "3" → error_count, "4" → warning_count
- `MESSAGE` field: Extract for pattern simplification

### Separate Grep Commands (kernel messages only)

```bash
# OOM events
journalctl --since "24 hours ago" -k --no-pager --grep "Out of memory|oom-kill|oom_reaper"

# Kernel panics
journalctl --since "24 hours ago" -k --no-pager --grep "Kernel panic"

# Segfaults
journalctl --since "24 hours ago" -k --no-pager --grep "segfault"
```

Count non-empty lines from each command output.

### Pattern Simplification

1. Remove hex addresses (0x[0-9a-fA-F]+) → "0x..."
2. Remove 4+ digit numbers → "..."
3. Truncate to 80 characters + "..."

## 4.14 Issue

```json
{
  "severity": "warning",
  "category": "Disk",
  "title": "Disk space warning: /",
  "description": "Filesystem usage is at 85.2%",
  "fix": "Consider cleaning up unused files"
}
```

| Field       | Type   | Values                                                                                                             |
| ----------- | ------ | ------------------------------------------------------------------------------------------------------------------ |
| severity    | string | `critical`, `warning`, `info`                                                                                      |
| category    | string | Category name (Disk, Memory, CPU, Services, Packages, Security, Hardware, Network, System, Docker, GPU, Processes) |
| title       | string | Short issue title                                                                                                  |
| description | string | Detailed description                                                                                               |
| fix         | string | Recommended action (optional)                                                                                      |

## 4.15 CollectorResult (Streaming)

When streaming, each collector emits:

```json
{
  "collector": "system",
  "timestamp": "2025-12-30T10:30:00Z",
  "data": {
    /* collector-specific data */
  }
}
```

| Field     | Type   | Description                                 |
| --------- | ------ | ------------------------------------------- |
| collector | string | Collector name (os, system, disk, etc.)     |
| timestamp | string | ISO 8601 timestamp when collector completed |
| data      | object | Collector-specific data structure           |

---

[← CLI](03-cli.md) | [Index](00-index.md) | [Next: Collectors →](05-collectors.md)
