# 12. Appendices

[← Deployment](11-deployment.md) | [Index](00-index.md)

---

## Appendix A: Byte Formatting

Convert bytes to human-readable format:

```
if bytes < 1024: return f"{bytes} B"
for unit in ["KB", "MB", "GB", "TB", "PB"]:
    bytes /= 1024
    if bytes < 1024:
        return f"{bytes:.1f} {unit}"
```

## Appendix B: Duration Formatting

Convert seconds to human-readable uptime:

```
days = seconds // 86400
hours = (seconds % 86400) // 3600
minutes = (seconds % 3600) // 60

if days > 0: return f"{days}d {hours}h {minutes}m"
if hours > 0: return f"{hours}h {minutes}m"
return f"{minutes}m"
```

## Appendix C: Graceful Degradation Matrix

| Feature | When Unavailable | Fallback Behavior |
|---------|------------------|-------------------|
| Docker | No docker binary | DockerInfo.Available = false, empty data |
| Snap | No snap binary | SnapInfo.Available = false, empty data |
| GPU | No nvidia-smi/rocm-smi | Try lspci, then GPUInfo.Available = false |
| Logs | No journalctl | LogInfo.Available = false |
| Battery | No /sys/class/power_supply/BAT* | HardwareInfo.Battery = null |
| Firewall | No ufw | SecurityInfo.FirewallActive = false |
| APT | No apt | PackageInfo with zeros |
| Systemd | No systemctl | ServiceInfo.FailedUnits = [] |

---

*End of Specification*

[← Deployment](11-deployment.md) | [Index](00-index.md)
