package collectors

import (
	"bufio"
	"encoding/json"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strings"

	"ubuntu-state/models"
)

// journalEntry represents a journalctl JSON output entry
type journalEntry struct {
	Priority string `json:"PRIORITY"`
	Message  string `json:"MESSAGE"`
}

// CollectLogInfo analyzes system logs for the last 24 hours
func CollectLogInfo() models.LogInfo {
	info := models.LogInfo{
		Period: "24h",
		Stats: models.LogStats{
			TopErrors: []models.ErrorPattern{},
		},
	}

	// Check if journalctl is available
	if _, err := exec.LookPath("journalctl"); err != nil {
		return info
	}
	info.Available = true

	// Get log statistics
	info.Stats = analyzeJournalLogs()

	// Check for OOM events
	info.Stats.OOMEvents = countOOMEvents()

	// Check for kernel panics
	info.Stats.KernelPanics = countKernelPanics()

	// Check for segfaults
	info.Stats.Segfaults = countSegfaults()

	return info
}

func analyzeJournalLogs() models.LogStats {
	stats := models.LogStats{
		TopErrors: []models.ErrorPattern{},
	}

	// Get errors and above (priority 0-3)
	cmd := exec.Command("journalctl",
		"--since", "24 hours ago",
		"-p", "err..emerg",
		"--no-pager",
		"-o", "json")
	output, err := cmd.Output()
	if err != nil {
		return stats
	}

	// Parse JSON entries and count by priority
	errorPatterns := make(map[string]int)

	lines := strings.Split(string(output), "\n")
	for _, line := range lines {
		if line == "" {
			continue
		}

		var entry journalEntry
		if err := json.Unmarshal([]byte(line), &entry); err != nil {
			continue
		}

		// Count by priority
		// 0: emerg, 1: alert, 2: crit, 3: err, 4: warning, 5: notice, 6: info, 7: debug
		switch entry.Priority {
		case "0", "1", "2":
			stats.CriticalCount++
		case "3":
			stats.ErrorCount++
		case "4":
			stats.WarningCount++
		}

		// Extract error pattern (simplify message for grouping)
		if entry.Message != "" {
			pattern := simplifyErrorMessage(entry.Message)
			if pattern != "" {
				errorPatterns[pattern]++
			}
		}
	}

	// Get top 5 error patterns
	stats.TopErrors = getTopPatterns(errorPatterns, 5)

	return stats
}

func simplifyErrorMessage(msg string) string {
	// Remove timestamps, PIDs, memory addresses, etc.
	msg = strings.TrimSpace(msg)

	// Remove hex addresses
	re := regexp.MustCompile(`0x[0-9a-fA-F]+`)
	msg = re.ReplaceAllString(msg, "0x...")

	// Remove numbers that look like PIDs or ports
	re = regexp.MustCompile(`\b\d{4,}\b`)
	msg = re.ReplaceAllString(msg, "...")

	// Truncate long messages
	if len(msg) > 80 {
		msg = msg[:80] + "..."
	}

	return msg
}

func getTopPatterns(patterns map[string]int, limit int) []models.ErrorPattern {
	var result []models.ErrorPattern

	for pattern, count := range patterns {
		result = append(result, models.ErrorPattern{
			Pattern: pattern,
			Count:   count,
		})
	}

	// Sort by count descending
	sort.Slice(result, func(i, j int) bool {
		return result[i].Count > result[j].Count
	})

	// Limit results
	if len(result) > limit {
		result = result[:limit]
	}

	return result
}

func countOOMEvents() int {
	cmd := exec.Command("journalctl",
		"--since", "24 hours ago",
		"-k",
		"--no-pager",
		"--grep", "Out of memory|oom-kill|oom_reaper")
	output, err := cmd.Output()
	if err != nil {
		// Command returns non-zero if no matches
		return 0
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	count := 0
	for _, line := range lines {
		if line != "" {
			count++
		}
	}
	return count
}

func countKernelPanics() int {
	// Check journalctl for kernel panics
	cmd := exec.Command("journalctl",
		"--since", "24 hours ago",
		"-k",
		"--no-pager",
		"--grep", "Kernel panic")
	output, _ := cmd.Output()

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	count := 0
	for _, line := range lines {
		if line != "" {
			count++
		}
	}

	// Also check /var/log/kern.log if it exists
	if f, err := os.Open("/var/log/kern.log"); err == nil {
		defer f.Close()
		scanner := bufio.NewScanner(f)
		for scanner.Scan() {
			if strings.Contains(strings.ToLower(scanner.Text()), "kernel panic") {
				count++
			}
		}
	}

	return count
}

func countSegfaults() int {
	cmd := exec.Command("journalctl",
		"--since", "24 hours ago",
		"-k",
		"--no-pager",
		"--grep", "segfault")
	output, err := cmd.Output()
	if err != nil {
		return 0
	}

	lines := strings.Split(strings.TrimSpace(string(output)), "\n")
	count := 0
	for _, line := range lines {
		if line != "" {
			count++
		}
	}
	return count
}
