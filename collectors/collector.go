package collectors

import (
	"strconv"
	"time"

	"ubuntu-state/models"
)

// CollectAll gathers all system information and returns a complete report
func CollectAll() *models.Report {
	report := &models.Report{
		Timestamp: time.Now(),
		Hostname:  GetHostname(),
		OS:        CollectOSInfo(),
		System:    CollectSystemInfo(),
		Disk:      CollectDiskInfo(),
		Network:   CollectNetworkInfo(),
		Packages:  CollectPackageInfo(),
		Services:  CollectServiceInfo(),
		Security:  CollectSecurityInfo(),
		Hardware:  CollectHardwareInfo(),
		Issues:    []models.Issue{},
	}

	// Analyze and add issues
	report.Issues = analyzeIssues(report)

	return report
}

// analyzeIssues analyzes the report and generates issues
func analyzeIssues(report *models.Report) []models.Issue {
	var issues []models.Issue

	// Check disk usage
	for _, fs := range report.Disk.Filesystems {
		if fs.UsedPercent >= 90 {
			issues = append(issues, models.Issue{
				Severity:    models.SeverityCritical,
				Category:    "Disk",
				Title:       "Disk space critical: " + fs.MountPoint,
				Description: "Filesystem usage is at " + formatPercent(fs.UsedPercent),
				Fix:         "Free up disk space or expand the partition",
			})
		} else if fs.UsedPercent >= 80 {
			issues = append(issues, models.Issue{
				Severity:    models.SeverityWarning,
				Category:    "Disk",
				Title:       "Disk space warning: " + fs.MountPoint,
				Description: "Filesystem usage is at " + formatPercent(fs.UsedPercent),
				Fix:         "Consider cleaning up unused files",
			})
		}

		if fs.InodesPercent >= 90 {
			issues = append(issues, models.Issue{
				Severity:    models.SeverityWarning,
				Category:    "Disk",
				Title:       "Inodes running low: " + fs.MountPoint,
				Description: "Inode usage is at " + formatPercent(fs.InodesPercent),
				Fix:         "Remove small files or directories with many files",
			})
		}
	}

	// Check memory
	if report.System.MemoryPercent >= 90 {
		issues = append(issues, models.Issue{
			Severity:    models.SeverityWarning,
			Category:    "Memory",
			Title:       "High memory usage",
			Description: "Memory usage is at " + formatPercent(report.System.MemoryPercent),
			Fix:         "Close unused applications or add more RAM",
		})
	}

	// Check swap usage
	if report.System.SwapPercent >= 80 {
		issues = append(issues, models.Issue{
			Severity:    models.SeverityWarning,
			Category:    "Memory",
			Title:       "High swap usage",
			Description: "Swap usage is at " + formatPercent(report.System.SwapPercent),
			Fix:         "Consider adding more RAM if swap is frequently used",
		})
	}

	// Check load average
	if report.System.CPUCores > 0 {
		loadPerCore := report.System.LoadAvg1 / float64(report.System.CPUCores)
		if loadPerCore >= 2.0 {
			issues = append(issues, models.Issue{
				Severity:    models.SeverityCritical,
				Category:    "CPU",
				Title:       "System overloaded",
				Description: "Load average is very high relative to CPU cores",
				Fix:         "Identify and stop resource-intensive processes",
			})
		} else if loadPerCore >= 1.0 {
			issues = append(issues, models.Issue{
				Severity:    models.SeverityWarning,
				Category:    "CPU",
				Title:       "High system load",
				Description: "Load average is elevated",
				Fix:         "Monitor CPU-intensive processes",
			})
		}
	}

	// Check failed services
	if len(report.Services.FailedUnits) > 0 {
		issues = append(issues, models.Issue{
			Severity:    models.SeverityWarning,
			Category:    "Services",
			Title:       "Failed systemd services",
			Description: "There are " + formatInt(len(report.Services.FailedUnits)) + " failed service(s)",
			Fix:         "Run: systemctl status <service> to investigate",
		})
	}

	// Check zombie processes
	if report.Services.ZombieCount > 0 {
		issues = append(issues, models.Issue{
			Severity:    models.SeverityInfo,
			Category:    "Processes",
			Title:       "Zombie processes detected",
			Description: "Found " + formatInt(report.Services.ZombieCount) + " zombie process(es)",
			Fix:         "Usually harmless; parent process should clean them up",
		})
	}

	// Check pending updates
	if report.Packages.UpdatesAvailable > 50 {
		issues = append(issues, models.Issue{
			Severity:    models.SeverityWarning,
			Category:    "Packages",
			Title:       "Many pending updates",
			Description: formatInt(report.Packages.UpdatesAvailable) + " packages need updating",
			Fix:         "Run: sudo apt update && sudo apt upgrade",
		})
	} else if report.Packages.UpdatesAvailable > 0 {
		issues = append(issues, models.Issue{
			Severity:    models.SeverityInfo,
			Category:    "Packages",
			Title:       "Updates available",
			Description: formatInt(report.Packages.UpdatesAvailable) + " packages can be updated",
			Fix:         "Run: sudo apt update && sudo apt upgrade",
		})
	}

	// Check security updates
	if report.Packages.SecurityUpdates > 0 {
		issues = append(issues, models.Issue{
			Severity:    models.SeverityWarning,
			Category:    "Security",
			Title:       "Security updates pending",
			Description: formatInt(report.Packages.SecurityUpdates) + " security updates available",
			Fix:         "Run: sudo apt update && sudo apt upgrade",
		})
	}

	// Check firewall
	if !report.Security.FirewallActive {
		issues = append(issues, models.Issue{
			Severity:    models.SeverityWarning,
			Category:    "Security",
			Title:       "Firewall not active",
			Description: "UFW firewall is not enabled",
			Fix:         "Run: sudo ufw enable",
		})
	}

	// Check battery health
	if report.Hardware.Battery != nil && report.Hardware.Battery.Health < 50 {
		issues = append(issues, models.Issue{
			Severity:    models.SeverityCritical,
			Category:    "Hardware",
			Title:       "Battery health degraded",
			Description: "Battery health is at " + formatPercent(report.Hardware.Battery.Health),
			Fix:         "Consider replacing the battery",
		})
	} else if report.Hardware.Battery != nil && report.Hardware.Battery.Health < 80 {
		issues = append(issues, models.Issue{
			Severity:    models.SeverityWarning,
			Category:    "Hardware",
			Title:       "Battery wear detected",
			Description: "Battery health is at " + formatPercent(report.Hardware.Battery.Health),
			Fix:         "Battery showing normal wear; monitor over time",
		})
	}

	// Check temperatures
	for _, temp := range report.Hardware.Temperatures {
		if temp.Critical > 0 && temp.Current >= temp.Critical {
			issues = append(issues, models.Issue{
				Severity:    models.SeverityCritical,
				Category:    "Hardware",
				Title:       "Critical temperature: " + temp.Label,
				Description: "Temperature is " + formatTemp(temp.Current) + " (critical threshold)",
				Fix:         "Check cooling system; reduce load",
			})
		} else if temp.High > 0 && temp.Current >= temp.High {
			issues = append(issues, models.Issue{
				Severity:    models.SeverityWarning,
				Category:    "Hardware",
				Title:       "High temperature: " + temp.Label,
				Description: "Temperature is " + formatTemp(temp.Current),
				Fix:         "Monitor temperature; check cooling",
			})
		} else if temp.Current >= 85 {
			issues = append(issues, models.Issue{
				Severity:    models.SeverityWarning,
				Category:    "Hardware",
				Title:       "Elevated temperature: " + temp.Label,
				Description: "Temperature is " + formatTemp(temp.Current),
				Fix:         "Check cooling system",
			})
		}
	}

	// Check crash reports
	if len(report.Hardware.CrashReports) > 0 {
		issues = append(issues, models.Issue{
			Severity:    models.SeverityWarning,
			Category:    "System",
			Title:       "Crash reports present",
			Description: formatInt(len(report.Hardware.CrashReports)) + " crash report(s) in /var/crash",
			Fix:         "Review with: apport-cli /var/crash/<file>; then remove old reports",
		})
	}

	// Check network connectivity
	if !report.Network.Connectivity {
		issues = append(issues, models.Issue{
			Severity:    models.SeverityWarning,
			Category:    "Network",
			Title:       "No internet connectivity",
			Description: "Unable to reach external DNS servers",
			Fix:         "Check network configuration and connection",
		})
	}

	return issues
}

func formatPercent(p float64) string {
	return strconv.FormatFloat(p, 'f', 1, 64) + "%"
}

func formatInt(i int) string {
	return strconv.Itoa(i)
}

func formatTemp(t float64) string {
	return strconv.FormatFloat(t, 'f', 1, 64) + "°C"
}
