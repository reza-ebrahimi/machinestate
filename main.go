package main

import (
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/fatih/color"

	"ubuntu-state/collectors"
	"ubuntu-state/config"
	"ubuntu-state/history"
	"ubuntu-state/mcpserver"
	"ubuntu-state/outputs"
)

var (
	formatFlag      = flag.String("format", "terminal", "Output format: terminal, html, json, markdown, all")
	outputFlag      = flag.String("output", "", "Output file path (default: stdout for terminal/json/markdown, report.html for html)")
	compareFlag     = flag.Bool("compare", false, "Compare with the last saved report")
	noSaveFlag      = flag.Bool("no-save", false, "Don't save this report to history")
	quietFlag       = flag.Bool("quiet", false, "Suppress terminal output when using --format all")
	jsonCompactFlag = flag.Bool("json-compact", false, "Output minified JSON (single line)")
	configFlag      = flag.String("config", "", "Path to config file (default: ~/.config/ubuntu-state/config.yaml)")
	versionFlag     = flag.Bool("version", false, "Show version")
	mcpFlag         = flag.Bool("mcp", false, "Run as MCP server (stdio transport for Claude Code integration)")
)

const version = "1.0.0"

func main() {
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "ubuntu-state - System state reporter\n\n")
		fmt.Fprintf(os.Stderr, "Usage:\n")
		fmt.Fprintf(os.Stderr, "  ubuntu-state [options]              Generate system report\n")
		fmt.Fprintf(os.Stderr, "  ubuntu-state --mcp                  Run as MCP server (for Claude Code)\n")
		fmt.Fprintf(os.Stderr, "  ubuntu-state history list           List saved reports\n")
		fmt.Fprintf(os.Stderr, "  ubuntu-state history compare <id>   Compare current with saved report\n")
		fmt.Fprintf(os.Stderr, "  ubuntu-state history show <id>      Show a saved report\n\n")
		fmt.Fprintf(os.Stderr, "Options:\n")
		flag.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nExamples:\n")
		fmt.Fprintf(os.Stderr, "  ubuntu-state                        Terminal output (default)\n")
		fmt.Fprintf(os.Stderr, "  ubuntu-state --format html          Generate HTML report\n")
		fmt.Fprintf(os.Stderr, "  ubuntu-state --format all           Generate all formats\n")
		fmt.Fprintf(os.Stderr, "  ubuntu-state --compare              Compare with last report\n")
		fmt.Fprintf(os.Stderr, "\nMCP Server:\n")
		fmt.Fprintf(os.Stderr, "  Configure in Claude Code with:\n")
		fmt.Fprintf(os.Stderr, "  claude mcp add-json ubuntu-state '{\"type\":\"stdio\",\"command\":\"/path/to/ubuntu-state\",\"args\":[\"--mcp\"]}'\n")
	}

	flag.Parse()

	if *versionFlag {
		fmt.Printf("ubuntu-state version %s\n", version)
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

	// Handle subcommands
	args := flag.Args()
	if len(args) > 0 {
		switch args[0] {
		case "history":
			handleHistory(args[1:])
			return
		}
	}

	// Collect system information
	report := collectors.CollectAll()

	// Save to history unless disabled
	if !*noSaveFlag {
		if err := history.Save(report); err != nil {
			fmt.Fprintf(os.Stderr, "Warning: failed to save to history: %v\n", err)
		}
	}

	// Handle comparison
	if *compareFlag {
		reports, err := history.List()
		if err != nil || len(reports) < 2 {
			fmt.Fprintln(os.Stderr, "Not enough history to compare (need at least 2 reports)")
		} else {
			// Compare with the second most recent (since we just saved the current one)
			old, err := history.Load(reports[1].ID)
			if err == nil {
				printComparison(history.Compare(old, report))
			}
		}
	}

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
		filename := *outputFlag
		if filename == "" {
			filename = "system-report.html"
		}
		writeFile(filename, output)
		fmt.Printf("HTML report saved to: %s\n", filename)

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

func handleHistory(args []string) {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "Usage: ubuntu-state history <list|compare|show> [id]")
		os.Exit(1)
	}

	switch args[0] {
	case "list":
		reports, err := history.List()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error listing history: %v\n", err)
			os.Exit(1)
		}
		if len(reports) == 0 {
			fmt.Println("No saved reports found.")
			return
		}
		fmt.Printf("%-25s  %s\n", "ID", "TIMESTAMP")
		fmt.Println(strings.Repeat("-", 50))
		for _, r := range reports {
			fmt.Printf("%-25s  %s\n", r.ID, r.Timestamp.Format("2006-01-02 15:04:05"))
		}

	case "show":
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "Usage: ubuntu-state history show <id>")
			os.Exit(1)
		}
		report, err := history.Load(args[1])
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error loading report: %v\n", err)
			os.Exit(1)
		}
		fmt.Print(outputs.RenderTerminal(report))

	case "compare":
		if len(args) < 2 {
			// Compare latest with current
			old, err := history.GetLatest()
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				os.Exit(1)
			}
			new := collectors.CollectAll()
			printComparison(history.Compare(old, new))
		} else {
			// Compare specified report with current
			old, err := history.Load(args[1])
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error loading report: %v\n", err)
				os.Exit(1)
			}
			new := collectors.CollectAll()
			printComparison(history.Compare(old, new))
		}

	default:
		fmt.Fprintf(os.Stderr, "Unknown history command: %s\n", args[0])
		os.Exit(1)
	}
}

func printComparison(comp *history.Comparison) {
	headerStyle := color.New(color.FgCyan, color.Bold)
	changeStyle := color.New(color.FgYellow)
	goodStyle := color.New(color.FgGreen)
	badStyle := color.New(color.FgRed)

	fmt.Println()
	headerStyle.Println("═══════════════════════════════════════════════════════════════")
	headerStyle.Println("                     COMPARISON REPORT                          ")
	headerStyle.Println("═══════════════════════════════════════════════════════════════")
	fmt.Println()
	fmt.Printf("Old Report: %s\n", comp.OldTimestamp.Format("2006-01-02 15:04:05"))
	fmt.Printf("New Report: %s\n", comp.NewTimestamp.Format("2006-01-02 15:04:05"))
	fmt.Println()

	if len(comp.Changes) == 0 {
		goodStyle.Println("✓ No significant changes detected")
		return
	}

	fmt.Printf("%-12s  %-20s  %-12s  %-12s  %s\n", "CATEGORY", "ITEM", "OLD", "NEW", "DELTA")
	fmt.Println(strings.Repeat("-", 70))

	for _, change := range comp.Changes {
		deltaStyle := changeStyle
		if strings.Contains(change.Delta, "-") || change.Delta == "RESOLVED" {
			deltaStyle = goodStyle
		} else if strings.Contains(change.Delta, "+") || change.Delta == "NEW FAILURE" {
			deltaStyle = badStyle
		}

		fmt.Printf("%-12s  %-20s  %-12s  %-12s  ",
			change.Category, truncate(change.Item, 20), change.Old, change.New)
		deltaStyle.Printf("%s\n", change.Delta)
	}
	fmt.Println()
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max-3] + "..."
}

func writeFile(path, content string) {
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		fmt.Fprintf(os.Stderr, "Error writing %s: %v\n", path, err)
		os.Exit(1)
	}
}
