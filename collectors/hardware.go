package collectors

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"ubuntu-state/models"
)

// CollectHardwareInfo gathers hardware health information
func CollectHardwareInfo() models.HardwareInfo {
	info := models.HardwareInfo{
		Temperatures: []models.TemperatureInfo{},
		CrashReports: []string{},
	}

	// Battery info
	battery := collectBatteryInfo()
	if battery != nil && battery.Present {
		info.Battery = battery
	}

	// Temperature sensors from thermal zones
	thermalZones, _ := filepath.Glob("/sys/class/thermal/thermal_zone*/temp")
	for _, zone := range thermalZones {
		data, err := os.ReadFile(zone)
		if err == nil {
			temp, err := strconv.ParseFloat(strings.TrimSpace(string(data)), 64)
			if err == nil {
				zoneDir := filepath.Dir(zone)
				zoneName := filepath.Base(zoneDir)

				// Try to get the zone type for a better label
				if typeData, err := os.ReadFile(filepath.Join(zoneDir, "type")); err == nil {
					zoneName = strings.TrimSpace(string(typeData))
				}

				info.Temperatures = append(info.Temperatures, models.TemperatureInfo{
					Label:   zoneName,
					Current: temp / 1000, // Convert from millidegrees
				})
			}
		}
	}

	// Also try hwmon sensors
	hwmonDirs, _ := filepath.Glob("/sys/class/hwmon/hwmon*/temp*_input")
	for _, tempFile := range hwmonDirs {
		data, err := os.ReadFile(tempFile)
		if err == nil {
			temp, err := strconv.ParseFloat(strings.TrimSpace(string(data)), 64)
			if err == nil {
				// Try to get sensor label
				labelFile := strings.Replace(tempFile, "_input", "_label", 1)
				label := filepath.Base(filepath.Dir(tempFile))
				if labelData, err := os.ReadFile(labelFile); err == nil {
					label = strings.TrimSpace(string(labelData))
				}

				info.Temperatures = append(info.Temperatures, models.TemperatureInfo{
					Label:   label,
					Current: temp / 1000, // Convert from millidegrees
				})
			}
		}
	}

	// Crash reports
	crashDir := "/var/crash"
	entries, err := os.ReadDir(crashDir)
	if err == nil {
		for _, entry := range entries {
			if strings.HasSuffix(entry.Name(), ".crash") {
				info.CrashReports = append(info.CrashReports, entry.Name())
			}
		}
	}

	return info
}

// collectBatteryInfo reads battery information from sysfs
func collectBatteryInfo() *models.BatteryInfo {
	batteryPath := "/sys/class/power_supply/BAT0"
	if _, err := os.Stat(batteryPath); os.IsNotExist(err) {
		batteryPath = "/sys/class/power_supply/BAT1"
		if _, err := os.Stat(batteryPath); os.IsNotExist(err) {
			return nil
		}
	}

	battery := &models.BatteryInfo{Present: true}

	// Status
	if data, err := os.ReadFile(filepath.Join(batteryPath, "status")); err == nil {
		battery.Status = strings.TrimSpace(string(data))
	}

	// Capacity (current percentage)
	if data, err := os.ReadFile(filepath.Join(batteryPath, "capacity")); err == nil {
		battery.Capacity, _ = strconv.ParseFloat(strings.TrimSpace(string(data)), 64)
	}

	// Cycle count
	if data, err := os.ReadFile(filepath.Join(batteryPath, "cycle_count")); err == nil {
		battery.CycleCount, _ = strconv.Atoi(strings.TrimSpace(string(data)))
	}

	// Design capacity (in microWh)
	if data, err := os.ReadFile(filepath.Join(batteryPath, "energy_full_design")); err == nil {
		val, _ := strconv.ParseFloat(strings.TrimSpace(string(data)), 64)
		battery.DesignCapacity = val / 1000000 // Convert to Wh
	}

	// Current full capacity (in microWh)
	if data, err := os.ReadFile(filepath.Join(batteryPath, "energy_full")); err == nil {
		val, _ := strconv.ParseFloat(strings.TrimSpace(string(data)), 64)
		battery.FullCapacity = val / 1000000 // Convert to Wh
	}

	// Calculate health percentage
	if battery.DesignCapacity > 0 {
		battery.Health = (battery.FullCapacity / battery.DesignCapacity) * 100
	}

	return battery
}
