package httpserver

import (
	"encoding/json"
	"net/http"
	"strings"

	"machinestate/collectors"
	"machinestate/config"
	"machinestate/models"
	"machinestate/outputs"
)

// writeJSON writes a JSON response
func writeJSON(w http.ResponseWriter, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	encoder := json.NewEncoder(w)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(data); err != nil {
		http.Error(w, `{"error":"Failed to encode JSON"}`, http.StatusInternalServerError)
	}
}

// writeError writes a JSON error response
func writeError(w http.ResponseWriter, message string, code int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]string{"error": message})
}

// handleHealth returns a simple health check response
func handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]string{"status": "ok"})
}

// handleReport returns the full system report
func handleReport(w http.ResponseWriter, r *http.Request) {
	report := collectors.CollectAll()
	writeJSON(w, report)
}

// handleIssues returns detected issues with optional severity filter
func handleIssues(w http.ResponseWriter, r *http.Request) {
	report := collectors.CollectAll()

	severityFilter := strings.ToLower(r.URL.Query().Get("severity"))

	var filtered []models.Issue
	for _, issue := range report.Issues {
		if severityFilter == "" || issue.Severity == severityFilter {
			filtered = append(filtered, issue)
		}
	}

	writeJSON(w, filtered)
}

// handleSystem returns CPU, memory, load information
func handleSystem(w http.ResponseWriter, r *http.Request) {
	systemInfo := collectors.CollectSystemInfo()
	writeJSON(w, systemInfo)
}

// handleDisk returns filesystem usage with optional mount point filter
func handleDisk(w http.ResponseWriter, r *http.Request) {
	diskInfo := collectors.CollectDiskInfo()

	mountFilter := r.URL.Query().Get("mount")
	if mountFilter != "" {
		var filtered []models.Filesystem
		for _, fs := range diskInfo.Filesystems {
			if fs.MountPoint == mountFilter {
				filtered = append(filtered, fs)
			}
		}
		if len(filtered) == 0 {
			writeError(w, "Mount point not found: "+mountFilter, http.StatusNotFound)
			return
		}
		diskInfo.Filesystems = filtered
	}

	writeJSON(w, diskInfo)
}

// handleNetwork returns network interfaces and ports
func handleNetwork(w http.ResponseWriter, r *http.Request) {
	networkInfo := collectors.CollectNetworkInfo()
	writeJSON(w, networkInfo)
}

// handlePackages returns APT package status
func handlePackages(w http.ResponseWriter, r *http.Request) {
	packageInfo := collectors.CollectPackageInfo()
	writeJSON(w, packageInfo)
}

// handleServices returns systemd service status
func handleServices(w http.ResponseWriter, r *http.Request) {
	serviceInfo := collectors.CollectServiceInfo()
	writeJSON(w, serviceInfo)
}

// handleSecurity returns security information
func handleSecurity(w http.ResponseWriter, r *http.Request) {
	securityInfo := collectors.CollectSecurityInfo()
	writeJSON(w, securityInfo)
}

// handleHardware returns hardware information
func handleHardware(w http.ResponseWriter, r *http.Request) {
	hardwareInfo := collectors.CollectHardwareInfo()
	writeJSON(w, hardwareInfo)
}

// handleDocker returns Docker container and image information
func handleDocker(w http.ResponseWriter, r *http.Request) {
	dockerInfo := collectors.CollectDockerInfo()
	writeJSON(w, dockerInfo)
}

// handleSnaps returns Snap package information
func handleSnaps(w http.ResponseWriter, r *http.Request) {
	snapInfo := collectors.CollectSnapInfo()
	writeJSON(w, snapInfo)
}

// handleGPU returns GPU information
func handleGPU(w http.ResponseWriter, r *http.Request) {
	gpuInfo := collectors.CollectGPUInfo()
	writeJSON(w, gpuInfo)
}

// handleLogs returns log analysis information
func handleLogs(w http.ResponseWriter, r *http.Request) {
	logInfo := collectors.CollectLogInfo()
	writeJSON(w, logInfo)
}

// handleConfig returns current configuration thresholds
func handleConfig(w http.ResponseWriter, r *http.Request) {
	cfg := config.Current
	if cfg == nil {
		cfg = config.DefaultConfig()
	}
	writeJSON(w, map[string]interface{}{
		"disk_warning_percent":    cfg.DiskWarningPercent,
		"disk_critical_percent":   cfg.DiskCriticalPercent,
		"memory_warning_percent":  cfg.MemoryWarningPercent,
		"battery_health_warning":  cfg.BatteryHealthWarning,
		"battery_health_critical": cfg.BatteryHealthCritical,
		"uptime_warning_days":     cfg.UptimeWarningDays,
		"gpu_temp_warning":        cfg.GPUTempWarning,
		"gpu_temp_critical":       cfg.GPUTempCritical,
	})
}

// handleDashboard serves the HTML dashboard at "/"
func handleDashboard(w http.ResponseWriter, r *http.Request) {
	// Only serve dashboard at exact "/" path
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	report := collectors.CollectAll()
	html, err := outputs.RenderHTML(report)
	if err != nil {
		http.Error(w, "Failed to generate dashboard", http.StatusInternalServerError)
		return
	}

	// Add auto-refresh meta tag (30 seconds)
	html = strings.Replace(html, "<head>",
		`<head><meta http-equiv="refresh" content="30">`, 1)

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(html))
}
