# 8. Output Formats

[← Configuration](07-configuration.md) | [Index](00-index.md) | [Next: MCP Server →](09-mcp-server.md)

---

## 8.1 Terminal Format

### Features

- ANSI color codes for severity indication
- Box-drawing characters for section borders
- Unicode symbols: ✓ (success), ✗ (critical), ⚠ (warning), ℹ (info)
- Human-readable byte formatting (KB, MB, GB, TB)

### Color Scheme

| Element | ANSI Code | Color |
|---------|-----------|-------|
| Title/Header | `\033[1;36m` | Cyan Bold |
| Success | `\033[32m` | Green |
| Warning | `\033[33m` | Yellow |
| Error | `\033[31m` | Red |
| Critical | `\033[1;91m` | Bright Red Bold |
| Dim | `\033[90m` | Dark Gray |

### Section Order

1. Header (hostname, OS, kernel, uptime, timezone)
2. Issues Summary
3. System
4. Disk
5. Network
6. Packages
7. Services
8. Security
9. Hardware
10. Docker (if available)
11. Snaps (if available)
12. GPU (if available)
13. Logs (if available)
14. Issues Detail

## 8.2 JSON Format

**Pretty (default):** 2-space indentation

**Compact (`--json-compact`):** No whitespace

Output is the complete Report object serialized to JSON.

## 8.3 JSONL Format (Continuous Streaming)

When `--stream` is enabled, the program runs continuously, outputting one JSON object per line with cycle markers:

### Per-Cycle Output

- `{"_cycle":N,"_timestamp":"..."}` - Start of collection cycle N
- Each collector emits a CollectorResult object
- `{"_cycle_complete":N}` - End of collection cycle N

### Shutdown Output

- `{"_shutdown":true,"_total_cycles":N,"_timestamp":"..."}` - Graceful shutdown marker

### Features

- Configurable interval between cycles (`--interval`)
- Optional stop conditions (`--count`, `--duration`)
- Collector filtering (`--collectors`)
- Graceful shutdown on SIGINT/SIGTERM (Ctrl+C)
- Real-time processing as data becomes available

## 8.4 Markdown Format

Standard GitHub-flavored Markdown with:

- H1 title with timestamp
- Tables for structured data
- Bullet lists for simple lists
- Code blocks where appropriate
- Horizontal rules between major sections

## 8.5 HTML Format

### Features

- Dark theme (GitHub-inspired)
- Standalone HTML (no external CSS/JS)
- Responsive design (CSS Grid)
- Color-coded status badges
- Progress bars for percentages
- Mobile-friendly

### CSS Custom Properties

```css
:root {
  --bg: #0d1117;
  --card-bg: #161b22;
  --border: #30363d;
  --text: #c9d1d9;
  --text-dim: #8b949e;
  --accent: #58a6ff;
  --success: #3fb950;
  --warning: #d29922;
  --error: #f85149;
}
```

---

[← Configuration](07-configuration.md) | [Index](00-index.md) | [Next: MCP Server →](09-mcp-server.md)
