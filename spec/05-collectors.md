# 5. Collectors

[← Data Model](04-data-model.md) | [Index](00-index.md) | [Next: Issue Detection →](06-issue-detection.md)

---

## 5.1 Collection Order

```
1. CollectOSInfo()
2. CollectSystemInfo()
3. CollectDiskInfo()
4. CollectNetworkInfo()
5. CollectPackageInfo()
6. CollectServiceInfo()
7. CollectSecurityInfo()
8. CollectHardwareInfo()
9. CollectDockerInfo()
10. CollectSnapInfo()
11. CollectGPUInfo()
12. CollectLogInfo()
13. analyzeIssues(report)  // Generate issues from collected data
```

## 5.2 Error Handling

Each collector MUST:

1. Return a valid (possibly empty) data structure on any error
2. Never crash or panic
3. Set `Available: false` for optional features when unavailable
4. Log errors internally but not to stdout/stderr (except in debug mode)

## 5.3 Exact Collection Mechanisms

All implementations MUST use identical file reads and command invocations. This section documents the canonical mechanisms.

### 5.3.1 OSInfo Collection

**File Reads:**
```
/etc/os-release        → Parse PRETTY_NAME for "name", VERSION for "version"
/proc/version          → Fallback for kernel version
```

**Commands:**
```bash
uname -r               → Kernel version
uname -m               → Architecture
```

### 5.3.2 SystemInfo Collection

**File Reads:**
```
/proc/uptime           → First field = uptime in seconds
/proc/loadavg          → First 3 fields = load averages (1/5/15 min)
/proc/cpuinfo          → Count lines starting with "processor" = cpu_cores
/proc/stat             → Read twice 1s apart to calculate cpu_usage
/proc/meminfo          → MemTotal, MemAvailable, SwapTotal, SwapFree
/etc/timezone          → Read directly for timezone string
/var/run/reboot-required → File existence = reboot_required
```

**Commands (timezone fallback):**
```bash
timedatectl show --property=Timezone --value
```

**CPU Usage Calculation:**

1. Read `/proc/stat` first line: `cpu user nice system idle iowait irq softirq steal guest guest_nice`
2. Wait 1 second
3. Read again
4. Calculate: `usage = 100 * (non_idle_delta / total_delta)`

### 5.3.3 DiskInfo Collection

**System Calls:**
```c
statvfs(mount_point)   → Get f_blocks, f_bfree, f_bavail, f_frsize, f_files, f_ffree
```

**File Reads:**
```
/proc/mounts           → Parse for device, mount_point, fs_type
```

**Filtering:** Skip fs_type in: `proc sysfs devfs devpts devtmpfs tmpfs securityfs cgroup cgroup2 pstore debugfs hugetlbfs mqueue fusectl configfs binfmt_misc autofs efivarfs squashfs`

Skip mount_point matching: `/snap/*`

### 5.3.4 NetworkInfo Collection

**File Reads:**
```
/sys/class/net/*/      → List interface directories (exclude "lo", "veth*")
/sys/class/net/<name>/operstate    → "up" or "down" → state
/sys/class/net/<name>/address      → MAC address
/proc/net/dev          → rx_bytes, tx_bytes (fields 2 and 10 per interface)
/proc/net/tcp          → Parse for listen ports (state=0A), inode
/proc/net/tcp6         → Same as tcp
/proc/net/udp          → Parse for listen ports (state=07)
/proc/net/udp6         → Same as udp
/proc/<pid>/fd/*       → Readlink to match socket inodes
/proc/<pid>/comm       → Process name for matched PID
```

**Commands (IP addresses):**
```bash
ip -o addr show        → Parse for interface IPs
```

**Connectivity Test:**

TCP connect to `8.8.8.8:53` with 3-second timeout. Success = true.

### 5.3.5 PackageInfo Collection

**Commands:**
```bash
apt list --upgradable 2>/dev/null    → Count lines (minus first header line)
dpkg --audit                          → Non-empty output = broken_packages
apt-mark showhold                     → List of held packages
```

**Security Updates:** Count lines containing `-security` or `security.ubuntu.com` from apt list output.

### 5.3.6 ServiceInfo Collection

**Commands:**
```bash
systemctl --failed --no-pager --no-legend    → First column = failed unit names
```

**File Reads:**
```
/proc/*/stat           → Parse field 3 for 'Z' to count zombies
                       → Parse field 14 (utime) and 15 (stime) for CPU
/proc/*/status         → Parse VmRSS for memory usage
/proc/*/comm           → Process name
/etc/passwd            → Resolve UID to username
```

**Top Processes:** Read /proc/*/stat twice 1 second apart to calculate CPU percentage. Sort by CPU and memory to get top 5 each.

### 5.3.7 SecurityInfo Collection

**Commands:**
```bash
ufw status                        → Check for "Status: active"
systemctl is-active ssh           → Returns "active" if SSH enabled
ss -tulpn                         → Parse for ports on 0.0.0.0 or *
```

**File Reads:**
```
/var/log/auth.log      → Count "Failed password" or "authentication failure" within 24h
```

**Timestamp Parsing:** `Mon DD HH:MM:SS` format, assume current year.

### 5.3.8 HardwareInfo Collection

**File Reads:**
```
/sys/class/power_supply/BAT*/         → Check for battery directories
/sys/class/power_supply/BAT*/status           → Battery status
/sys/class/power_supply/BAT*/capacity         → Percentage
/sys/class/power_supply/BAT*/cycle_count      → Cycle count
/sys/class/power_supply/BAT*/energy_full_design    → Design capacity (µWh)
/sys/class/power_supply/BAT*/energy_full           → Full capacity (µWh)
/sys/class/thermal/thermal_zone*/temp         → Temperature (m°C)
/sys/class/thermal/thermal_zone*/type         → Zone label
/sys/class/hwmon/hwmon*/temp*_input           → Temperature (m°C)
/sys/class/hwmon/hwmon*/temp*_label           → Sensor label
/var/crash/*.crash                            → List crash report files
```

**Unit Conversions:** µWh → Wh: divide by 1,000,000. m°C → °C: divide by 1,000.

### 5.3.9 DockerInfo Collection

**Command Existence:** Check if `docker` is in PATH.

**Commands:**
```bash
docker info                              → Exit code 0 = daemon running
docker ps -a --format '{{json .}}'       → Container list as JSON
docker stats <name> --no-stream --format '{{.CPUPerc}},{{.MemPerc}}'   → CPU/Memory
docker images --format '{{.Size}}'       → Image sizes
docker images -f dangling=true --format '{{.Size}}'   → Dangling image sizes
```

**Size Parsing:** Parse "1.23GB", "456MB", "789KB", "123B" with binary multipliers (1024^n).

### 5.3.10 SnapInfo Collection

**Command Existence:** Check if `snap` is in PATH.

**Commands:**
```bash
snap list --color=never                 → Parse columns (skip header)
du -sb /snap/<name>                     → Disk usage per snap
snap refresh --list                     → "All snaps up to date" = 0, else count lines
```

### 5.3.11 GPUInfo Collection

**Detection Order (try in sequence, use first that succeeds):**

1. **NVIDIA:**
```bash
nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits
```
Parse CSV. Memory values in MiB (multiply by 1024²).

2. **AMD:**
```bash
rocm-smi --showtemp --csv
rocm-smi --showuse --csv
rocm-smi --showmemuse --csv
```

3. **Fallback (lspci):**
```bash
lspci
```
Grep for lines containing "VGA", "3D", or "Display". Parse vendor from text.

### 5.3.12 LogInfo Collection

**Command Existence:** Check if `journalctl` is in PATH.

**Main Query (JSON format for priority parsing):**
```bash
journalctl --since "24 hours ago" -p err..emerg --no-pager -o json
```

Parse each JSON line:
- `PRIORITY` field: "0"/"1"/"2" → critical_count, "3" → error_count, "4" → warning_count
- `MESSAGE` field: Extract for pattern simplification

**Separate Grep Commands (for specific event counts):**
```bash
journalctl --since "24 hours ago" -k --no-pager --grep "Out of memory|oom-kill|oom_reaper"
journalctl --since "24 hours ago" -k --no-pager --grep "Kernel panic"
journalctl --since "24 hours ago" -k --no-pager --grep "segfault"
```

Count non-empty lines that don't start with "-- " (skip journalctl status messages).

**Pattern Simplification:**

1. Replace hex addresses (`0x[0-9a-fA-F]+`) → `0x...`
2. Replace 4+ digit numbers → `...`
3. Truncate to 80 characters + "..."

---

[← Data Model](04-data-model.md) | [Index](00-index.md) | [Next: Issue Detection →](06-issue-detection.md)
