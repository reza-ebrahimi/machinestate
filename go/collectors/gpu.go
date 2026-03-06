package collectors

import (
	"os/exec"
	"strconv"
	"strings"

	"machinestate/models"
)

// CollectGPUInfo gathers GPU information
func CollectGPUInfo() models.GPUInfo {
	info := models.GPUInfo{
		GPUs: []models.GPUDevice{},
	}

	// Try NVIDIA first
	if gpus := getNvidiaGPUs(); len(gpus) > 0 {
		info.Available = true
		info.GPUs = gpus
		return info
	}

	// Try AMD
	if gpus := getAMDGPUs(); len(gpus) > 0 {
		info.Available = true
		info.GPUs = gpus
		return info
	}

	// Fallback to lspci detection
	if gpus := detectGPUsFromLspci(); len(gpus) > 0 {
		info.Available = true
		info.GPUs = gpus
		return info
	}

	return info
}

func getNvidiaGPUs() []models.GPUDevice {
	var gpus []models.GPUDevice

	// Check if nvidia-smi is available
	if _, err := exec.LookPath("nvidia-smi"); err != nil {
		return gpus
	}

	// Query GPU info
	cmd := exec.Command("nvidia-smi",
		"--query-gpu=index,name,temperature.gpu,utilization.gpu,memory.used,memory.total,power.draw",
		"--format=csv,noheader,nounits")
	output, err := cmd.Output()
	if err != nil {
		return gpus
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	for _, line := range lines {
		if line == "" {
			continue
		}

		fields := strings.Split(line, ", ")
		if len(fields) < 7 {
			continue
		}

		index, _ := strconv.Atoi(strings.TrimSpace(fields[0]))
		temp, _ := strconv.Atoi(strings.TrimSpace(fields[2]))
		util, _ := strconv.Atoi(strings.TrimSpace(fields[3]))
		memUsed, _ := strconv.ParseInt(strings.TrimSpace(fields[4]), 10, 64)
		memTotal, _ := strconv.ParseInt(strings.TrimSpace(fields[5]), 10, 64)
		power, _ := strconv.ParseFloat(strings.TrimSpace(fields[6]), 64)

		gpu := models.GPUDevice{
			Index:       index,
			Name:        strings.TrimSpace(fields[1]),
			Vendor:      "nvidia",
			Temperature: temp,
			Utilization: util,
			MemoryUsed:  memUsed * 1024 * 1024, // MiB to bytes
			MemoryTotal: memTotal * 1024 * 1024,
			PowerDraw:   power,
		}

		gpus = append(gpus, gpu)
	}

	return gpus
}

func getAMDGPUs() []models.GPUDevice {
	var gpus []models.GPUDevice

	// Check if rocm-smi is available
	if _, err := exec.LookPath("rocm-smi"); err != nil {
		return gpus
	}

	// Get temperature
	cmd := exec.Command("rocm-smi", "--showtemp", "--csv")
	tempOutput, err := cmd.Output()
	if err != nil {
		return gpus
	}

	// Parse temperature output
	tempMap := make(map[int]int)
	lines := strings.Split(string(tempOutput), "\n")
	for i, line := range lines {
		if i == 0 || line == "" {
			continue
		}
		fields := strings.Split(line, ",")
		if len(fields) >= 2 {
			idx, _ := strconv.Atoi(strings.TrimSpace(fields[0]))
			temp, _ := strconv.ParseFloat(strings.TrimSpace(fields[1]), 64)
			tempMap[idx] = int(temp)
		}
	}

	// Get utilization
	cmd = exec.Command("rocm-smi", "--showuse", "--csv")
	useOutput, err := cmd.Output()
	if err != nil {
		return gpus
	}

	useMap := make(map[int]int)
	lines = strings.Split(string(useOutput), "\n")
	for i, line := range lines {
		if i == 0 || line == "" {
			continue
		}
		fields := strings.Split(line, ",")
		if len(fields) >= 2 {
			idx, _ := strconv.Atoi(strings.TrimSpace(fields[0]))
			use, _ := strconv.ParseFloat(strings.TrimSpace(fields[1]), 64)
			useMap[idx] = int(use)
		}
	}

	// Get memory usage
	cmd = exec.Command("rocm-smi", "--showmemuse", "--csv")
	memOutput, err := cmd.Output()
	if err != nil {
		return gpus
	}

	lines = strings.Split(string(memOutput), "\n")
	for i, line := range lines {
		if i == 0 || line == "" {
			continue
		}
		fields := strings.Split(line, ",")
		if len(fields) >= 2 {
			idx, _ := strconv.Atoi(strings.TrimSpace(fields[0]))

			gpu := models.GPUDevice{
				Index:       idx,
				Name:        "AMD GPU " + strconv.Itoa(idx),
				Vendor:      "amd",
				Temperature: tempMap[idx],
				Utilization: useMap[idx],
			}

			gpus = append(gpus, gpu)
		}
	}

	return gpus
}

func detectGPUsFromLspci() []models.GPUDevice {
	var gpus []models.GPUDevice

	// Check if lspci is available
	if _, err := exec.LookPath("lspci"); err != nil {
		return gpus
	}

	cmd := exec.Command("lspci")
	output, err := cmd.Output()
	if err != nil {
		return gpus
	}

	lines := strings.Split(string(output), "\n")
	index := 0
	for _, line := range lines {
		lineLower := strings.ToLower(line)
		if strings.Contains(lineLower, "vga") || strings.Contains(lineLower, "3d") || strings.Contains(lineLower, "display") {
			// Extract GPU name
			parts := strings.SplitN(line, ":", 3)
			name := "Unknown GPU"
			if len(parts) >= 3 {
				name = strings.TrimSpace(parts[2])
			}

			vendor := "unknown"
			if strings.Contains(lineLower, "nvidia") {
				vendor = "nvidia"
			} else if strings.Contains(lineLower, "amd") || strings.Contains(lineLower, "radeon") {
				vendor = "amd"
			} else if strings.Contains(lineLower, "intel") {
				vendor = "intel"
			}

			gpu := models.GPUDevice{
				Index:  index,
				Name:   name,
				Vendor: vendor,
				// Temperature, utilization, memory not available via lspci
			}

			gpus = append(gpus, gpu)
			index++
		}
	}

	return gpus
}
