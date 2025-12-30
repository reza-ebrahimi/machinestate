package collectors

import (
	"os/exec"
	"sort"
	"strings"

	"github.com/shirou/gopsutil/v3/process"

	"ubuntu-state/models"
)

// CollectServiceInfo gathers systemd service and process information
func CollectServiceInfo() models.ServiceInfo {
	info := models.ServiceInfo{
		FailedUnits: []string{},
		TopCPU:      []models.ProcessInfo{},
		TopMemory:   []models.ProcessInfo{},
	}

	// Get failed systemd units
	cmd := exec.Command("systemctl", "--failed", "--no-pager", "--no-legend")
	output, err := cmd.Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}
			// First field is the unit name
			fields := strings.Fields(line)
			if len(fields) > 0 {
				info.FailedUnits = append(info.FailedUnits, fields[0])
			}
		}
	}

	// Get all processes
	procs, err := process.Processes()
	if err != nil {
		return info
	}

	var procInfos []models.ProcessInfo
	for _, p := range procs {
		status, err := p.Status()
		if err == nil {
			// Count zombies
			for _, s := range status {
				if s == "Z" {
					info.ZombieCount++
				}
			}
		}

		name, _ := p.Name()
		cpu, _ := p.CPUPercent()
		mem, _ := p.MemoryPercent()
		user, _ := p.Username()

		procInfos = append(procInfos, models.ProcessInfo{
			PID:    p.Pid,
			Name:   name,
			CPU:    cpu,
			Memory: mem,
			User:   user,
		})
	}

	// Sort by CPU and get top 5
	sort.Slice(procInfos, func(i, j int) bool {
		return procInfos[i].CPU > procInfos[j].CPU
	})
	for i := 0; i < 5 && i < len(procInfos); i++ {
		info.TopCPU = append(info.TopCPU, procInfos[i])
	}

	// Sort by memory and get top 5
	sort.Slice(procInfos, func(i, j int) bool {
		return procInfos[i].Memory > procInfos[j].Memory
	})
	for i := 0; i < 5 && i < len(procInfos); i++ {
		info.TopMemory = append(info.TopMemory, procInfos[i])
	}

	return info
}
