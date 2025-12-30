package collectors

import (
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"ubuntu-state/models"
)

// CollectSnapInfo gathers snap package information
func CollectSnapInfo() models.SnapInfo {
	info := models.SnapInfo{
		Snaps: []models.SnapPackage{},
	}

	// Check if snap is available
	if _, err := exec.LookPath("snap"); err != nil {
		return info
	}
	info.Available = true

	// Get installed snaps
	info.Snaps, info.TotalDiskUsage = getInstalledSnaps()

	// Get pending refreshes
	info.PendingRefreshes = getPendingRefreshes()

	return info
}

func getInstalledSnaps() ([]models.SnapPackage, int64) {
	var snaps []models.SnapPackage
	var totalSize int64 = 0

	cmd := exec.Command("snap", "list", "--color=never")
	output, err := cmd.Output()
	if err != nil {
		return snaps, 0
	}

	lines := strings.Split(string(output), "\n")
	for i, line := range lines {
		// Skip header line
		if i == 0 {
			continue
		}

		fields := strings.Fields(line)
		if len(fields) < 4 {
			continue
		}

		snap := models.SnapPackage{
			Name:     fields[0],
			Version:  fields[1],
			Revision: fields[2],
		}

		// Publisher is in the 4th column
		if len(fields) >= 5 {
			snap.Publisher = fields[4]
		}

		// Get disk usage for this snap
		snap.DiskUsage = getSnapDiskUsage(snap.Name)
		totalSize += snap.DiskUsage

		snaps = append(snaps, snap)
	}

	return snaps, totalSize
}

func getSnapDiskUsage(name string) int64 {
	// Snaps are installed in /snap/<name>
	snapPath := filepath.Join("/snap", name)

	cmd := exec.Command("du", "-sb", snapPath)
	output, err := cmd.Output()
	if err != nil {
		return 0
	}

	fields := strings.Fields(string(output))
	if len(fields) < 1 {
		return 0
	}

	size, err := strconv.ParseInt(fields[0], 10, 64)
	if err != nil {
		return 0
	}

	return size
}

func getPendingRefreshes() int {
	cmd := exec.Command("snap", "refresh", "--list")
	output, err := cmd.Output()
	if err != nil {
		return 0
	}

	// Count lines (excluding header if present)
	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	if len(lines) == 0 {
		return 0
	}

	// If the output contains "All snaps up to date" or similar, return 0
	if strings.Contains(string(output), "All snaps up to date") {
		return 0
	}

	// Count non-empty lines (minus header)
	count := 0
	for i, line := range lines {
		// Skip header
		if i == 0 && strings.Contains(strings.ToLower(line), "name") {
			continue
		}
		if strings.TrimSpace(line) != "" {
			count++
		}
	}

	return count
}
