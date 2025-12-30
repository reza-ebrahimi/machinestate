package outputs

import (
	"fmt"
	"html/template"
	"strings"

	"ubuntu-state/models"
)

const htmlTemplate = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System State Report - {{.Hostname}}</title>
    <style>
        :root {
            --bg: #0d1117;
            --card-bg: #161b22;
            --border: #30363d;
            --text: #c9d1d9;
            --text-dim: #8b949e;
            --accent: #58a6ff;
            --success: #3fb950;
            --warning: #d29922;
            --error: #f85149;
            --critical: #ff7b72;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
            background: var(--bg);
            color: var(--text);
            line-height: 1.6;
            padding: 20px;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 {
            text-align: center;
            padding: 20px;
            border-bottom: 1px solid var(--border);
            margin-bottom: 20px;
        }
        .header-info {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 10px;
            margin-bottom: 20px;
            padding: 15px;
            background: var(--card-bg);
            border-radius: 8px;
            border: 1px solid var(--border);
        }
        .header-info div { color: var(--text-dim); }
        .header-info span { color: var(--text); font-weight: 500; }
        .issues-summary {
            display: flex;
            gap: 15px;
            margin-bottom: 20px;
            flex-wrap: wrap;
        }
        .issue-badge {
            padding: 10px 20px;
            border-radius: 8px;
            font-weight: 600;
        }
        .issue-badge.critical { background: rgba(248, 81, 73, 0.2); color: var(--critical); border: 1px solid var(--critical); }
        .issue-badge.warning { background: rgba(210, 153, 34, 0.2); color: var(--warning); border: 1px solid var(--warning); }
        .issue-badge.info { background: rgba(88, 166, 255, 0.2); color: var(--accent); border: 1px solid var(--accent); }
        .issue-badge.success { background: rgba(63, 185, 80, 0.2); color: var(--success); border: 1px solid var(--success); }
        .section {
            background: var(--card-bg);
            border: 1px solid var(--border);
            border-radius: 8px;
            margin-bottom: 20px;
            overflow: hidden;
        }
        .section-title {
            background: rgba(88, 166, 255, 0.1);
            padding: 12px 20px;
            font-weight: 600;
            color: var(--accent);
            border-bottom: 1px solid var(--border);
        }
        .section-content { padding: 15px 20px; }
        table {
            width: 100%;
            border-collapse: collapse;
        }
        th, td {
            padding: 10px 15px;
            text-align: left;
            border-bottom: 1px solid var(--border);
        }
        th { color: var(--text-dim); font-weight: 500; }
        tr:last-child td { border-bottom: none; }
        .status-up { color: var(--success); }
        .status-down { color: var(--text-dim); }
        .status-ok { color: var(--success); }
        .status-warn { color: var(--warning); }
        .status-error { color: var(--error); }
        .progress-bar {
            background: var(--border);
            border-radius: 4px;
            height: 8px;
            overflow: hidden;
            width: 100px;
            display: inline-block;
            vertical-align: middle;
            margin-left: 10px;
        }
        .progress-fill {
            height: 100%;
            border-radius: 4px;
        }
        .progress-ok { background: var(--success); }
        .progress-warn { background: var(--warning); }
        .progress-error { background: var(--error); }
        .issue-card {
            padding: 15px;
            margin-bottom: 10px;
            border-radius: 6px;
            border-left: 4px solid;
        }
        .issue-card.critical { border-color: var(--critical); background: rgba(248, 81, 73, 0.1); }
        .issue-card.warning { border-color: var(--warning); background: rgba(210, 153, 34, 0.1); }
        .issue-card.info { border-color: var(--accent); background: rgba(88, 166, 255, 0.1); }
        .issue-title { font-weight: 600; margin-bottom: 5px; }
        .issue-category { color: var(--text-dim); font-size: 0.9em; }
        .issue-fix { color: var(--success); margin-top: 8px; font-family: monospace; font-size: 0.9em; }
        .grid-2 { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .kv-row { display: flex; justify-content: space-between; padding: 8px 0; border-bottom: 1px solid var(--border); }
        .kv-row:last-child { border-bottom: none; }
        .kv-key { color: var(--text-dim); }
        .kv-value { font-weight: 500; }
        footer {
            text-align: center;
            padding: 20px;
            color: var(--text-dim);
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>System State Report</h1>

        <div class="header-info">
            <div>Hostname: <span>{{.Hostname}}</span></div>
            <div>OS: <span>{{.OS.Name}}</span></div>
            <div>Kernel: <span>{{.OS.Kernel}}</span></div>
            <div>Uptime: <span>{{.System.UptimeHuman}}</span></div>
            <div>Report Time: <span>{{.Timestamp.Format "2006-01-02 15:04:05"}}</span></div>
        </div>

        <div class="issues-summary">
            {{if .HasCritical}}<div class="issue-badge critical">{{.CriticalCount}} Critical</div>{{end}}
            {{if .HasWarning}}<div class="issue-badge warning">{{.WarningCount}} Warnings</div>{{end}}
            {{if .HasInfo}}<div class="issue-badge info">{{.InfoCount}} Info</div>{{end}}
            {{if .NoIssues}}<div class="issue-badge success">✓ No Issues Detected</div>{{end}}
        </div>

        <div class="grid-2">
            <div class="section">
                <div class="section-title">System</div>
                <div class="section-content">
                    <div class="kv-row">
                        <span class="kv-key">Load Average</span>
                        <span class="kv-value">{{printf "%.2f / %.2f / %.2f" .System.LoadAvg1 .System.LoadAvg5 .System.LoadAvg15}}</span>
                    </div>
                    <div class="kv-row">
                        <span class="kv-key">CPU</span>
                        <span class="kv-value">{{.System.CPUCores}} cores @ {{printf "%.1f" .System.CPUUsage}}%</span>
                    </div>
                    <div class="kv-row">
                        <span class="kv-key">Memory</span>
                        <span class="kv-value {{.MemoryStatus}}">
                            {{.MemoryUsedStr}} / {{.MemoryTotalStr}} ({{printf "%.1f" .System.MemoryPercent}}%)
                            <div class="progress-bar"><div class="progress-fill {{.MemoryProgress}}" style="width: {{printf "%.0f" .System.MemoryPercent}}%"></div></div>
                        </span>
                    </div>
                    {{if gt .System.SwapTotal 0}}
                    <div class="kv-row">
                        <span class="kv-key">Swap</span>
                        <span class="kv-value">{{.SwapUsedStr}} / {{.SwapTotalStr}} ({{printf "%.1f" .System.SwapPercent}}%)</span>
                    </div>
                    {{end}}
                </div>
            </div>

            <div class="section">
                <div class="section-title">Packages</div>
                <div class="section-content">
                    <div class="kv-row">
                        <span class="kv-key">Updates Available</span>
                        <span class="kv-value {{if gt .Packages.UpdatesAvailable 0}}status-warn{{else}}status-ok{{end}}">{{.Packages.UpdatesAvailable}}</span>
                    </div>
                    {{if gt .Packages.SecurityUpdates 0}}
                    <div class="kv-row">
                        <span class="kv-key">Security Updates</span>
                        <span class="kv-value status-error">{{.Packages.SecurityUpdates}}</span>
                    </div>
                    {{end}}
                    <div class="kv-row">
                        <span class="kv-key">Broken Packages</span>
                        <span class="kv-value {{if gt .Packages.BrokenPackages 0}}status-error{{else}}status-ok{{end}}">{{.Packages.BrokenPackages}}</span>
                    </div>
                </div>
            </div>
        </div>

        <div class="section">
            <div class="section-title">Disk</div>
            <div class="section-content">
                <table>
                    <thead>
                        <tr>
                            <th>Mount Point</th>
                            <th>Size</th>
                            <th>Used</th>
                            <th>Free</th>
                            <th>Usage</th>
                        </tr>
                    </thead>
                    <tbody>
                        {{range .Disk.Filesystems}}
                        <tr>
                            <td>{{.MountPoint}}</td>
                            <td>{{formatBytes .Total}}</td>
                            <td>{{formatBytes .Used}}</td>
                            <td>{{formatBytes .Free}}</td>
                            <td>
                                <span class="{{diskStatus .UsedPercent}}">{{printf "%.1f" .UsedPercent}}%</span>
                                <div class="progress-bar"><div class="progress-fill {{diskProgress .UsedPercent}}" style="width: {{printf "%.0f" .UsedPercent}}%"></div></div>
                            </td>
                        </tr>
                        {{end}}
                    </tbody>
                </table>
            </div>
        </div>

        <div class="section">
            <div class="section-title">Network</div>
            <div class="section-content">
                <table>
                    <thead>
                        <tr>
                            <th>Interface</th>
                            <th>State</th>
                            <th>IP Addresses</th>
                            <th>RX</th>
                            <th>TX</th>
                        </tr>
                    </thead>
                    <tbody>
                        {{range .Network.Interfaces}}
                        <tr>
                            <td>{{.Name}}</td>
                            <td class="{{if eq .State "UP"}}status-up{{else}}status-down{{end}}">{{.State}}</td>
                            <td>{{join .IPs ", "}}</td>
                            <td>{{formatBytes .RxBytes}}</td>
                            <td>{{formatBytes .TxBytes}}</td>
                        </tr>
                        {{end}}
                    </tbody>
                </table>
                <div style="margin-top: 15px;">
                    <span class="kv-key">Internet: </span>
                    <span class="{{if .Network.Connectivity}}status-ok{{else}}status-error{{end}}">
                        {{if .Network.Connectivity}}Connected{{else}}Disconnected{{end}}
                    </span>
                </div>
            </div>
        </div>

        <div class="grid-2">
            <div class="section">
                <div class="section-title">Security</div>
                <div class="section-content">
                    <div class="kv-row">
                        <span class="kv-key">Firewall</span>
                        <span class="kv-value {{if .Security.FirewallActive}}status-ok{{else}}status-error{{end}}">
                            {{if .Security.FirewallActive}}Active{{else}}Inactive{{end}}
                        </span>
                    </div>
                    <div class="kv-row">
                        <span class="kv-key">SSH</span>
                        <span class="kv-value">{{if .Security.SSHEnabled}}Enabled{{else}}Disabled{{end}}</span>
                    </div>
                    {{if gt .Security.FailedLogins24h 0}}
                    <div class="kv-row">
                        <span class="kv-key">Failed Logins (24h)</span>
                        <span class="kv-value status-warn">{{.Security.FailedLogins24h}}</span>
                    </div>
                    {{end}}
                    <div class="kv-row">
                        <span class="kv-key">Open Ports (0.0.0.0)</span>
                        <span class="kv-value">{{len .Security.OpenPorts}}</span>
                    </div>
                </div>
            </div>

            <div class="section">
                <div class="section-title">Services</div>
                <div class="section-content">
                    <div class="kv-row">
                        <span class="kv-key">Failed Services</span>
                        <span class="kv-value {{if gt (len .Services.FailedUnits) 0}}status-error{{else}}status-ok{{end}}">
                            {{len .Services.FailedUnits}}
                        </span>
                    </div>
                    <div class="kv-row">
                        <span class="kv-key">Zombie Processes</span>
                        <span class="kv-value {{if gt .Services.ZombieCount 0}}status-warn{{else}}status-ok{{end}}">
                            {{.Services.ZombieCount}}
                        </span>
                    </div>
                </div>
            </div>
        </div>

        {{if .Hardware.Battery}}
        <div class="section">
            <div class="section-title">Battery</div>
            <div class="section-content">
                <div class="kv-row">
                    <span class="kv-key">Status</span>
                    <span class="kv-value">{{.Hardware.Battery.Status}}</span>
                </div>
                <div class="kv-row">
                    <span class="kv-key">Capacity</span>
                    <span class="kv-value">{{printf "%.0f" .Hardware.Battery.Capacity}}%</span>
                </div>
                <div class="kv-row">
                    <span class="kv-key">Health</span>
                    <span class="kv-value {{batteryHealthStatus .Hardware.Battery.Health}}">{{printf "%.1f" .Hardware.Battery.Health}}%</span>
                </div>
                <div class="kv-row">
                    <span class="kv-key">Cycle Count</span>
                    <span class="kv-value">{{.Hardware.Battery.CycleCount}}</span>
                </div>
            </div>
        </div>
        {{end}}

        {{if .Issues}}
        <div class="section">
            <div class="section-title">Issues</div>
            <div class="section-content">
                {{range .Issues}}
                <div class="issue-card {{.Severity}}">
                    <div class="issue-title">{{.Title}}</div>
                    <div class="issue-category">{{.Category}}</div>
                    <div>{{.Description}}</div>
                    {{if .Fix}}<div class="issue-fix">Fix: {{.Fix}}</div>{{end}}
                </div>
                {{end}}
            </div>
        </div>
        {{end}}

        <footer>
            Generated by ubuntu-state
        </footer>
    </div>
</body>
</html>`

// HTMLData extends Report with template helper fields
type HTMLData struct {
	*models.Report
	CriticalCount  int
	WarningCount   int
	InfoCount      int
	HasCritical    bool
	HasWarning     bool
	HasInfo        bool
	NoIssues       bool
	MemoryUsedStr  string
	MemoryTotalStr string
	SwapUsedStr    string
	SwapTotalStr   string
	MemoryStatus   string
	MemoryProgress string
}

// RenderHTML outputs the report as HTML
func RenderHTML(report *models.Report) (string, error) {
	funcMap := template.FuncMap{
		"formatBytes": formatBytes,
		"join":        strings.Join,
		"diskStatus": func(p float64) string {
			if p >= 90 {
				return "status-error"
			} else if p >= 80 {
				return "status-warn"
			}
			return "status-ok"
		},
		"diskProgress": func(p float64) string {
			if p >= 90 {
				return "progress-error"
			} else if p >= 80 {
				return "progress-warn"
			}
			return "progress-ok"
		},
		"batteryHealthStatus": func(h float64) string {
			if h < 50 {
				return "status-error"
			} else if h < 80 {
				return "status-warn"
			}
			return "status-ok"
		},
	}

	tmpl, err := template.New("report").Funcs(funcMap).Parse(htmlTemplate)
	if err != nil {
		return "", fmt.Errorf("failed to parse template: %w", err)
	}

	// Prepare data
	data := HTMLData{
		Report:         report,
		MemoryUsedStr:  formatBytes(report.System.MemoryUsed),
		MemoryTotalStr: formatBytes(report.System.MemoryTotal),
		SwapUsedStr:    formatBytes(report.System.SwapUsed),
		SwapTotalStr:   formatBytes(report.System.SwapTotal),
	}

	// Count issues
	for _, issue := range report.Issues {
		switch issue.Severity {
		case models.SeverityCritical:
			data.CriticalCount++
		case models.SeverityWarning:
			data.WarningCount++
		case models.SeverityInfo:
			data.InfoCount++
		}
	}
	data.HasCritical = data.CriticalCount > 0
	data.HasWarning = data.WarningCount > 0
	data.HasInfo = data.InfoCount > 0
	data.NoIssues = !data.HasCritical && !data.HasWarning && !data.HasInfo

	// Memory status
	if report.System.MemoryPercent >= 90 {
		data.MemoryStatus = "status-error"
		data.MemoryProgress = "progress-error"
	} else if report.System.MemoryPercent >= 80 {
		data.MemoryStatus = "status-warn"
		data.MemoryProgress = "progress-warn"
	} else {
		data.MemoryStatus = "status-ok"
		data.MemoryProgress = "progress-ok"
	}

	var sb strings.Builder
	if err := tmpl.Execute(&sb, data); err != nil {
		return "", fmt.Errorf("failed to execute template: %w", err)
	}

	return sb.String(), nil
}
