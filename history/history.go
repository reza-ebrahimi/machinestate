package history

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"ubuntu-state/models"
)

const (
	historyDir  = ".local/share/ubuntu-state/history"
	maxHistory  = 100 // Keep last 100 reports
)

// GetHistoryDir returns the full path to history directory
func GetHistoryDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, historyDir)
}

// Save saves a report to history
func Save(report *models.Report) error {
	dir := GetHistoryDir()
	if dir == "" {
		return fmt.Errorf("could not determine home directory")
	}

	// Create directory if needed
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create history directory: %w", err)
	}

	// Generate filename from timestamp
	filename := report.Timestamp.Format("2006-01-02T15-04-05") + ".json"
	filepath := filepath.Join(dir, filename)

	// Marshal report
	data, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal report: %w", err)
	}

	// Write file
	if err := os.WriteFile(filepath, data, 0644); err != nil {
		return fmt.Errorf("failed to write report: %w", err)
	}

	// Cleanup old reports
	cleanupOldReports(dir)

	return nil
}

// List returns all saved reports (metadata only)
func List() ([]ReportMeta, error) {
	dir := GetHistoryDir()
	if dir == "" {
		return nil, fmt.Errorf("could not determine home directory")
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return []ReportMeta{}, nil
		}
		return nil, err
	}

	var reports []ReportMeta
	for _, entry := range entries {
		if !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}

		// Parse timestamp from filename
		name := strings.TrimSuffix(entry.Name(), ".json")
		t, err := time.Parse("2006-01-02T15-04-05", name)
		if err != nil {
			continue
		}

		info, err := entry.Info()
		if err != nil {
			continue
		}

		reports = append(reports, ReportMeta{
			ID:        name,
			Timestamp: t,
			Size:      info.Size(),
			Path:      filepath.Join(dir, entry.Name()),
		})
	}

	// Sort by timestamp descending
	sort.Slice(reports, func(i, j int) bool {
		return reports[i].Timestamp.After(reports[j].Timestamp)
	})

	return reports, nil
}

// Load loads a report by ID
func Load(id string) (*models.Report, error) {
	dir := GetHistoryDir()
	if dir == "" {
		return nil, fmt.Errorf("could not determine home directory")
	}

	path := filepath.Join(dir, id+".json")
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read report: %w", err)
	}

	var report models.Report
	if err := json.Unmarshal(data, &report); err != nil {
		return nil, fmt.Errorf("failed to parse report: %w", err)
	}

	return &report, nil
}

// GetLatest returns the most recent saved report
func GetLatest() (*models.Report, error) {
	reports, err := List()
	if err != nil {
		return nil, err
	}
	if len(reports) == 0 {
		return nil, fmt.Errorf("no history found")
	}
	return Load(reports[0].ID)
}

// Compare compares two reports and returns the differences
func Compare(old, new *models.Report) *Comparison {
	comp := &Comparison{
		OldTimestamp: old.Timestamp,
		NewTimestamp: new.Timestamp,
		Changes:      []Change{},
	}

	// Compare disk usage
	oldDisks := make(map[string]float64)
	for _, fs := range old.Disk.Filesystems {
		oldDisks[fs.MountPoint] = fs.UsedPercent
	}
	for _, fs := range new.Disk.Filesystems {
		if oldPct, ok := oldDisks[fs.MountPoint]; ok {
			diff := fs.UsedPercent - oldPct
			if diff > 1 || diff < -1 { // Only report significant changes
				comp.Changes = append(comp.Changes, Change{
					Category: "Disk",
					Item:     fs.MountPoint,
					Old:      fmt.Sprintf("%.1f%%", oldPct),
					New:      fmt.Sprintf("%.1f%%", fs.UsedPercent),
					Delta:    fmt.Sprintf("%+.1f%%", diff),
				})
			}
		}
	}

	// Compare memory
	memDiff := new.System.MemoryPercent - old.System.MemoryPercent
	if memDiff > 5 || memDiff < -5 {
		comp.Changes = append(comp.Changes, Change{
			Category: "Memory",
			Item:     "Usage",
			Old:      fmt.Sprintf("%.1f%%", old.System.MemoryPercent),
			New:      fmt.Sprintf("%.1f%%", new.System.MemoryPercent),
			Delta:    fmt.Sprintf("%+.1f%%", memDiff),
		})
	}

	// Compare package updates
	updateDiff := new.Packages.UpdatesAvailable - old.Packages.UpdatesAvailable
	if updateDiff != 0 {
		comp.Changes = append(comp.Changes, Change{
			Category: "Packages",
			Item:     "Updates Available",
			Old:      fmt.Sprintf("%d", old.Packages.UpdatesAvailable),
			New:      fmt.Sprintf("%d", new.Packages.UpdatesAvailable),
			Delta:    fmt.Sprintf("%+d", updateDiff),
		})
	}

	// Compare failed services
	oldFailed := make(map[string]bool)
	for _, s := range old.Services.FailedUnits {
		oldFailed[s] = true
	}
	newFailed := make(map[string]bool)
	for _, s := range new.Services.FailedUnits {
		newFailed[s] = true
	}

	for s := range newFailed {
		if !oldFailed[s] {
			comp.Changes = append(comp.Changes, Change{
				Category: "Services",
				Item:     s,
				Old:      "OK",
				New:      "FAILED",
				Delta:    "NEW FAILURE",
			})
		}
	}
	for s := range oldFailed {
		if !newFailed[s] {
			comp.Changes = append(comp.Changes, Change{
				Category: "Services",
				Item:     s,
				Old:      "FAILED",
				New:      "OK",
				Delta:    "RESOLVED",
			})
		}
	}

	// Compare issues count
	oldCrit, oldWarn, _ := countIssuesBySeverity(old.Issues)
	newCrit, newWarn, _ := countIssuesBySeverity(new.Issues)

	if newCrit != oldCrit {
		comp.Changes = append(comp.Changes, Change{
			Category: "Issues",
			Item:     "Critical",
			Old:      fmt.Sprintf("%d", oldCrit),
			New:      fmt.Sprintf("%d", newCrit),
			Delta:    fmt.Sprintf("%+d", newCrit-oldCrit),
		})
	}
	if newWarn != oldWarn {
		comp.Changes = append(comp.Changes, Change{
			Category: "Issues",
			Item:     "Warnings",
			Old:      fmt.Sprintf("%d", oldWarn),
			New:      fmt.Sprintf("%d", newWarn),
			Delta:    fmt.Sprintf("%+d", newWarn-oldWarn),
		})
	}

	// Compare battery health
	if old.Hardware.Battery != nil && new.Hardware.Battery != nil {
		healthDiff := new.Hardware.Battery.Health - old.Hardware.Battery.Health
		if healthDiff < -1 {
			comp.Changes = append(comp.Changes, Change{
				Category: "Hardware",
				Item:     "Battery Health",
				Old:      fmt.Sprintf("%.1f%%", old.Hardware.Battery.Health),
				New:      fmt.Sprintf("%.1f%%", new.Hardware.Battery.Health),
				Delta:    fmt.Sprintf("%.1f%%", healthDiff),
			})
		}
	}

	return comp
}

func countIssuesBySeverity(issues []models.Issue) (critical, warning, info int) {
	for _, issue := range issues {
		switch issue.Severity {
		case models.SeverityCritical:
			critical++
		case models.SeverityWarning:
			warning++
		case models.SeverityInfo:
			info++
		}
	}
	return
}

func cleanupOldReports(dir string) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}

	var files []os.DirEntry
	for _, entry := range entries {
		if strings.HasSuffix(entry.Name(), ".json") {
			files = append(files, entry)
		}
	}

	if len(files) <= maxHistory {
		return
	}

	// Sort by name (which is timestamp) ascending
	sort.Slice(files, func(i, j int) bool {
		return files[i].Name() < files[j].Name()
	})

	// Remove oldest files
	for i := 0; i < len(files)-maxHistory; i++ {
		os.Remove(filepath.Join(dir, files[i].Name()))
	}
}

// ReportMeta contains metadata about a saved report
type ReportMeta struct {
	ID        string
	Timestamp time.Time
	Size      int64
	Path      string
}

// Comparison represents the difference between two reports
type Comparison struct {
	OldTimestamp time.Time
	NewTimestamp time.Time
	Changes      []Change
}

// Change represents a single change between reports
type Change struct {
	Category string
	Item     string
	Old      string
	New      string
	Delta    string
}
