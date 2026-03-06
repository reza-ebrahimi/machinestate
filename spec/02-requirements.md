# 2. System Requirements

[← Overview](01-overview.md) | [Index](00-index.md) | [Next: CLI →](03-cli.md)

---

## 2.1 Target Platform

- **Operating System:** Linux (optimized for Ubuntu/Debian)
- **Architecture:** amd64, arm64

## 2.2 Required System Interfaces

| Interface | Purpose | Fallback |
|-----------|---------|----------|
| `/proc/` | Process info, memory stats | None (required) |
| `/sys/class/` | Hardware sensors, battery | Empty data |
| `/etc/os-release` | OS identification | Use kernel info |
| `/etc/timezone` | Timezone | `timedatectl` command |
| `/var/log/auth.log` | Failed login attempts | Return 0 |
| `/var/crash/` | Crash reports | Empty list |
| `/var/run/reboot-required` | Reboot status | Return false |

## 2.3 Optional External Commands

| Command | Purpose | Fallback |
|---------|---------|----------|
| `apt` | Package updates | Empty PackageInfo |
| `dpkg` | Broken packages | Return 0 |
| `apt-mark` | Held packages | Empty list |
| `systemctl` | Service status | Empty ServiceInfo |
| `ufw` | Firewall status | Return inactive |
| `ss` | Open ports | Empty list |
| `docker` | Container info | DockerInfo.Available = false |
| `snap` | Snap packages | SnapInfo.Available = false |
| `nvidia-smi` | NVIDIA GPU | Try AMD/Intel fallback |
| `rocm-smi` | AMD GPU | Try lspci fallback |
| `lspci` | GPU detection | GPUInfo.Available = false |
| `journalctl` | Log analysis | LogInfo.Available = false |
| `timedatectl` | Timezone | Use Go/system locale |
| `ps` | Process names | Return empty string |
| `du` | Disk usage | Return 0 |

---

[← Overview](01-overview.md) | [Index](00-index.md) | [Next: CLI →](03-cli.md)
