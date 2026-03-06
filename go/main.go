package main

import (
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"machinestate/collectors"
	"machinestate/config"
	"machinestate/httpserver"
	"machinestate/mcpserver"
	"machinestate/outputs"
)

var (
	formatFlag      = flag.String("format", "terminal", "Output format: terminal, html, json, markdown, all")
	outputFlag      = flag.String("output", "", "Output file path (default: stdout for all formats)")
	quietFlag       = flag.Bool("quiet", false, "Suppress terminal output when using --format all")
	jsonCompactFlag = flag.Bool("json-compact", false, "Output minified JSON (single line)")
	streamFlag      = flag.Bool("stream", false, "Enable continuous streaming mode (JSONL output)")
	intervalFlag    = flag.Int("interval", 5, "Interval between streaming cycles in seconds")
	durationFlag    = flag.Int("duration", 0, "Maximum streaming duration in seconds (0 = infinite)")
	countFlag       = flag.Int("count", 0, "Number of streaming cycles (0 = infinite)")
	collectorsFlag  = flag.String("collectors", "", "Comma-separated collectors to stream (empty = all)")
	configFlag      = flag.String("config", "", "Path to config file (default: ~/.config/machinestate/config.yaml)")
	httpFlag        = flag.String("http", "", "Run HTTP server on port (e.g., 8080)")
	versionFlag     = flag.Bool("version", false, "Show version")
	mcpFlag         = flag.Bool("mcp", false, "Run as MCP server (stdio transport for Claude Code integration)")
)

const version = "1.0.0"

func main() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "machinestate - Real-time system state reporter\n\n")
		fmt.Fprintf(os.Stderr, "Usage:\n")
		fmt.Fprintf(os.Stderr, "  machinestate [options]              Generate system report\n")
		fmt.Fprintf(os.Stderr, "  machinestate --stream               Continuous streaming mode\n")
		fmt.Fprintf(os.Stderr, "  machinestate --http 8080            Run HTTP server\n")
		fmt.Fprintf(os.Stderr, "  machinestate --mcp                  Run as MCP server (for Claude Code)\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		flag.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  machinestate                                    Terminal output (default)\n")
		fmt.Fprintf(os.Stderr, "  machinestate --format json                      JSON output to stdout\n")
		fmt.Fprintf(os.Stderr, "  machinestate --stream                           Stream all collectors every 5s\n")
		fmt.Fprintf(os.Stderr, "  machinestate --stream --interval 10             Stream every 10 seconds\n")
		fmt.Fprintf(os.Stderr, "  machinestate --stream --collectors system,disk  Stream specific collectors\n")
		fmt.Fprintf(os.Stderr, "  machinestate --stream --count 10                Stream 10 cycles then stop\n")
		fmt.Fprintf(os.Stderr, "  machinestate --stream --duration 3600           Stream for 1 hour\n")
		fmt.Fprintf(os.Stderr, "  machinestate --http 8080                        Start HTTP server on port 8080\n")
		fmt.Fprintf(os.Stderr, "\nMCP Server:\n")
		fmt.Fprintf(os.Stderr, "  Configure in Claude Code with:\n")
		fmt.Fprintf(os.Stderr, "  claude mcp add-json machinestate '{\"type\":\"stdio\",\"command\":\"/path/to/machinestate\",\"args\":[\"--mcp\"]}'\n")
	}

	flag.Parse()

	if *versionFlag {
		fmt.Printf("machinestate version %s\n", version)
		os.Exit(0)
	}

	// Initialize configuration
	config.Init(*configFlag)

	// Run as MCP server if --mcp flag is set
	if *mcpFlag {
		if err := mcpserver.Run(); err != nil {
			fmt.Fprintf(os.Stderr, "MCP server error: %v\n", err)
			os.Exit(1)
		}
		return
	}

	// Run as HTTP server if --http flag is set
	if *httpFlag != "" {
		if err := httpserver.Run(*httpFlag); err != nil && err != http.ErrServerClosed {
			fmt.Fprintf(os.Stderr, "HTTP server error: %v\n", err)
			os.Exit(1)
		}
		return
	}

	// Handle streaming mode
	if *streamFlag {
		runContinuousStreaming(*intervalFlag, *durationFlag, *countFlag, *collectorsFlag)
		return
	}

	// Collect system information (one-shot)
	report := collectors.CollectAll()

	// Generate output based on format
	format := strings.ToLower(*formatFlag)

	switch format {
	case "terminal":
		fmt.Print(outputs.RenderTerminal(report))

	case "json":
		var output string
		var err error
		if *jsonCompactFlag {
			output, err = outputs.RenderJSONCompact(report)
		} else {
			output, err = outputs.RenderJSON(report)
		}
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error generating JSON: %v\n", err)
			os.Exit(1)
		}
		if *outputFlag != "" {
			writeFile(*outputFlag, output)
		} else {
			fmt.Println(output)
		}

	case "markdown", "md":
		output := outputs.RenderMarkdown(report)
		if *outputFlag != "" {
			writeFile(*outputFlag, output)
		} else {
			fmt.Print(output)
		}

	case "html":
		output, err := outputs.RenderHTML(report)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error generating HTML: %v\n", err)
			os.Exit(1)
		}
		if *outputFlag != "" {
			writeFile(*outputFlag, output)
		} else {
			fmt.Print(output)
		}

	case "all":
		// Generate all formats
		baseDir := "."
		if *outputFlag != "" {
			baseDir = *outputFlag
			os.MkdirAll(baseDir, 0755)
		}

		// Terminal (print unless quiet)
		if !*quietFlag {
			fmt.Print(outputs.RenderTerminal(report))
		}

		// JSON
		jsonOut, _ := outputs.RenderJSON(report)
		writeFile(baseDir+"/system-report.json", jsonOut)

		// Markdown
		mdOut := outputs.RenderMarkdown(report)
		writeFile(baseDir+"/system-report.md", mdOut)

		// HTML
		htmlOut, _ := outputs.RenderHTML(report)
		writeFile(baseDir+"/system-report.html", htmlOut)

		fmt.Printf("\nReports saved:\n")
		fmt.Printf("  - %s/system-report.json\n", baseDir)
		fmt.Printf("  - %s/system-report.md\n", baseDir)
		fmt.Printf("  - %s/system-report.html\n", baseDir)

	default:
		fmt.Fprintf(os.Stderr, "Unknown format: %s\n", format)
		os.Exit(1)
	}
}

func writeFile(path, content string) {
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		fmt.Fprintf(os.Stderr, "Error writing %s: %v\n", path, err)
		os.Exit(1)
	}
}

// runContinuousStreaming runs the streaming loop with signal handling
func runContinuousStreaming(intervalSecs, durationSecs, maxCount int, collectorsStr string) {
	// Parse collector filter
	filter := parseCollectorFilter(collectorsStr)

	// Set up signal handling for graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	// Track start time for duration limit
	startTime := time.Now()
	cycle := 0

	// Convert seconds to duration
	interval := time.Duration(intervalSecs) * time.Second
	maxDuration := time.Duration(durationSecs) * time.Second

	// Create ticker for interval (first collection is immediate)
	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	// Run first cycle immediately
	runStreamingCycle := func() bool {
		cycle++

		// Emit cycle start marker
		cycleStart := fmt.Sprintf(`{"_cycle":%d,"_timestamp":"%s"}`, cycle, time.Now().Format(time.RFC3339))
		fmt.Println(cycleStart)

		// Collect and stream data
		collectors.CollectAllStreaming(func(result collectors.CollectorResult) error {
			// Apply filter if set
			if len(filter) > 0 && !filter[result.Collector] {
				return nil
			}
			jsonData, err := outputs.RenderJSONFromInterface(result)
			if err != nil {
				return err
			}
			fmt.Println(jsonData)
			return nil
		})

		// Emit cycle complete marker
		cycleComplete := fmt.Sprintf(`{"_cycle_complete":%d}`, cycle)
		fmt.Println(cycleComplete)

		// Check count limit
		if maxCount > 0 && cycle >= maxCount {
			return false
		}

		// Check duration limit
		if durationSecs > 0 && time.Since(startTime) >= maxDuration {
			return false
		}

		return true
	}

	// Run first cycle immediately
	if !runStreamingCycle() {
		emitShutdownMarker(cycle)
		return
	}

	// Main loop
	for {
		select {
		case <-sigChan:
			// Graceful shutdown on signal
			emitShutdownMarker(cycle)
			return
		case <-ticker.C:
			if !runStreamingCycle() {
				emitShutdownMarker(cycle)
				return
			}
		}
	}
}

// parseCollectorFilter parses comma-separated collector names into a filter map
func parseCollectorFilter(collectorsStr string) map[string]bool {
	filter := make(map[string]bool)
	if collectorsStr == "" {
		return filter // Empty means all collectors
	}

	validCollectors := map[string]bool{
		"os": true, "system": true, "disk": true, "network": true,
		"packages": true, "services": true, "security": true, "hardware": true,
		"docker": true, "snaps": true, "gpu": true, "logs": true, "issues": true,
	}

	parts := strings.Split(collectorsStr, ",")
	for _, part := range parts {
		name := strings.TrimSpace(strings.ToLower(part))
		if validCollectors[name] {
			filter[name] = true
		}
	}

	// Always include issues if other collectors are selected
	if len(filter) > 0 {
		filter["issues"] = true
	}

	return filter
}

// emitShutdownMarker outputs the shutdown marker with total cycle count
func emitShutdownMarker(totalCycles int) {
	shutdown := fmt.Sprintf(`{"_shutdown":true,"_total_cycles":%d,"_timestamp":"%s"}`,
		totalCycles, time.Now().Format(time.RFC3339))
	fmt.Println(shutdown)
}
