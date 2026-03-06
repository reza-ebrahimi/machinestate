package httpserver

import (
	"fmt"
	"net/http"
	"strings"

	"machinestate/collectors"
)

// handlePrometheus returns metrics in Prometheus exposition format
func handlePrometheus(w http.ResponseWriter, r *http.Request) {
	report := collectors.CollectAll()

	var sb strings.Builder

	// System metrics
	sb.WriteString("# HELP machinestate_cpu_usage_percent CPU usage percentage\n")
	sb.WriteString("# TYPE machinestate_cpu_usage_percent gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_cpu_usage_percent %.2f\n", report.System.CPUUsage))

	sb.WriteString("# HELP machinestate_cpu_cores Number of CPU cores\n")
	sb.WriteString("# TYPE machinestate_cpu_cores gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_cpu_cores %d\n", report.System.CPUCores))

	sb.WriteString("# HELP machinestate_load_average_1m Load average (1 minute)\n")
	sb.WriteString("# TYPE machinestate_load_average_1m gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_load_average_1m %.2f\n", report.System.LoadAvg1))

	sb.WriteString("# HELP machinestate_load_average_5m Load average (5 minutes)\n")
	sb.WriteString("# TYPE machinestate_load_average_5m gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_load_average_5m %.2f\n", report.System.LoadAvg5))

	sb.WriteString("# HELP machinestate_load_average_15m Load average (15 minutes)\n")
	sb.WriteString("# TYPE machinestate_load_average_15m gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_load_average_15m %.2f\n", report.System.LoadAvg15))

	// Memory metrics
	sb.WriteString("# HELP machinestate_memory_total_bytes Total memory in bytes\n")
	sb.WriteString("# TYPE machinestate_memory_total_bytes gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_memory_total_bytes %d\n", report.System.MemoryTotal))

	sb.WriteString("# HELP machinestate_memory_used_bytes Used memory in bytes\n")
	sb.WriteString("# TYPE machinestate_memory_used_bytes gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_memory_used_bytes %d\n", report.System.MemoryUsed))

	sb.WriteString("# HELP machinestate_memory_free_bytes Free memory in bytes\n")
	sb.WriteString("# TYPE machinestate_memory_free_bytes gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_memory_free_bytes %d\n", report.System.MemoryFree))

	sb.WriteString("# HELP machinestate_memory_used_percent Memory usage percentage\n")
	sb.WriteString("# TYPE machinestate_memory_used_percent gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_memory_used_percent %.2f\n", report.System.MemoryPercent))

	sb.WriteString("# HELP machinestate_swap_total_bytes Total swap in bytes\n")
	sb.WriteString("# TYPE machinestate_swap_total_bytes gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_swap_total_bytes %d\n", report.System.SwapTotal))

	sb.WriteString("# HELP machinestate_swap_used_bytes Used swap in bytes\n")
	sb.WriteString("# TYPE machinestate_swap_used_bytes gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_swap_used_bytes %d\n", report.System.SwapUsed))

	sb.WriteString("# HELP machinestate_swap_used_percent Swap usage percentage\n")
	sb.WriteString("# TYPE machinestate_swap_used_percent gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_swap_used_percent %.2f\n", report.System.SwapPercent))

	sb.WriteString("# HELP machinestate_uptime_seconds System uptime in seconds\n")
	sb.WriteString("# TYPE machinestate_uptime_seconds gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_uptime_seconds %d\n", report.System.Uptime/1000000000))

	// Disk metrics
	sb.WriteString("# HELP machinestate_disk_total_bytes Total disk space in bytes\n")
	sb.WriteString("# TYPE machinestate_disk_total_bytes gauge\n")
	sb.WriteString("# HELP machinestate_disk_used_bytes Used disk space in bytes\n")
	sb.WriteString("# TYPE machinestate_disk_used_bytes gauge\n")
	sb.WriteString("# HELP machinestate_disk_free_bytes Free disk space in bytes\n")
	sb.WriteString("# TYPE machinestate_disk_free_bytes gauge\n")
	sb.WriteString("# HELP machinestate_disk_used_percent Disk usage percentage\n")
	sb.WriteString("# TYPE machinestate_disk_used_percent gauge\n")
	for _, fs := range report.Disk.Filesystems {
		mount := sanitizeLabel(fs.MountPoint)
		sb.WriteString(fmt.Sprintf("machinestate_disk_total_bytes{mount=\"%s\"} %d\n", mount, fs.Total))
		sb.WriteString(fmt.Sprintf("machinestate_disk_used_bytes{mount=\"%s\"} %d\n", mount, fs.Used))
		sb.WriteString(fmt.Sprintf("machinestate_disk_free_bytes{mount=\"%s\"} %d\n", mount, fs.Free))
		sb.WriteString(fmt.Sprintf("machinestate_disk_used_percent{mount=\"%s\"} %.2f\n", mount, fs.UsedPercent))
	}

	// Package metrics
	sb.WriteString("# HELP machinestate_packages_updates_available Number of available package updates\n")
	sb.WriteString("# TYPE machinestate_packages_updates_available gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_packages_updates_available %d\n", report.Packages.UpdatesAvailable))

	sb.WriteString("# HELP machinestate_packages_security_updates Number of security updates\n")
	sb.WriteString("# TYPE machinestate_packages_security_updates gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_packages_security_updates %d\n", report.Packages.SecurityUpdates))

	sb.WriteString("# HELP machinestate_packages_broken Number of broken packages\n")
	sb.WriteString("# TYPE machinestate_packages_broken gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_packages_broken %d\n", report.Packages.BrokenPackages))

	// Services metrics
	sb.WriteString("# HELP machinestate_services_failed Number of failed systemd services\n")
	sb.WriteString("# TYPE machinestate_services_failed gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_services_failed %d\n", len(report.Services.FailedUnits)))

	sb.WriteString("# HELP machinestate_processes_zombie Number of zombie processes\n")
	sb.WriteString("# TYPE machinestate_processes_zombie gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_processes_zombie %d\n", report.Services.ZombieCount))

	// Security metrics
	sb.WriteString("# HELP machinestate_security_firewall_active Firewall status (1=active, 0=inactive)\n")
	sb.WriteString("# TYPE machinestate_security_firewall_active gauge\n")
	firewallValue := 0
	if report.Security.FirewallActive {
		firewallValue = 1
	}
	sb.WriteString(fmt.Sprintf("machinestate_security_firewall_active %d\n", firewallValue))

	sb.WriteString("# HELP machinestate_security_failed_logins Failed login attempts in last 24h\n")
	sb.WriteString("# TYPE machinestate_security_failed_logins gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_security_failed_logins %d\n", report.Security.FailedLogins24h))

	// Hardware metrics
	if report.Hardware.Battery != nil {
		sb.WriteString("# HELP machinestate_battery_capacity_percent Battery capacity percentage\n")
		sb.WriteString("# TYPE machinestate_battery_capacity_percent gauge\n")
		sb.WriteString(fmt.Sprintf("machinestate_battery_capacity_percent %.1f\n", report.Hardware.Battery.Capacity))

		sb.WriteString("# HELP machinestate_battery_health_percent Battery health percentage\n")
		sb.WriteString("# TYPE machinestate_battery_health_percent gauge\n")
		sb.WriteString(fmt.Sprintf("machinestate_battery_health_percent %.1f\n", report.Hardware.Battery.Health))
	}

	sb.WriteString("# HELP machinestate_temperature_celsius Temperature readings\n")
	sb.WriteString("# TYPE machinestate_temperature_celsius gauge\n")
	for _, temp := range report.Hardware.Temperatures {
		label := sanitizeLabel(temp.Label)
		sb.WriteString(fmt.Sprintf("machinestate_temperature_celsius{sensor=\"%s\"} %.1f\n", label, temp.Current))
	}

	// Docker metrics
	if report.Docker.Available {
		sb.WriteString("# HELP machinestate_docker_containers_running Number of running containers\n")
		sb.WriteString("# TYPE machinestate_docker_containers_running gauge\n")
		sb.WriteString(fmt.Sprintf("machinestate_docker_containers_running %d\n", report.Docker.RunningCount))

		sb.WriteString("# HELP machinestate_docker_containers_stopped Number of stopped containers\n")
		sb.WriteString("# TYPE machinestate_docker_containers_stopped gauge\n")
		sb.WriteString(fmt.Sprintf("machinestate_docker_containers_stopped %d\n", report.Docker.StoppedCount))

		sb.WriteString("# HELP machinestate_docker_images Number of Docker images\n")
		sb.WriteString("# TYPE machinestate_docker_images gauge\n")
		sb.WriteString(fmt.Sprintf("machinestate_docker_images %d\n", report.Docker.ImageCount))
	}

	// GPU metrics
	if report.GPU.Available {
		sb.WriteString("# HELP machinestate_gpu_temperature_celsius GPU temperature\n")
		sb.WriteString("# TYPE machinestate_gpu_temperature_celsius gauge\n")
		sb.WriteString("# HELP machinestate_gpu_utilization_percent GPU utilization percentage\n")
		sb.WriteString("# TYPE machinestate_gpu_utilization_percent gauge\n")
		sb.WriteString("# HELP machinestate_gpu_memory_used_bytes GPU memory used\n")
		sb.WriteString("# TYPE machinestate_gpu_memory_used_bytes gauge\n")
		sb.WriteString("# HELP machinestate_gpu_memory_total_bytes GPU memory total\n")
		sb.WriteString("# TYPE machinestate_gpu_memory_total_bytes gauge\n")
		for _, gpu := range report.GPU.GPUs {
			name := sanitizeLabel(gpu.Name)
			sb.WriteString(fmt.Sprintf("machinestate_gpu_temperature_celsius{gpu=\"%s\"} %d\n", name, gpu.Temperature))
			sb.WriteString(fmt.Sprintf("machinestate_gpu_utilization_percent{gpu=\"%s\"} %d\n", name, gpu.Utilization))
			sb.WriteString(fmt.Sprintf("machinestate_gpu_memory_used_bytes{gpu=\"%s\"} %d\n", name, gpu.MemoryUsed))
			sb.WriteString(fmt.Sprintf("machinestate_gpu_memory_total_bytes{gpu=\"%s\"} %d\n", name, gpu.MemoryTotal))
		}
	}

	// Log metrics
	if report.Logs.Available {
		sb.WriteString("# HELP machinestate_logs_errors Error count in last 24h\n")
		sb.WriteString("# TYPE machinestate_logs_errors gauge\n")
		sb.WriteString(fmt.Sprintf("machinestate_logs_errors %d\n", report.Logs.Stats.ErrorCount))

		sb.WriteString("# HELP machinestate_logs_warnings Warning count in last 24h\n")
		sb.WriteString("# TYPE machinestate_logs_warnings gauge\n")
		sb.WriteString(fmt.Sprintf("machinestate_logs_warnings %d\n", report.Logs.Stats.WarningCount))

		sb.WriteString("# HELP machinestate_logs_critical Critical count in last 24h\n")
		sb.WriteString("# TYPE machinestate_logs_critical gauge\n")
		sb.WriteString(fmt.Sprintf("machinestate_logs_critical %d\n", report.Logs.Stats.CriticalCount))

		sb.WriteString("# HELP machinestate_logs_oom_events OOM events in last 24h\n")
		sb.WriteString("# TYPE machinestate_logs_oom_events gauge\n")
		sb.WriteString(fmt.Sprintf("machinestate_logs_oom_events %d\n", report.Logs.Stats.OOMEvents))

		sb.WriteString("# HELP machinestate_logs_kernel_panics Kernel panics in last 24h\n")
		sb.WriteString("# TYPE machinestate_logs_kernel_panics gauge\n")
		sb.WriteString(fmt.Sprintf("machinestate_logs_kernel_panics %d\n", report.Logs.Stats.KernelPanics))
	}

	// Issues metrics
	criticalCount := 0
	warningCount := 0
	infoCount := 0
	for _, issue := range report.Issues {
		switch issue.Severity {
		case "critical":
			criticalCount++
		case "warning":
			warningCount++
		case "info":
			infoCount++
		}
	}

	sb.WriteString("# HELP machinestate_issues_total Total issues by severity\n")
	sb.WriteString("# TYPE machinestate_issues_total gauge\n")
	sb.WriteString(fmt.Sprintf("machinestate_issues_total{severity=\"critical\"} %d\n", criticalCount))
	sb.WriteString(fmt.Sprintf("machinestate_issues_total{severity=\"warning\"} %d\n", warningCount))
	sb.WriteString(fmt.Sprintf("machinestate_issues_total{severity=\"info\"} %d\n", infoCount))

	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	w.Write([]byte(sb.String()))
}

// sanitizeLabel sanitizes a string for use as a Prometheus label value
func sanitizeLabel(s string) string {
	// Replace characters that need escaping in Prometheus labels
	s = strings.ReplaceAll(s, "\\", "\\\\")
	s = strings.ReplaceAll(s, "\"", "\\\"")
	s = strings.ReplaceAll(s, "\n", "\\n")
	return s
}
