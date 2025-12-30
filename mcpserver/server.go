package mcpserver

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"

	"ubuntu-state/collectors"
	"ubuntu-state/history"
	"ubuntu-state/models"
)

// Run starts the MCP server using stdio transport
func Run() error {
	s := NewServer()
	return server.ServeStdio(s)
}

// NewServer creates a new MCP server with all tools registered
func NewServer() *server.MCPServer {
	s := server.NewMCPServer(
		"ubuntu-state",
		"1.0.0",
		server.WithToolCapabilities(false),
		server.WithRecovery(),
	)

	registerTools(s)
	return s
}

func registerTools(s *server.MCPServer) {
	// Primary tools
	registerGetSystemReport(s)
	registerGetIssues(s)

	// Granular collectors
	registerGetSystemInfo(s)
	registerGetDiskInfo(s)
	registerGetNetworkInfo(s)
	registerGetPackageInfo(s)
	registerGetServiceInfo(s)
	registerGetSecurityInfo(s)
	registerGetHardwareInfo(s)

	// History tools
	registerListReports(s)
	registerGetReport(s)
	registerCompareReports(s)
}

// toJSON marshals data to indented JSON string
func toJSON(v interface{}) (string, error) {
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// =============================================================================
// Primary Tools
// =============================================================================

func registerGetSystemReport(s *server.MCPServer) {
	tool := mcp.NewTool("get_system_report",
		mcp.WithDescription("Get complete system state report including CPU, memory, disk, network, packages, services, security, hardware, and detected issues. This is the most comprehensive tool - use it when you need a full system overview."),
	)

	s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		report := collectors.CollectAll()
		jsonData, err := toJSON(report)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to serialize report: %v", err)), nil
		}
		return mcp.NewToolResultText(jsonData), nil
	})
}

func registerGetIssues(s *server.MCPServer) {
	tool := mcp.NewTool("get_issues",
		mcp.WithDescription("Get detected system issues with severity levels. Returns problems found during system analysis with recommended fixes."),
		mcp.WithString("severity",
			mcp.Description("Filter by severity level: 'critical', 'warning', or 'info'. Leave empty for all issues."),
		),
	)

	s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		report := collectors.CollectAll()

		// Get optional severity filter
		args := req.GetArguments()
		severityFilter, _ := args["severity"].(string)
		severityFilter = strings.ToLower(severityFilter)

		var filtered []models.Issue
		for _, issue := range report.Issues {
			if severityFilter == "" || issue.Severity == severityFilter {
				filtered = append(filtered, issue)
			}
		}

		result := map[string]interface{}{
			"total":  len(filtered),
			"issues": filtered,
		}

		jsonData, err := toJSON(result)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to serialize issues: %v", err)), nil
		}
		return mcp.NewToolResultText(jsonData), nil
	})
}

// =============================================================================
// Granular Collectors
// =============================================================================

func registerGetSystemInfo(s *server.MCPServer) {
	tool := mcp.NewTool("get_system_info",
		mcp.WithDescription("Get CPU, memory, swap, load average, and uptime information."),
	)

	s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		result := map[string]interface{}{
			"hostname": collectors.GetHostname(),
			"os":       collectors.CollectOSInfo(),
			"system":   collectors.CollectSystemInfo(),
		}

		jsonData, err := toJSON(result)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to serialize: %v", err)), nil
		}
		return mcp.NewToolResultText(jsonData), nil
	})
}

func registerGetDiskInfo(s *server.MCPServer) {
	tool := mcp.NewTool("get_disk_info",
		mcp.WithDescription("Get filesystem usage information including size, used, free space, and inode usage."),
		mcp.WithString("mount_point",
			mcp.Description("Filter to specific mount point (e.g., '/', '/home'). Leave empty for all filesystems."),
		),
	)

	s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		diskInfo := collectors.CollectDiskInfo()

		// Get optional mount point filter
		args := req.GetArguments()
		mountFilter, _ := args["mount_point"].(string)

		if mountFilter != "" {
			var filtered []models.Filesystem
			for _, fs := range diskInfo.Filesystems {
				if fs.MountPoint == mountFilter {
					filtered = append(filtered, fs)
				}
			}
			if len(filtered) == 0 {
				return mcp.NewToolResultError(fmt.Sprintf("Mount point '%s' not found", mountFilter)), nil
			}
			diskInfo.Filesystems = filtered
		}

		jsonData, err := toJSON(diskInfo)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to serialize: %v", err)), nil
		}
		return mcp.NewToolResultText(jsonData), nil
	})
}

func registerGetNetworkInfo(s *server.MCPServer) {
	tool := mcp.NewTool("get_network_info",
		mcp.WithDescription("Get network interface status, IP addresses, listening ports, and connectivity information."),
	)

	s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		networkInfo := collectors.CollectNetworkInfo()

		jsonData, err := toJSON(networkInfo)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to serialize: %v", err)), nil
		}
		return mcp.NewToolResultText(jsonData), nil
	})
}

func registerGetPackageInfo(s *server.MCPServer) {
	tool := mcp.NewTool("get_package_info",
		mcp.WithDescription("Get APT package status including available updates, security updates, broken packages, and held packages."),
	)

	s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		packageInfo := collectors.CollectPackageInfo()

		jsonData, err := toJSON(packageInfo)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to serialize: %v", err)), nil
		}
		return mcp.NewToolResultText(jsonData), nil
	})
}

func registerGetServiceInfo(s *server.MCPServer) {
	tool := mcp.NewTool("get_service_info",
		mcp.WithDescription("Get systemd service status including failed units, zombie processes, and top CPU/memory consuming processes."),
	)

	s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		serviceInfo := collectors.CollectServiceInfo()

		jsonData, err := toJSON(serviceInfo)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to serialize: %v", err)), nil
		}
		return mcp.NewToolResultText(jsonData), nil
	})
}

func registerGetSecurityInfo(s *server.MCPServer) {
	tool := mcp.NewTool("get_security_info",
		mcp.WithDescription("Get security status including firewall state, SSH status, failed login attempts, and open ports."),
	)

	s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		securityInfo := collectors.CollectSecurityInfo()

		jsonData, err := toJSON(securityInfo)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to serialize: %v", err)), nil
		}
		return mcp.NewToolResultText(jsonData), nil
	})
}

func registerGetHardwareInfo(s *server.MCPServer) {
	tool := mcp.NewTool("get_hardware_info",
		mcp.WithDescription("Get hardware health including battery status/health, temperature sensors, and crash reports."),
	)

	s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		hardwareInfo := collectors.CollectHardwareInfo()

		jsonData, err := toJSON(hardwareInfo)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to serialize: %v", err)), nil
		}
		return mcp.NewToolResultText(jsonData), nil
	})
}

// =============================================================================
// History Tools
// =============================================================================

func registerListReports(s *server.MCPServer) {
	tool := mcp.NewTool("list_reports",
		mcp.WithDescription("List saved system reports from history. Reports are saved automatically and can be loaded or compared."),
		mcp.WithNumber("limit",
			mcp.Description("Maximum number of reports to return (default: 10, max: 100)"),
		),
	)

	s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		reports, err := history.List()
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to list reports: %v", err)), nil
		}

		// Get limit
		args := req.GetArguments()
		limit := 10
		if l, ok := args["limit"].(float64); ok && l > 0 {
			limit = int(l)
			if limit > 100 {
				limit = 100
			}
		}

		// Apply limit
		if len(reports) > limit {
			reports = reports[:limit]
		}

		// Convert to simpler format
		var result []map[string]interface{}
		for _, r := range reports {
			result = append(result, map[string]interface{}{
				"id":        r.ID,
				"timestamp": r.Timestamp.Format("2006-01-02 15:04:05"),
			})
		}

		jsonData, err := toJSON(map[string]interface{}{
			"total":   len(result),
			"reports": result,
		})
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to serialize: %v", err)), nil
		}
		return mcp.NewToolResultText(jsonData), nil
	})
}

func registerGetReport(s *server.MCPServer) {
	tool := mcp.NewTool("get_report",
		mcp.WithDescription("Load a saved system report by ID. Use list_reports to see available report IDs."),
		mcp.WithString("id",
			mcp.Required(),
			mcp.Description("Report ID (timestamp format: 2006-01-02T15-04-05)"),
		),
	)

	s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		id, err := req.RequireString("id")
		if err != nil {
			return mcp.NewToolResultError("Report ID is required"), nil
		}

		report, err := history.Load(id)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to load report: %v", err)), nil
		}

		jsonData, err := toJSON(report)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to serialize: %v", err)), nil
		}
		return mcp.NewToolResultText(jsonData), nil
	})
}

func registerCompareReports(s *server.MCPServer) {
	tool := mcp.NewTool("compare_reports",
		mcp.WithDescription("Compare two system reports to see what changed. Use 'current' as new_id to compare with current system state."),
		mcp.WithString("old_id",
			mcp.Required(),
			mcp.Description("ID of the older report to compare from"),
		),
		mcp.WithString("new_id",
			mcp.Required(),
			mcp.Description("ID of the newer report, or 'current' for current system state"),
		),
	)

	s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		oldID, err := req.RequireString("old_id")
		if err != nil {
			return mcp.NewToolResultError("old_id is required"), nil
		}

		newID, err := req.RequireString("new_id")
		if err != nil {
			return mcp.NewToolResultError("new_id is required"), nil
		}

		// Load old report
		oldReport, err := history.Load(oldID)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to load old report: %v", err)), nil
		}

		// Load or collect new report
		var newReport *models.Report
		if strings.ToLower(newID) == "current" {
			newReport = collectors.CollectAll()
		} else {
			newReport, err = history.Load(newID)
			if err != nil {
				return mcp.NewToolResultError(fmt.Sprintf("Failed to load new report: %v", err)), nil
			}
		}

		// Compare
		comparison := history.Compare(oldReport, newReport)

		result := map[string]interface{}{
			"old_timestamp": comparison.OldTimestamp.Format("2006-01-02 15:04:05"),
			"new_timestamp": comparison.NewTimestamp.Format("2006-01-02 15:04:05"),
			"changes_count": len(comparison.Changes),
			"changes":       comparison.Changes,
		}

		jsonData, err := toJSON(result)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to serialize: %v", err)), nil
		}
		return mcp.NewToolResultText(jsonData), nil
	})
}
