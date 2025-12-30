package config

import (
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

// Config holds all configurable thresholds
type Config struct {
	DiskWarningPercent    int `yaml:"disk_warning_percent"`
	DiskCriticalPercent   int `yaml:"disk_critical_percent"`
	MemoryWarningPercent  int `yaml:"memory_warning_percent"`
	BatteryHealthWarning  int `yaml:"battery_health_warning"`
	BatteryHealthCritical int `yaml:"battery_health_critical"`
	UptimeWarningDays     int `yaml:"uptime_warning_days"`
	GPUTempWarning        int `yaml:"gpu_temp_warning"`
	GPUTempCritical       int `yaml:"gpu_temp_critical"`
}

// Current holds the active configuration (global variable)
var Current *Config

// DefaultConfig returns a Config with default values
func DefaultConfig() *Config {
	return &Config{
		DiskWarningPercent:    80,
		DiskCriticalPercent:   90,
		MemoryWarningPercent:  90,
		BatteryHealthWarning:  80,
		BatteryHealthCritical: 50,
		UptimeWarningDays:     30,
		GPUTempWarning:        80,
		GPUTempCritical:       90,
	}
}

// GetConfigPath returns the default config file path
func GetConfigPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".config", "ubuntu-state", "config.yaml")
}

// LoadConfig loads configuration from a file, returning defaults on error
func LoadConfig(path string) (*Config, error) {
	cfg := DefaultConfig()

	data, err := os.ReadFile(path)
	if err != nil {
		return cfg, err
	}

	if err := yaml.Unmarshal(data, cfg); err != nil {
		return DefaultConfig(), err
	}

	return cfg, nil
}

// Init initializes the global Current config
// If path is empty, uses the default config path
// Falls back to defaults if file doesn't exist or can't be parsed
func Init(path string) {
	if path == "" {
		path = GetConfigPath()
	}

	cfg, err := LoadConfig(path)
	if err != nil {
		// File doesn't exist or can't be read - use defaults
		cfg = DefaultConfig()
	}

	Current = cfg
}
