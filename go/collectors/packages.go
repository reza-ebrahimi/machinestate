package collectors

import (
	"bufio"
	"os/exec"
	"strings"

	"machinestate/models"
)

// CollectPackageInfo gathers APT package information
func CollectPackageInfo() models.PackageInfo {
	info := models.PackageInfo{
		UpdatesList:  []string{},
		HeldPackages: []string{},
	}

	// Get upgradable packages
	cmd := exec.Command("apt", "list", "--upgradable")
	output, err := cmd.Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			if strings.Contains(line, "upgradable") || strings.Contains(line, "/") {
				if strings.TrimSpace(line) != "" && !strings.HasPrefix(line, "Listing") {
					// Extract package name
					parts := strings.Split(line, "/")
					if len(parts) > 0 {
						info.UpdatesList = append(info.UpdatesList, parts[0])
						info.UpdatesAvailable++

						// Check for security updates
						if strings.Contains(line, "security") {
							info.SecurityUpdates++
						}
					}
				}
			}
		}
	}

	// Check for broken packages
	cmd = exec.Command("dpkg", "--audit")
	output, err = cmd.Output()
	if err == nil && len(strings.TrimSpace(string(output))) > 0 {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			if strings.TrimSpace(line) != "" {
				info.BrokenPackages++
			}
		}
	}

	// Check for held packages
	cmd = exec.Command("apt-mark", "showhold")
	output, err = cmd.Output()
	if err == nil {
		scanner := bufio.NewScanner(strings.NewReader(string(output)))
		for scanner.Scan() {
			line := strings.TrimSpace(scanner.Text())
			if line != "" {
				info.HeldPackages = append(info.HeldPackages, line)
			}
		}
	}

	return info
}
