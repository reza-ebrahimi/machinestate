package collectors

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/load"
	"github.com/shirou/gopsutil/v3/mem"

	"ubuntu-state/models"
)

// CollectOSInfo gathers OS information
func CollectOSInfo() models.OSInfo {
	info, _ := host.Info()

	osInfo := models.OSInfo{
		Architecture: runtime.GOARCH,
	}

	if info != nil {
		osInfo.Name = info.Platform
		osInfo.Version = info.PlatformVersion
		osInfo.Kernel = info.KernelVersion
	}

	// Try to get more detailed OS info from /etc/os-release
	if data, err := os.ReadFile("/etc/os-release"); err == nil {
		lines := strings.Split(string(data), "\n")
		for _, line := range lines {
			if strings.HasPrefix(line, "PRETTY_NAME=") {
				osInfo.Name = strings.Trim(strings.TrimPrefix(line, "PRETTY_NAME="), "\"")
			}
			if strings.HasPrefix(line, "VERSION=") {
				osInfo.Version = strings.Trim(strings.TrimPrefix(line, "VERSION="), "\"")
			}
		}
	}

	return osInfo
}

// CollectSystemInfo gathers CPU, memory, and load information
func CollectSystemInfo() models.SystemInfo {
	info := models.SystemInfo{}

	// Uptime
	if uptime, err := host.Uptime(); err == nil {
		info.Uptime = time.Duration(uptime) * time.Second
		info.UptimeHuman = formatDuration(info.Uptime)
	}

	// Timezone
	info.Timezone = getTimezone()

	// Reboot required check
	if _, err := os.Stat("/var/run/reboot-required"); err == nil {
		info.RebootRequired = true
	}

	// Load average
	if avg, err := load.Avg(); err == nil {
		info.LoadAvg1 = avg.Load1
		info.LoadAvg5 = avg.Load5
		info.LoadAvg15 = avg.Load15
	}

	// CPU
	if cores, err := cpu.Counts(true); err == nil {
		info.CPUCores = cores
	}

	if usage, err := cpu.Percent(time.Second, false); err == nil && len(usage) > 0 {
		info.CPUUsage = usage[0]
	}

	// Memory
	if vmem, err := mem.VirtualMemory(); err == nil {
		info.MemoryTotal = vmem.Total
		info.MemoryUsed = vmem.Used
		info.MemoryFree = vmem.Available
		info.MemoryPercent = vmem.UsedPercent
	}

	// Swap
	if swap, err := mem.SwapMemory(); err == nil {
		info.SwapTotal = swap.Total
		info.SwapUsed = swap.Used
		info.SwapPercent = swap.UsedPercent
	}

	return info
}

// formatDuration formats a duration in human readable format
func formatDuration(d time.Duration) string {
	days := int(d.Hours()) / 24
	hours := int(d.Hours()) % 24
	minutes := int(d.Minutes()) % 60

	if days > 0 {
		return fmt.Sprintf("%dd %dh %dm", days, hours, minutes)
	}
	if hours > 0 {
		return fmt.Sprintf("%dh %dm", hours, minutes)
	}
	return fmt.Sprintf("%dm", minutes)
}

// GetHostname returns the system hostname
func GetHostname() string {
	hostname, err := os.Hostname()
	if err != nil {
		return "unknown"
	}
	return hostname
}

// getTimezone returns the system timezone
func getTimezone() string {
	// Try reading from /etc/timezone first (Debian/Ubuntu)
	if data, err := os.ReadFile("/etc/timezone"); err == nil {
		tz := strings.TrimSpace(string(data))
		if tz != "" {
			return tz
		}
	}

	// Fallback to timedatectl
	cmd := exec.Command("timedatectl", "show", "-p", "Timezone", "--value")
	if output, err := cmd.Output(); err == nil {
		tz := strings.TrimSpace(string(output))
		if tz != "" {
			return tz
		}
	}

	// Final fallback: use Go's local timezone
	return time.Now().Location().String()
}
