package outputs

import (
	"fmt"
	"strings"

	"github.com/fatih/color"

	"ubuntu-state/models"
)

var (
	titleStyle    = color.New(color.FgHiWhite, color.Bold)
	headerStyle   = color.New(color.FgCyan, color.Bold)
	successStyle  = color.New(color.FgGreen)
	warningStyle  = color.New(color.FgYellow)
	errorStyle    = color.New(color.FgRed)
	criticalStyle = color.New(color.FgHiRed, color.Bold)
	dimStyle      = color.New(color.FgHiBlack)
	infoStyle     = color.New(color.FgWhite)
)

// RenderTerminal outputs the report to terminal with colors
func RenderTerminal(report *models.Report) string {
	var sb strings.Builder

	// Header
	sb.WriteString("\n")
	titleStyle.Fprint(&sb, "═══════════════════════════════════════════════════════════════\n")
	titleStyle.Fprint(&sb, "                    UBUNTU SYSTEM STATE REPORT                  \n")
	titleStyle.Fprint(&sb, "═══════════════════════════════════════════════════════════════\n")
	sb.WriteString("\n")

	// Basic info
	dimStyle.Fprintf(&sb, "  Hostname: ")
	infoStyle.Fprintf(&sb, "%s\n", report.Hostname)
	dimStyle.Fprintf(&sb, "  OS:       ")
	infoStyle.Fprintf(&sb, "%s\n", report.OS.Name)
	dimStyle.Fprintf(&sb, "  Kernel:   ")
	infoStyle.Fprintf(&sb, "%s\n", report.OS.Kernel)
	dimStyle.Fprintf(&sb, "  Uptime:   ")
	infoStyle.Fprintf(&sb, "%s\n", report.System.UptimeHuman)
	if report.System.Timezone != "" {
		dimStyle.Fprintf(&sb, "  Timezone: ")
		infoStyle.Fprintf(&sb, "%s\n", report.System.Timezone)
	}
	dimStyle.Fprintf(&sb, "  Report:   ")
	infoStyle.Fprintf(&sb, "%s\n", report.Timestamp.Format("2006-01-02 15:04:05"))
	if report.System.RebootRequired {
		warningStyle.Fprintf(&sb, "  ⚠ Reboot Required\n")
	}
	sb.WriteString("\n")

	// Issues summary
	renderIssuesSummary(&sb, report.Issues)
	sb.WriteString("\n")

	// System section
	renderSection(&sb, "SYSTEM", func(sb *strings.Builder) {
		renderKV(sb, "Load Average", fmt.Sprintf("%.2f / %.2f / %.2f (1/5/15 min)",
			report.System.LoadAvg1, report.System.LoadAvg5, report.System.LoadAvg15))
		renderKV(sb, "CPU Cores", fmt.Sprintf("%d", report.System.CPUCores))
		renderKV(sb, "CPU Usage", fmt.Sprintf("%.1f%%", report.System.CPUUsage))
		renderKVWithStatus(sb, "Memory", fmt.Sprintf("%s / %s (%.1f%%)",
			formatBytes(report.System.MemoryUsed),
			formatBytes(report.System.MemoryTotal),
			report.System.MemoryPercent), report.System.MemoryPercent, 80, 90)
		if report.System.SwapTotal > 0 {
			renderKVWithStatus(sb, "Swap", fmt.Sprintf("%s / %s (%.1f%%)",
				formatBytes(report.System.SwapUsed),
				formatBytes(report.System.SwapTotal),
				report.System.SwapPercent), report.System.SwapPercent, 50, 80)
		}
	})

	// Disk section
	renderSection(&sb, "DISK", func(sb *strings.Builder) {
		for _, fs := range report.Disk.Filesystems {
			label := fmt.Sprintf("%s (%s)", fs.MountPoint, fs.FSType)
			value := fmt.Sprintf("%s / %s (%.1f%%)",
				formatBytes(fs.Used), formatBytes(fs.Total), fs.UsedPercent)
			renderKVWithStatus(sb, label, value, fs.UsedPercent, 80, 90)
		}
	})

	// Network section
	renderSection(&sb, "NETWORK", func(sb *strings.Builder) {
		for _, iface := range report.Network.Interfaces {
			status := iface.State
			if status == "UP" {
				successStyle.Fprintf(sb, "  %-12s ", iface.Name)
				successStyle.Fprint(sb, "UP")
			} else {
				dimStyle.Fprintf(sb, "  %-12s ", iface.Name)
				dimStyle.Fprint(sb, "DOWN")
			}
			if len(iface.IPs) > 0 {
				dimStyle.Fprintf(sb, "  %s", strings.Join(iface.IPs, ", "))
			}
			sb.WriteString("\n")
		}
		sb.WriteString("\n")
		if report.Network.Connectivity {
			renderKV(sb, "Internet", successStyle.Sprint("Connected"))
		} else {
			renderKV(sb, "Internet", errorStyle.Sprint("Disconnected"))
		}
		renderKV(sb, "Listening Ports", fmt.Sprintf("%d", len(report.Network.ListenPorts)))
	})

	// Packages section
	renderSection(&sb, "PACKAGES", func(sb *strings.Builder) {
		if report.Packages.UpdatesAvailable > 0 {
			renderKVWithColor(sb, "Updates Available", fmt.Sprintf("%d", report.Packages.UpdatesAvailable), warningStyle)
		} else {
			renderKVWithColor(sb, "Updates Available", "0", successStyle)
		}
		if report.Packages.SecurityUpdates > 0 {
			renderKVWithColor(sb, "Security Updates", fmt.Sprintf("%d", report.Packages.SecurityUpdates), errorStyle)
		}
		if report.Packages.BrokenPackages > 0 {
			renderKVWithColor(sb, "Broken Packages", fmt.Sprintf("%d", report.Packages.BrokenPackages), errorStyle)
		}
		if len(report.Packages.HeldPackages) > 0 {
			renderKV(sb, "Held Packages", strings.Join(report.Packages.HeldPackages, ", "))
		}
	})

	// Services section
	renderSection(&sb, "SERVICES", func(sb *strings.Builder) {
		if len(report.Services.FailedUnits) > 0 {
			renderKVWithColor(sb, "Failed Services", fmt.Sprintf("%d", len(report.Services.FailedUnits)), errorStyle)
			for _, unit := range report.Services.FailedUnits {
				errorStyle.Fprintf(sb, "    - %s\n", unit)
			}
		} else {
			renderKVWithColor(sb, "Failed Services", "0", successStyle)
		}
		if report.Services.ZombieCount > 0 {
			renderKVWithColor(sb, "Zombie Processes", fmt.Sprintf("%d", report.Services.ZombieCount), warningStyle)
		}

		sb.WriteString("\n")
		dimStyle.Fprint(sb, "  Top CPU:\n")
		for _, p := range report.Services.TopCPU {
			fmt.Fprintf(sb, "    %-20s %5.1f%% CPU  (%s)\n", truncate(p.Name, 20), p.CPU, p.User)
		}
	})

	// Security section
	renderSection(&sb, "SECURITY", func(sb *strings.Builder) {
		if report.Security.FirewallActive {
			renderKVWithColor(sb, "Firewall", "Active", successStyle)
		} else {
			renderKVWithColor(sb, "Firewall", "Inactive", errorStyle)
		}
		if report.Security.SSHEnabled {
			renderKV(sb, "SSH", "Enabled")
		}
		if report.Security.FailedLogins24h > 0 {
			renderKVWithColor(sb, "Failed Logins (24h)", fmt.Sprintf("%d", report.Security.FailedLogins24h), warningStyle)
		}
		if len(report.Security.OpenPorts) > 0 {
			renderKV(sb, "Ports on 0.0.0.0", fmt.Sprintf("%d", len(report.Security.OpenPorts)))
		}
	})

	// Hardware section
	renderSection(&sb, "HARDWARE", func(sb *strings.Builder) {
		if report.Hardware.Battery != nil {
			b := report.Hardware.Battery
			batteryStatus := fmt.Sprintf("%s (%.0f%% capacity, %.1f%% health, %d cycles)",
				b.Status, b.Capacity, b.Health, b.CycleCount)
			if b.Health < 50 {
				renderKVWithColor(sb, "Battery", batteryStatus, errorStyle)
			} else if b.Health < 80 {
				renderKVWithColor(sb, "Battery", batteryStatus, warningStyle)
			} else {
				renderKV(sb, "Battery", batteryStatus)
			}
		}

		if len(report.Hardware.Temperatures) > 0 {
			sb.WriteString("\n")
			dimStyle.Fprint(sb, "  Temperatures:\n")
			for _, t := range report.Hardware.Temperatures {
				tempStr := fmt.Sprintf("%.1f°C", t.Current)
				if t.Current >= 85 {
					fmt.Fprintf(sb, "    %-20s ", truncate(t.Label, 20))
					errorStyle.Fprintf(sb, "%s\n", tempStr)
				} else if t.Current >= 70 {
					fmt.Fprintf(sb, "    %-20s ", truncate(t.Label, 20))
					warningStyle.Fprintf(sb, "%s\n", tempStr)
				} else {
					fmt.Fprintf(sb, "    %-20s %s\n", truncate(t.Label, 20), tempStr)
				}
			}
		}

		if len(report.Hardware.CrashReports) > 0 {
			renderKVWithColor(sb, "Crash Reports", fmt.Sprintf("%d in /var/crash", len(report.Hardware.CrashReports)), warningStyle)
		}
	})

	// Docker section
	if report.Docker.Available {
		renderSection(&sb, "DOCKER", func(sb *strings.Builder) {
			if !report.Docker.DaemonRunning {
				renderKVWithColor(sb, "Docker Daemon", "Not Running", errorStyle)
				return
			}
			renderKV(sb, "Running Containers", fmt.Sprintf("%d", report.Docker.RunningCount))
			if report.Docker.StoppedCount > 0 {
				renderKVWithColor(sb, "Stopped Containers", fmt.Sprintf("%d", report.Docker.StoppedCount), dimStyle)
			}
			renderKV(sb, "Images", fmt.Sprintf("%d (%s)", report.Docker.ImageCount, formatBytes(uint64(report.Docker.TotalImageSize))))
			if report.Docker.DanglingImages > 0 {
				renderKVWithColor(sb, "Dangling Images", formatBytes(uint64(report.Docker.DanglingImages)), warningStyle)
			}

			if len(report.Docker.Containers) > 0 {
				sb.WriteString("\n")
				dimStyle.Fprint(sb, "  Running Containers:\n")
				for _, c := range report.Docker.Containers {
					if c.State == "running" {
						fmt.Fprintf(sb, "    %-20s %s (%.1f%% CPU, %.1f%% Mem)\n",
							truncate(c.Name, 20), truncate(c.Image, 25), c.CPUPercent, c.MemoryPercent)
					}
				}
			}
		})
	}

	// Snaps section
	if report.Snaps.Available && len(report.Snaps.Snaps) > 0 {
		renderSection(&sb, "SNAPS", func(sb *strings.Builder) {
			renderKV(sb, "Installed Snaps", fmt.Sprintf("%d", len(report.Snaps.Snaps)))
			renderKV(sb, "Total Disk Usage", formatBytes(uint64(report.Snaps.TotalDiskUsage)))
			if report.Snaps.PendingRefreshes > 0 {
				renderKVWithColor(sb, "Pending Refreshes", fmt.Sprintf("%d", report.Snaps.PendingRefreshes), warningStyle)
			}
		})
	}

	// GPU section
	if report.GPU.Available && len(report.GPU.GPUs) > 0 {
		renderSection(&sb, "GPU", func(sb *strings.Builder) {
			for _, gpu := range report.GPU.GPUs {
				sb.WriteString("\n")
				dimStyle.Fprintf(sb, "  [%d] %s (%s)\n", gpu.Index, gpu.Name, gpu.Vendor)
				if gpu.Temperature > 0 {
					tempStr := fmt.Sprintf("%d°C", gpu.Temperature)
					if gpu.Temperature >= 90 {
						fmt.Fprintf(sb, "      Temperature:  ")
						errorStyle.Fprintf(sb, "%s\n", tempStr)
					} else if gpu.Temperature >= 80 {
						fmt.Fprintf(sb, "      Temperature:  ")
						warningStyle.Fprintf(sb, "%s\n", tempStr)
					} else {
						fmt.Fprintf(sb, "      Temperature:  %s\n", tempStr)
					}
				}
				if gpu.Utilization > 0 {
					fmt.Fprintf(sb, "      Utilization:  %d%%\n", gpu.Utilization)
				}
				if gpu.MemoryTotal > 0 {
					fmt.Fprintf(sb, "      Memory:       %s / %s\n",
						formatBytes(uint64(gpu.MemoryUsed)), formatBytes(uint64(gpu.MemoryTotal)))
				}
				if gpu.PowerDraw > 0 {
					fmt.Fprintf(sb, "      Power Draw:   %.1fW\n", gpu.PowerDraw)
				}
			}
		})
	}

	// Logs section
	if report.Logs.Available {
		renderSection(&sb, "LOGS (24h)", func(sb *strings.Builder) {
			if report.Logs.Stats.CriticalCount > 0 {
				renderKVWithColor(sb, "Critical", fmt.Sprintf("%d", report.Logs.Stats.CriticalCount), errorStyle)
			}
			if report.Logs.Stats.ErrorCount > 0 {
				renderKVWithColor(sb, "Errors", fmt.Sprintf("%d", report.Logs.Stats.ErrorCount), warningStyle)
			}
			if report.Logs.Stats.WarningCount > 0 {
				renderKV(sb, "Warnings", fmt.Sprintf("%d", report.Logs.Stats.WarningCount))
			}
			if report.Logs.Stats.OOMEvents > 0 {
				renderKVWithColor(sb, "OOM Events", fmt.Sprintf("%d", report.Logs.Stats.OOMEvents), errorStyle)
			}
			if report.Logs.Stats.KernelPanics > 0 {
				renderKVWithColor(sb, "Kernel Panics", fmt.Sprintf("%d", report.Logs.Stats.KernelPanics), criticalStyle)
			}
			if report.Logs.Stats.Segfaults > 0 {
				renderKVWithColor(sb, "Segfaults", fmt.Sprintf("%d", report.Logs.Stats.Segfaults), warningStyle)
			}

			if len(report.Logs.Stats.TopErrors) > 0 {
				sb.WriteString("\n")
				dimStyle.Fprint(sb, "  Top Error Patterns:\n")
				for _, e := range report.Logs.Stats.TopErrors {
					fmt.Fprintf(sb, "    [%d] %s\n", e.Count, truncate(e.Pattern, 60))
				}
			}
		})
	}

	// Detailed issues
	renderIssuesDetail(&sb, report.Issues)

	return sb.String()
}

func renderSection(sb *strings.Builder, title string, content func(*strings.Builder)) {
	headerStyle.Fprintf(sb, "┌─ %s\n", title)
	content(sb)
	sb.WriteString("\n")
}

func renderKV(sb *strings.Builder, key, value string) {
	dimStyle.Fprintf(sb, "  %-20s ", key+":")
	infoStyle.Fprintf(sb, "%s\n", value)
}

func renderKVWithColor(sb *strings.Builder, key, value string, c *color.Color) {
	dimStyle.Fprintf(sb, "  %-20s ", key+":")
	c.Fprintf(sb, "%s\n", value)
}

func renderKVWithStatus(sb *strings.Builder, key, value string, percent float64, warnThreshold, critThreshold float64) {
	dimStyle.Fprintf(sb, "  %-20s ", key+":")
	if percent >= critThreshold {
		errorStyle.Fprintf(sb, "%s\n", value)
	} else if percent >= warnThreshold {
		warningStyle.Fprintf(sb, "%s\n", value)
	} else {
		successStyle.Fprintf(sb, "%s\n", value)
	}
}

func renderIssuesSummary(sb *strings.Builder, issues []models.Issue) {
	critical, warning, info := 0, 0, 0
	for _, issue := range issues {
		switch issue.Severity {
		case models.SeverityCritical:
			critical++
		case models.SeverityWarning:
			warning++
		case models.SeverityInfo:
			info++
		}
	}

	if critical == 0 && warning == 0 {
		successStyle.Fprint(sb, "  ✓ No critical issues detected\n")
	} else {
		if critical > 0 {
			criticalStyle.Fprintf(sb, "  ✗ %d critical issue(s)\n", critical)
		}
		if warning > 0 {
			warningStyle.Fprintf(sb, "  ⚠ %d warning(s)\n", warning)
		}
	}
	if info > 0 {
		dimStyle.Fprintf(sb, "  ℹ %d info item(s)\n", info)
	}
}

func renderIssuesDetail(sb *strings.Builder, issues []models.Issue) {
	if len(issues) == 0 {
		return
	}

	headerStyle.Fprint(sb, "┌─ ISSUES\n")
	for _, issue := range issues {
		var icon string
		var style *color.Color
		switch issue.Severity {
		case models.SeverityCritical:
			icon = "✗"
			style = criticalStyle
		case models.SeverityWarning:
			icon = "⚠"
			style = warningStyle
		default:
			icon = "ℹ"
			style = dimStyle
		}

		style.Fprintf(sb, "  %s [%s] %s\n", icon, issue.Category, issue.Title)
		dimStyle.Fprintf(sb, "    %s\n", issue.Description)
		if issue.Fix != "" {
			successStyle.Fprintf(sb, "    Fix: %s\n", issue.Fix)
		}
		sb.WriteString("\n")
	}
}

func formatBytes(b uint64) string {
	const unit = 1024
	if b < unit {
		return fmt.Sprintf("%d B", b)
	}
	div, exp := uint64(unit), 0
	for n := b / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(b)/float64(div), "KMGTPE"[exp])
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-3] + "..."
}
