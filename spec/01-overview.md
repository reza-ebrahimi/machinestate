# 1. Overview

[← Index](00-index.md) | [Next: Requirements →](02-requirements.md)

---

## 1.1 Purpose

MachineState is a system health reporter that:

- Collects comprehensive system metrics from Linux systems
- Detects issues and provides actionable recommendations
- Outputs reports in multiple formats (terminal, HTML, JSON, Markdown)
- Supports real-time streaming of data per collector
- Exposes data via Model Context Protocol (MCP) for AI assistant integration

## 1.2 Design Principles

1. **Single Binary** - No runtime dependencies; everything compiles into one executable
2. **Read-Only** - Never modifies system state; purely observational
3. **Graceful Degradation** - Missing tools/features fail silently with empty data
4. **Configurable Thresholds** - Issue detection thresholds are user-configurable
5. **Cross-Platform Data Sources** - Use standard Linux interfaces (/proc, /sys, commands)

---

[← Index](00-index.md) | [Next: Requirements →](02-requirements.md)
