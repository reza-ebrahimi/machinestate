package collectors

import (
	"bufio"
	"os"
	"os/exec"
	"strings"
	"time"

	"ubuntu-state/models"
)

// CollectSecurityInfo gathers security-related information
func CollectSecurityInfo() models.SecurityInfo {
	info := models.SecurityInfo{
		OpenPorts: []string{},
	}

	// Check UFW status
	cmd := exec.Command("ufw", "status")
	output, err := cmd.Output()
	if err == nil {
		info.FirewallStatus = strings.TrimSpace(string(output))
		info.FirewallActive = strings.Contains(info.FirewallStatus, "Status: active")
	} else {
		info.FirewallStatus = "UFW not installed or not accessible"
		info.FirewallActive = false
	}

	// Check for ports listening on all interfaces (0.0.0.0)
	cmd = exec.Command("ss", "-tulpn")
	output, err = cmd.Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			if strings.Contains(line, "0.0.0.0:") || strings.Contains(line, "*:") {
				fields := strings.Fields(line)
				if len(fields) >= 5 {
					info.OpenPorts = append(info.OpenPorts, fields[4])
				}
			}
		}
	}

	// Count failed login attempts in last 24 hours
	info.FailedLogins24h = countFailedLogins()

	// Check if SSH is enabled
	cmd = exec.Command("systemctl", "is-active", "ssh")
	output, err = cmd.Output()
	if err == nil {
		info.SSHEnabled = strings.TrimSpace(string(output)) == "active"
	}

	return info
}

// countFailedLogins counts failed login attempts in the last 24 hours
func countFailedLogins() int {
	count := 0
	cutoff := time.Now().Add(-24 * time.Hour)

	// Check auth.log
	file, err := os.Open("/var/log/auth.log")
	if err != nil {
		return 0
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.Contains(line, "Failed password") && !strings.Contains(line, "authentication failure") {
			continue
		}

		// Parse timestamp (format: "Dec 30 10:30:45")
		if len(line) >= 15 {
			timeStr := line[:15]
			// Add current year since auth.log doesn't include it
			timeStr = timeStr + " " + time.Now().Format("2006")
			t, err := time.Parse("Jan  2 15:04:05 2006", timeStr)
			if err != nil {
				t, err = time.Parse("Jan 2 15:04:05 2006", timeStr)
			}
			if err == nil && t.After(cutoff) {
				count++
			}
		}
	}

	return count
}
