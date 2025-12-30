package models

import "time"

// Report represents the complete system state report
type Report struct {
	Timestamp time.Time     `json:"timestamp"`
	Hostname  string        `json:"hostname"`
	OS        OSInfo        `json:"os"`
	System    SystemInfo    `json:"system"`
	Disk      DiskInfo      `json:"disk"`
	Network   NetworkInfo   `json:"network"`
	Packages  PackageInfo   `json:"packages"`
	Services  ServiceInfo   `json:"services"`
	Security  SecurityInfo  `json:"security"`
	Hardware  HardwareInfo  `json:"hardware"`
	Docker    DockerInfo    `json:"docker"`
	Snaps     SnapInfo      `json:"snaps"`
	GPU       GPUInfo       `json:"gpu"`
	Logs      LogInfo       `json:"logs"`
	Issues    []Issue       `json:"issues"`
}

// OSInfo contains OS details
type OSInfo struct {
	Name         string `json:"name"`
	Version      string `json:"version"`
	Kernel       string `json:"kernel"`
	Architecture string `json:"architecture"`
}

// SystemInfo contains CPU, memory, and load information
type SystemInfo struct {
	Uptime         time.Duration `json:"uptime"`
	UptimeHuman    string        `json:"uptime_human"`
	Timezone       string        `json:"timezone"`
	RebootRequired bool          `json:"reboot_required"`
	LoadAvg1       float64       `json:"load_avg_1"`
	LoadAvg5       float64       `json:"load_avg_5"`
	LoadAvg15      float64       `json:"load_avg_15"`
	CPUCores       int           `json:"cpu_cores"`
	CPUUsage       float64       `json:"cpu_usage"`
	MemoryTotal    uint64        `json:"memory_total"`
	MemoryUsed     uint64        `json:"memory_used"`
	MemoryFree     uint64        `json:"memory_free"`
	MemoryPercent  float64       `json:"memory_percent"`
	SwapTotal      uint64        `json:"swap_total"`
	SwapUsed       uint64        `json:"swap_used"`
	SwapPercent    float64       `json:"swap_percent"`
}

// DiskInfo contains filesystem information
type DiskInfo struct {
	Filesystems []Filesystem `json:"filesystems"`
}

// Filesystem represents a mounted filesystem
type Filesystem struct {
	Device      string  `json:"device"`
	MountPoint  string  `json:"mount_point"`
	FSType      string  `json:"fs_type"`
	Total       uint64  `json:"total"`
	Used        uint64  `json:"used"`
	Free        uint64  `json:"free"`
	UsedPercent float64 `json:"used_percent"`
	InodesTotal uint64  `json:"inodes_total"`
	InodesUsed  uint64  `json:"inodes_used"`
	InodesFree  uint64  `json:"inodes_free"`
	InodesPercent float64 `json:"inodes_percent"`
}

// NetworkInfo contains network interface and connectivity info
type NetworkInfo struct {
	Interfaces   []NetworkInterface `json:"interfaces"`
	ListenPorts  []ListenPort       `json:"listen_ports"`
	Connectivity bool               `json:"connectivity"`
	PublicIP     string             `json:"public_ip,omitempty"`
}

// NetworkInterface represents a network interface
type NetworkInterface struct {
	Name    string   `json:"name"`
	State   string   `json:"state"`
	MAC     string   `json:"mac"`
	IPs     []string `json:"ips"`
	RxBytes uint64   `json:"rx_bytes"`
	TxBytes uint64   `json:"tx_bytes"`
}

// ListenPort represents a listening port
type ListenPort struct {
	Protocol string `json:"protocol"`
	Address  string `json:"address"`
	Port     uint32 `json:"port"`
	Process  string `json:"process"`
	PID      int32  `json:"pid"`
}

// PackageInfo contains package manager information
type PackageInfo struct {
	UpdatesAvailable int      `json:"updates_available"`
	UpdatesList      []string `json:"updates_list,omitempty"`
	SecurityUpdates  int      `json:"security_updates"`
	BrokenPackages   int      `json:"broken_packages"`
	HeldPackages     []string `json:"held_packages,omitempty"`
}

// ServiceInfo contains systemd service information
type ServiceInfo struct {
	FailedUnits    []string      `json:"failed_units"`
	ZombieCount    int           `json:"zombie_count"`
	TopCPU         []ProcessInfo `json:"top_cpu"`
	TopMemory      []ProcessInfo `json:"top_memory"`
}

// ProcessInfo represents a process
type ProcessInfo struct {
	PID     int32   `json:"pid"`
	Name    string  `json:"name"`
	CPU     float64 `json:"cpu"`
	Memory  float32 `json:"memory"`
	User    string  `json:"user"`
}

// SecurityInfo contains security-related information
type SecurityInfo struct {
	FirewallActive   bool     `json:"firewall_active"`
	FirewallStatus   string   `json:"firewall_status"`
	FailedLogins24h  int      `json:"failed_logins_24h"`
	OpenPorts        []string `json:"open_ports"`
	SSHEnabled       bool     `json:"ssh_enabled"`
}

// HardwareInfo contains hardware health information
type HardwareInfo struct {
	Battery      *BatteryInfo     `json:"battery,omitempty"`
	Temperatures []TemperatureInfo `json:"temperatures,omitempty"`
	CrashReports []string         `json:"crash_reports,omitempty"`
}

// BatteryInfo represents battery status
type BatteryInfo struct {
	Present       bool    `json:"present"`
	Status        string  `json:"status"`
	Capacity      float64 `json:"capacity"`
	Health        float64 `json:"health"`
	CycleCount    int     `json:"cycle_count"`
	DesignCapacity float64 `json:"design_capacity"`
	FullCapacity  float64 `json:"full_capacity"`
}

// TemperatureInfo represents a temperature sensor
type TemperatureInfo struct {
	Label    string  `json:"label"`
	Current  float64 `json:"current"`
	High     float64 `json:"high,omitempty"`
	Critical float64 `json:"critical,omitempty"`
}

// DockerInfo contains Docker container and image information
type DockerInfo struct {
	Available      bool            `json:"available"`
	DaemonRunning  bool            `json:"daemon_running"`
	Containers     []ContainerInfo `json:"containers,omitempty"`
	RunningCount   int             `json:"running_count"`
	StoppedCount   int             `json:"stopped_count"`
	ImageCount     int             `json:"image_count"`
	TotalImageSize int64           `json:"total_image_size"`
	DanglingImages int64           `json:"dangling_images_size"`
}

// ContainerInfo represents a Docker container
type ContainerInfo struct {
	Name          string  `json:"name"`
	Image         string  `json:"image"`
	Status        string  `json:"status"`
	State         string  `json:"state"`
	Created       string  `json:"created"`
	CPUPercent    float64 `json:"cpu_percent"`
	MemoryPercent float64 `json:"memory_percent"`
}

// SnapInfo contains Snap package information
type SnapInfo struct {
	Available        bool          `json:"available"`
	Snaps            []SnapPackage `json:"snaps,omitempty"`
	TotalDiskUsage   int64         `json:"total_disk_usage"`
	PendingRefreshes int           `json:"pending_refreshes"`
}

// SnapPackage represents an installed snap
type SnapPackage struct {
	Name      string `json:"name"`
	Version   string `json:"version"`
	Revision  string `json:"revision"`
	Publisher string `json:"publisher"`
	DiskUsage int64  `json:"disk_usage"`
}

// GPUInfo contains GPU information
type GPUInfo struct {
	Available bool        `json:"available"`
	GPUs      []GPUDevice `json:"gpus,omitempty"`
}

// GPUDevice represents a GPU
type GPUDevice struct {
	Index       int     `json:"index"`
	Name        string  `json:"name"`
	Vendor      string  `json:"vendor"`
	Temperature int     `json:"temperature"`
	Utilization int     `json:"utilization"`
	MemoryUsed  int64   `json:"memory_used"`
	MemoryTotal int64   `json:"memory_total"`
	PowerDraw   float64 `json:"power_draw"`
}

// LogInfo contains log analysis information
type LogInfo struct {
	Available bool     `json:"available"`
	Period    string   `json:"period"`
	Stats     LogStats `json:"stats"`
}

// LogStats contains log statistics
type LogStats struct {
	ErrorCount    int            `json:"error_count"`
	WarningCount  int            `json:"warning_count"`
	CriticalCount int            `json:"critical_count"`
	OOMEvents     int            `json:"oom_events"`
	KernelPanics  int            `json:"kernel_panics"`
	Segfaults     int            `json:"segfaults"`
	TopErrors     []ErrorPattern `json:"top_errors,omitempty"`
}

// ErrorPattern represents a frequent error pattern
type ErrorPattern struct {
	Pattern string `json:"pattern"`
	Count   int    `json:"count"`
}

// Issue represents a detected problem
type Issue struct {
	Severity    string `json:"severity"` // critical, warning, info
	Category    string `json:"category"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Fix         string `json:"fix,omitempty"`
}

// Severity constants
const (
	SeverityCritical = "critical"
	SeverityWarning  = "warning"
	SeverityInfo     = "info"
)
