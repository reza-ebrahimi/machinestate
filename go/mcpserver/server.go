package mcpserver

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"

	"machinestate/collectors"
	"machinestate/models"
)

// Run starts the MCP server using stdio transport
func Run() error {
	s := NewServer()
	return server.ServeStdio(s)
}

// NewServer creates a new MCP server with all tools registered
func NewServer() *server.MCPServer {
	s := server.NewMCPServer(
		"machinestate",
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
	registerStreamSystemReport(s)

	// Granular collectors
	registerGetSystemInfo(s)
	registerGetDiskInfo(s)
	registerGetNetworkInfo(s)
	registerGetPackageInfo(s)
	registerGetServiceInfo(s)
	registerGetSecurityInfo(s)
	registerGetHardwareInfo(s)
	registerGetDockerInfo(s)
	registerGetSnapInfo(s)
	registerGetGPUInfo(s)
	registerGetLogInfo(s)
}

// toJSON marshals data to indented JSON string
func toJSON(v interface{}) (string, error) {
	data, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// toJSONCompact marshals data to compact JSON string
func toJSONCompact(v interface{}) (string, error) {
	data, err := json.Marshal(v)
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

		// Return just the array
		jsonData, err := toJSON(filtered)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to serialize issues: %v", err)), nil
		}
		return mcp.NewToolResultText(jsonData), nil
	})
}

func registerStreamSystemReport(s *server.MCPServer) {
	tool := mcp.NewTool("stream_system_report",
		mcp.WithDescription("Stream system report data as each collector completes. Returns JSONL format (one JSON object per line) for real-time data as collectors finish."),
		mcp.WithArray("collectors",
			mcp.Description("Optional: specific collectors to run. Valid values: os, system, disk, network, packages, services, security, hardware, docker, snaps, gpu, logs. Leave empty for all."),
		),
	)

	s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		// Get optional collectors filter
		args := req.GetArguments()
		var collectorsFilter []string
		if arr, ok := args["collectors"].([]interface{}); ok {
			for _, v := range arr {
				if s, ok := v.(string); ok {
					collectorsFilter = append(collectorsFilter, strings.ToLower(s))
				}
			}
		}

		// Build filter set
		filterSet := make(map[string]bool)
		for _, c := range collectorsFilter {
			filterSet[c] = true
		}
		hasFilter := len(filterSet) > 0

		// Collect with streaming callback, building JSONL output
		var lines []string
		collectors.CollectAllStreaming(func(result collectors.CollectorResult) error {
			// Apply filter if specified
			if hasFilter && !filterSet[result.Collector] {
				return nil
			}
			line, err := toJSONCompact(result)
			if err != nil {
				return err
			}
			lines = append(lines, line)
			return nil
		})

		// Add completion marker
		lines = append(lines, `{"_complete":true}`)

		// Return JSONL (newline-separated JSON objects)
		return mcp.NewToolResultText(strings.Join(lines, "\n")), nil
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
		systemInfo := collectors.CollectSystemInfo()

		jsonData, err := toJSON(systemInfo)
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

func registerGetDockerInfo(s *server.MCPServer) {
	tool := mcp.NewTool("get_docker_info",
		mcp.WithDescription("Get Docker container and image information including running/stopped containers, images, and disk usage."),
	)

	s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		dockerInfo := collectors.CollectDockerInfo()

		jsonData, err := toJSON(dockerInfo)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to serialize: %v", err)), nil
		}
		return mcp.NewToolResultText(jsonData), nil
	})
}

func registerGetSnapInfo(s *server.MCPServer) {
	tool := mcp.NewTool("get_snap_info",
		mcp.WithDescription("Get Snap package information including installed snaps, disk usage, and pending refreshes."),
	)

	s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		snapInfo := collectors.CollectSnapInfo()

		jsonData, err := toJSON(snapInfo)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to serialize: %v", err)), nil
		}
		return mcp.NewToolResultText(jsonData), nil
	})
}

func registerGetGPUInfo(s *server.MCPServer) {
	tool := mcp.NewTool("get_gpu_info",
		mcp.WithDescription("Get GPU information including temperature, utilization, and memory usage for NVIDIA, AMD, or Intel GPUs."),
	)

	s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		gpuInfo := collectors.CollectGPUInfo()

		jsonData, err := toJSON(gpuInfo)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to serialize: %v", err)), nil
		}
		return mcp.NewToolResultText(jsonData), nil
	})
}

func registerGetLogInfo(s *server.MCPServer) {
	tool := mcp.NewTool("get_log_info",
		mcp.WithDescription("Get log analysis for the last 24 hours including error counts, OOM events, kernel panics, and top error patterns."),
	)

	s.AddTool(tool, func(ctx context.Context, req mcp.CallToolRequest) (*mcp.CallToolResult, error) {
		logInfo := collectors.CollectLogInfo()

		jsonData, err := toJSON(logInfo)
		if err != nil {
			return mcp.NewToolResultError(fmt.Sprintf("Failed to serialize: %v", err)), nil
		}
		return mcp.NewToolResultText(jsonData), nil
	})
}
