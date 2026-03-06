package collectors

import (
	"encoding/json"
	"os/exec"
	"strconv"
	"strings"

	"machinestate/models"
)

// dockerContainer represents the JSON output from docker ps
type dockerContainer struct {
	Names  string `json:"Names"`
	Image  string `json:"Image"`
	Status string `json:"Status"`
	State  string `json:"State"`
	// RunningFor is available in docker ps --format
	CreatedAt string `json:"CreatedAt"`
}

// dockerImage represents the JSON output from docker images
type dockerImage struct {
	Size string `json:"Size"`
}

// dockerDiskUsage represents the JSON output from docker system df
type dockerDFOutput struct {
	Type        string `json:"Type"`
	TotalCount  int    `json:"TotalCount"`
	Size        string `json:"Size"`
	Reclaimable string `json:"Reclaimable"`
}

// CollectDockerInfo gathers Docker container and image information
func CollectDockerInfo() models.DockerInfo {
	info := models.DockerInfo{
		Containers: []models.ContainerInfo{},
	}

	// Check if docker is available
	if _, err := exec.LookPath("docker"); err != nil {
		return info
	}
	info.Available = true

	// Check if daemon is running
	cmd := exec.Command("docker", "info")
	if err := cmd.Run(); err != nil {
		info.Available = true
		info.DaemonRunning = false
		return info
	}
	info.DaemonRunning = true

	// Get running containers
	info.Containers, info.RunningCount = getContainers("running")

	// Get stopped containers count
	_, info.StoppedCount = getContainers("exited")

	// Get images info
	info.ImageCount, info.TotalImageSize = getImagesInfo()

	// Get dangling images size
	info.DanglingImages = getDanglingImagesSize()

	return info
}

func getContainers(status string) ([]models.ContainerInfo, int) {
	var containers []models.ContainerInfo

	cmd := exec.Command("docker", "ps", "-a",
		"--filter", "status="+status,
		"--format", "{{json .}}")
	output, err := cmd.Output()
	if err != nil {
		return containers, 0
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	for _, line := range lines {
		if line == "" {
			continue
		}

		var dc dockerContainer
		if err := json.Unmarshal([]byte(line), &dc); err != nil {
			continue
		}

		container := models.ContainerInfo{
			Name:    strings.TrimPrefix(dc.Names, "/"),
			Image:   dc.Image,
			Status:  dc.Status,
			State:   dc.State,
			Created: dc.CreatedAt,
		}

		// Get container stats for CPU/Memory (only for running containers)
		if status == "running" {
			container.CPUPercent, container.MemoryPercent = getContainerStats(container.Name)
		}

		containers = append(containers, container)
	}

	return containers, len(containers)
}

func getContainerStats(name string) (float64, float64) {
	cmd := exec.Command("docker", "stats", name, "--no-stream", "--format", "{{.CPUPerc}},{{.MemPerc}}")
	output, err := cmd.Output()
	if err != nil {
		return 0, 0
	}

	parts := strings.Split(strings.TrimSpace(string(output)), ",")
	if len(parts) != 2 {
		return 0, 0
	}

	cpuStr := strings.TrimSuffix(parts[0], "%")
	memStr := strings.TrimSuffix(parts[1], "%")

	cpu, _ := strconv.ParseFloat(cpuStr, 64)
	mem, _ := strconv.ParseFloat(memStr, 64)

	return cpu, mem
}

func getImagesInfo() (int, int64) {
	cmd := exec.Command("docker", "images", "--format", "{{.Size}}")
	output, err := cmd.Output()
	if err != nil {
		return 0, 0
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	count := 0
	var totalSize int64 = 0

	for _, line := range lines {
		if line == "" {
			continue
		}
		count++
		totalSize += parseSize(line)
	}

	return count, totalSize
}

func getDanglingImagesSize() int64 {
	cmd := exec.Command("docker", "images", "-f", "dangling=true", "--format", "{{.Size}}")
	output, err := cmd.Output()
	if err != nil {
		return 0
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	var totalSize int64 = 0

	for _, line := range lines {
		if line == "" {
			continue
		}
		totalSize += parseSize(line)
	}

	return totalSize
}

// parseSize converts Docker size strings like "1.23GB" to bytes
func parseSize(sizeStr string) int64 {
	sizeStr = strings.TrimSpace(sizeStr)
	if sizeStr == "" {
		return 0
	}

	var multiplier int64 = 1
	sizeStr = strings.ToUpper(sizeStr)

	if strings.HasSuffix(sizeStr, "GB") {
		multiplier = 1024 * 1024 * 1024
		sizeStr = strings.TrimSuffix(sizeStr, "GB")
	} else if strings.HasSuffix(sizeStr, "MB") {
		multiplier = 1024 * 1024
		sizeStr = strings.TrimSuffix(sizeStr, "MB")
	} else if strings.HasSuffix(sizeStr, "KB") {
		multiplier = 1024
		sizeStr = strings.TrimSuffix(sizeStr, "KB")
	} else if strings.HasSuffix(sizeStr, "B") {
		sizeStr = strings.TrimSuffix(sizeStr, "B")
	}

	value, err := strconv.ParseFloat(sizeStr, 64)
	if err != nil {
		return 0
	}

	return int64(value * float64(multiplier))
}
