package httpserver

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

// Run starts the HTTP server on the specified port
func Run(port string) error {
	mux := http.NewServeMux()

	// Web dashboard at root
	mux.HandleFunc("/", handleDashboard)

	// Health check
	mux.HandleFunc("/health", handleHealth)

	// Full report
	mux.HandleFunc("/api/report", handleReport)

	// Individual collectors
	mux.HandleFunc("/api/issues", handleIssues)
	mux.HandleFunc("/api/system", handleSystem)
	mux.HandleFunc("/api/disk", handleDisk)
	mux.HandleFunc("/api/network", handleNetwork)
	mux.HandleFunc("/api/packages", handlePackages)
	mux.HandleFunc("/api/services", handleServices)
	mux.HandleFunc("/api/security", handleSecurity)
	mux.HandleFunc("/api/hardware", handleHardware)
	mux.HandleFunc("/api/docker", handleDocker)
	mux.HandleFunc("/api/snaps", handleSnaps)
	mux.HandleFunc("/api/gpu", handleGPU)
	mux.HandleFunc("/api/logs", handleLogs)

	// Config
	mux.HandleFunc("/api/config", handleConfig)

	// Prometheus metrics
	mux.HandleFunc("/metrics", handlePrometheus)

	server := &http.Server{
		Addr:         ":" + port,
		Handler:      withCORS(mux),
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 60 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	// Graceful shutdown
	shutdownChan := make(chan struct{})
	go func() {
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
		<-sigChan

		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		if err := server.Shutdown(ctx); err != nil {
			fmt.Fprintf(os.Stderr, "HTTP server shutdown error: %v\n", err)
		}
		close(shutdownChan)
	}()

	fmt.Printf("HTTP server listening on http://localhost:%s\n", port)
	fmt.Printf("Endpoints:\n")
	fmt.Printf("  GET /              - Web dashboard (HTML, auto-refresh)\n")
	fmt.Printf("  GET /health        - Health check\n")
	fmt.Printf("  GET /api/report    - Full system report\n")
	fmt.Printf("  GET /api/issues    - Detected issues (?severity=critical|warning|info)\n")
	fmt.Printf("  GET /api/system    - CPU, memory, load\n")
	fmt.Printf("  GET /api/disk      - Filesystem usage (?mount=/)\n")
	fmt.Printf("  GET /api/network   - Interfaces, ports\n")
	fmt.Printf("  GET /api/packages  - APT status\n")
	fmt.Printf("  GET /api/services  - Systemd, processes\n")
	fmt.Printf("  GET /api/security  - Firewall, SSH\n")
	fmt.Printf("  GET /api/hardware  - Battery, temps\n")
	fmt.Printf("  GET /api/docker    - Containers, images\n")
	fmt.Printf("  GET /api/snaps     - Snap packages\n")
	fmt.Printf("  GET /api/gpu       - GPU stats\n")
	fmt.Printf("  GET /api/logs      - Log analysis\n")
	fmt.Printf("  GET /api/config    - Current thresholds\n")
	fmt.Printf("  GET /metrics       - Prometheus metrics\n")
	fmt.Println("\nPress Ctrl+C to stop")

	err := server.ListenAndServe()
	if err == http.ErrServerClosed {
		<-shutdownChan
		fmt.Println("\nHTTP server stopped gracefully")
		return nil
	}
	return err
}

// withCORS adds CORS headers to allow cross-origin requests
func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		next.ServeHTTP(w, r)
	})
}
