package outputs

import (
	"fmt"
	"strings"

	"ubuntu-state/models"
)

// RenderMarkdown outputs the report as Markdown
func RenderMarkdown(report *models.Report) string {
	var sb strings.Builder

	// Header
	sb.WriteString("# Ubuntu System State Report\n\n")
	sb.WriteString(fmt.Sprintf("**Generated:** %s  \n", report.Timestamp.Format("2006-01-02 15:04:05")))
	sb.WriteString(fmt.Sprintf("**Hostname:** %s  \n", report.Hostname))
	sb.WriteString(fmt.Sprintf("**OS:** %s  \n", report.OS.Name))
	sb.WriteString(fmt.Sprintf("**Kernel:** %s  \n", report.OS.Kernel))
	sb.WriteString(fmt.Sprintf("**Uptime:** %s  \n\n", report.System.UptimeHuman))

	// Issues Summary
	sb.WriteString("## Issues Summary\n\n")
	critical, warning, info := countIssues(report.Issues)
	if critical > 0 {
		sb.WriteString(fmt.Sprintf("- **%d** Critical issue(s)\n", critical))
	}
	if warning > 0 {
		sb.WriteString(fmt.Sprintf("- **%d** Warning(s)\n", warning))
	}
	if info > 0 {
		sb.WriteString(fmt.Sprintf("- **%d** Info item(s)\n", info))
	}
	if critical == 0 && warning == 0 && info == 0 {
		sb.WriteString("No issues detected.\n")
	}
	sb.WriteString("\n")

	// System
	sb.WriteString("## System\n\n")
	sb.WriteString("| Metric | Value |\n")
	sb.WriteString("|--------|-------|\n")
	sb.WriteString(fmt.Sprintf("| Load Average | %.2f / %.2f / %.2f (1/5/15 min) |\n",
		report.System.LoadAvg1, report.System.LoadAvg5, report.System.LoadAvg15))
	sb.WriteString(fmt.Sprintf("| CPU Cores | %d |\n", report.System.CPUCores))
	sb.WriteString(fmt.Sprintf("| CPU Usage | %.1f%% |\n", report.System.CPUUsage))
	sb.WriteString(fmt.Sprintf("| Memory | %s / %s (%.1f%%) |\n",
		formatBytes(report.System.MemoryUsed), formatBytes(report.System.MemoryTotal), report.System.MemoryPercent))
	if report.System.SwapTotal > 0 {
		sb.WriteString(fmt.Sprintf("| Swap | %s / %s (%.1f%%) |\n",
			formatBytes(report.System.SwapUsed), formatBytes(report.System.SwapTotal), report.System.SwapPercent))
	}
	sb.WriteString("\n")

	// Disk
	sb.WriteString("## Disk\n\n")
	sb.WriteString("| Mount Point | Size | Used | Free | Usage |\n")
	sb.WriteString("|-------------|------|------|------|-------|\n")
	for _, fs := range report.Disk.Filesystems {
		sb.WriteString(fmt.Sprintf("| %s | %s | %s | %s | %.1f%% |\n",
			fs.MountPoint, formatBytes(fs.Total), formatBytes(fs.Used), formatBytes(fs.Free), fs.UsedPercent))
	}
	sb.WriteString("\n")

	// Network
	sb.WriteString("## Network\n\n")
	sb.WriteString("### Interfaces\n\n")
	sb.WriteString("| Interface | State | IPs |\n")
	sb.WriteString("|-----------|-------|-----|\n")
	for _, iface := range report.Network.Interfaces {
		sb.WriteString(fmt.Sprintf("| %s | %s | %s |\n",
			iface.Name, iface.State, strings.Join(iface.IPs, ", ")))
	}
	sb.WriteString("\n")
	sb.WriteString(fmt.Sprintf("**Internet Connectivity:** %s  \n", boolToStatus(report.Network.Connectivity)))
	sb.WriteString(fmt.Sprintf("**Listening Ports:** %d  \n\n", len(report.Network.ListenPorts)))

	// Packages
	sb.WriteString("## Packages\n\n")
	sb.WriteString(fmt.Sprintf("- **Updates Available:** %d\n", report.Packages.UpdatesAvailable))
	if report.Packages.SecurityUpdates > 0 {
		sb.WriteString(fmt.Sprintf("- **Security Updates:** %d\n", report.Packages.SecurityUpdates))
	}
	if report.Packages.BrokenPackages > 0 {
		sb.WriteString(fmt.Sprintf("- **Broken Packages:** %d\n", report.Packages.BrokenPackages))
	}
	sb.WriteString("\n")

	// Services
	sb.WriteString("## Services\n\n")
	if len(report.Services.FailedUnits) > 0 {
		sb.WriteString("### Failed Services\n\n")
		for _, unit := range report.Services.FailedUnits {
			sb.WriteString(fmt.Sprintf("- %s\n", unit))
		}
		sb.WriteString("\n")
	} else {
		sb.WriteString("No failed services.\n\n")
	}

	sb.WriteString("### Top CPU Processes\n\n")
	sb.WriteString("| Process | CPU | Memory | User |\n")
	sb.WriteString("|---------|-----|--------|------|\n")
	for _, p := range report.Services.TopCPU {
		sb.WriteString(fmt.Sprintf("| %s | %.1f%% | %.1f%% | %s |\n",
			p.Name, p.CPU, p.Memory, p.User))
	}
	sb.WriteString("\n")

	// Security
	sb.WriteString("## Security\n\n")
	sb.WriteString(fmt.Sprintf("- **Firewall:** %s\n", boolToActive(report.Security.FirewallActive)))
	sb.WriteString(fmt.Sprintf("- **SSH:** %s\n", boolToEnabled(report.Security.SSHEnabled)))
	if report.Security.FailedLogins24h > 0 {
		sb.WriteString(fmt.Sprintf("- **Failed Logins (24h):** %d\n", report.Security.FailedLogins24h))
	}
	sb.WriteString("\n")

	// Hardware
	sb.WriteString("## Hardware\n\n")
	if report.Hardware.Battery != nil {
		b := report.Hardware.Battery
		sb.WriteString("### Battery\n\n")
		sb.WriteString(fmt.Sprintf("- **Status:** %s\n", b.Status))
		sb.WriteString(fmt.Sprintf("- **Capacity:** %.0f%%\n", b.Capacity))
		sb.WriteString(fmt.Sprintf("- **Health:** %.1f%%\n", b.Health))
		sb.WriteString(fmt.Sprintf("- **Cycle Count:** %d\n", b.CycleCount))
		sb.WriteString("\n")
	}

	if len(report.Hardware.Temperatures) > 0 {
		sb.WriteString("### Temperatures\n\n")
		sb.WriteString("| Sensor | Temperature |\n")
		sb.WriteString("|--------|-------------|\n")
		for _, t := range report.Hardware.Temperatures {
			sb.WriteString(fmt.Sprintf("| %s | %.1f°C |\n", t.Label, t.Current))
		}
		sb.WriteString("\n")
	}

	if len(report.Hardware.CrashReports) > 0 {
		sb.WriteString(fmt.Sprintf("### Crash Reports\n\n%d crash report(s) in /var/crash\n\n", len(report.Hardware.CrashReports)))
	}

	// Detailed Issues
	if len(report.Issues) > 0 {
		sb.WriteString("## Detailed Issues\n\n")
		for _, issue := range report.Issues {
			severity := strings.ToUpper(issue.Severity)
			sb.WriteString(fmt.Sprintf("### [%s] %s\n\n", severity, issue.Title))
			sb.WriteString(fmt.Sprintf("**Category:** %s  \n", issue.Category))
			sb.WriteString(fmt.Sprintf("**Description:** %s  \n", issue.Description))
			if issue.Fix != "" {
				sb.WriteString(fmt.Sprintf("**Fix:** %s  \n", issue.Fix))
			}
			sb.WriteString("\n")
		}
	}

	return sb.String()
}

func countIssues(issues []models.Issue) (critical, warning, info int) {
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
	return
}

func boolToStatus(b bool) string {
	if b {
		return "Connected"
	}
	return "Disconnected"
}

func boolToActive(b bool) string {
	if b {
		return "Active"
	}
	return "Inactive"
}

func boolToEnabled(b bool) string {
	if b {
		return "Enabled"
	}
	return "Disabled"
}
