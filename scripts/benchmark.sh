#!/bin/bash
#
# Benchmark script for machinestate Go vs Zig implementations
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GO_BIN="$PROJECT_DIR/go/machinestate"
ZIG_BIN="$PROJECT_DIR/zig/zig-out/bin/machinestate"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${CYAN}${BOLD}"
echo "═══════════════════════════════════════════════════════════════"
echo "              machinestate Benchmark: Go vs Zig                  "
echo "═══════════════════════════════════════════════════════════════"
echo -e "${NC}"

# Check binaries exist
if [[ ! -f "$GO_BIN" ]]; then
    echo -e "${RED}Error: Go binary not found at $GO_BIN${NC}"
    echo "Run 'make go' first"
    exit 1
fi

if [[ ! -f "$ZIG_BIN" ]]; then
    echo -e "${RED}Error: Zig binary not found at $ZIG_BIN${NC}"
    echo "Run 'make zig' first"
    exit 1
fi

# Check hyperfine
if ! command -v hyperfine &> /dev/null; then
    echo -e "${RED}Error: hyperfine not installed${NC}"
    echo "Install with: sudo apt install hyperfine"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────
# Binary Size Comparison
# ─────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}${BOLD}1. Binary Size${NC}"
echo "─────────────────────────────────────────────────────────────────"

GO_SIZE=$(stat -c%s "$GO_BIN")
ZIG_SIZE=$(stat -c%s "$ZIG_BIN")
GO_SIZE_HR=$(numfmt --to=iec-i --suffix=B "$GO_SIZE")
ZIG_SIZE_HR=$(numfmt --to=iec-i --suffix=B "$ZIG_SIZE")

echo -e "  Go:  ${BOLD}$GO_SIZE_HR${NC} ($GO_SIZE bytes)"
echo -e "  Zig: ${BOLD}$ZIG_SIZE_HR${NC} ($ZIG_SIZE bytes)"

if [[ $ZIG_SIZE -lt $GO_SIZE ]]; then
    DIFF=$((GO_SIZE - ZIG_SIZE))
    PCT=$(echo "scale=1; ($DIFF * 100) / $GO_SIZE" | bc)
    echo -e "  ${GREEN}Zig is ${PCT}% smaller${NC}"
else
    DIFF=$((ZIG_SIZE - GO_SIZE))
    PCT=$(echo "scale=1; ($DIFF * 100) / $ZIG_SIZE" | bc)
    echo -e "  ${GREEN}Go is ${PCT}% smaller${NC}"
fi

# ─────────────────────────────────────────────────────────────────
# Startup Time (--version)
# ─────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}${BOLD}2. Startup Time (--version)${NC}"
echo "─────────────────────────────────────────────────────────────────"

hyperfine --warmup 5 --runs 20 \
    --export-json /tmp/bench_startup.json \
    -n "Go" "$GO_BIN --version" \
    -n "Zig" "$ZIG_BIN --version" \
    2>&1 | grep -E '(Benchmark|Time|Range|runs)'

# ─────────────────────────────────────────────────────────────────
# JSON Output (full report)
# ─────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}${BOLD}3. Full Report (JSON output)${NC}"
echo "─────────────────────────────────────────────────────────────────"

hyperfine --warmup 2 --runs 10 \
    --export-json /tmp/bench_json.json \
    -n "Go" "$GO_BIN --format json --no-save" \
    -n "Zig" "$ZIG_BIN --format json --no-save" \
    2>&1 | grep -E '(Benchmark|Time|Range|runs)'

# ─────────────────────────────────────────────────────────────────
# Terminal Output (full report)
# ─────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}${BOLD}4. Full Report (Terminal output)${NC}"
echo "─────────────────────────────────────────────────────────────────"

hyperfine --warmup 2 --runs 10 \
    --export-json /tmp/bench_terminal.json \
    -n "Go" "$GO_BIN --format terminal --no-save" \
    -n "Zig" "$ZIG_BIN --format terminal --no-save" \
    2>&1 | grep -E '(Benchmark|Time|Range|runs)'

# ─────────────────────────────────────────────────────────────────
# Memory Usage
# ─────────────────────────────────────────────────────────────────
echo -e "\n${YELLOW}${BOLD}5. Peak Memory Usage${NC}"
echo "─────────────────────────────────────────────────────────────────"

GO_MEM=$(/usr/bin/time -v "$GO_BIN" --format json --no-save 2>&1 >/dev/null | grep "Maximum resident set size" | awk '{print $6}')
ZIG_MEM=$(/usr/bin/time -v "$ZIG_BIN" --format json --no-save 2>&1 >/dev/null | grep "Maximum resident set size" | awk '{print $6}')

GO_MEM_HR=$(numfmt --to=iec-i --suffix=B $((GO_MEM * 1024)))
ZIG_MEM_HR=$(numfmt --to=iec-i --suffix=B $((ZIG_MEM * 1024)))

echo -e "  Go:  ${BOLD}$GO_MEM_HR${NC} ($GO_MEM KB)"
echo -e "  Zig: ${BOLD}$ZIG_MEM_HR${NC} ($ZIG_MEM KB)"

if [[ $ZIG_MEM -lt $GO_MEM ]]; then
    DIFF=$((GO_MEM - ZIG_MEM))
    PCT=$(echo "scale=1; ($DIFF * 100) / $GO_MEM" | bc)
    echo -e "  ${GREEN}Zig uses ${PCT}% less memory${NC}"
else
    DIFF=$((ZIG_MEM - GO_MEM))
    PCT=$(echo "scale=1; ($DIFF * 100) / $ZIG_MEM" | bc)
    echo -e "  ${GREEN}Go uses ${PCT}% less memory${NC}"
fi

# ─────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────
echo -e "\n${CYAN}${BOLD}"
echo "═══════════════════════════════════════════════════════════════"
echo "                         Summary                                "
echo "═══════════════════════════════════════════════════════════════"
echo -e "${NC}"

# Parse JSON results for summary
if command -v jq &> /dev/null; then
    echo -e "${BOLD}Execution Time (JSON output):${NC}"
    GO_TIME=$(jq -r '.results[] | select(.command | contains("Go")) | .mean' /tmp/bench_json.json)
    ZIG_TIME=$(jq -r '.results[] | select(.command | contains("Zig")) | .mean' /tmp/bench_json.json)

    GO_TIME_MS=$(echo "scale=1; $GO_TIME * 1000" | bc)
    ZIG_TIME_MS=$(echo "scale=1; $ZIG_TIME * 1000" | bc)

    echo -e "  Go:  ${GO_TIME_MS} ms"
    echo -e "  Zig: ${ZIG_TIME_MS} ms"

    if (( $(echo "$ZIG_TIME < $GO_TIME" | bc -l) )); then
        SPEEDUP=$(echo "scale=2; $GO_TIME / $ZIG_TIME" | bc)
        echo -e "  ${GREEN}Zig is ${SPEEDUP}x faster${NC}"
    else
        SPEEDUP=$(echo "scale=2; $ZIG_TIME / $GO_TIME" | bc)
        echo -e "  ${GREEN}Go is ${SPEEDUP}x faster${NC}"
    fi
fi

echo -e "\n${BOLD}| Metric | Go | Zig | Winner |${NC}"
echo "|--------|-----|------|--------|"
echo "| Binary Size | $GO_SIZE_HR | $ZIG_SIZE_HR | $(if [[ $ZIG_SIZE -lt $GO_SIZE ]]; then echo "Zig"; else echo "Go"; fi) |"
echo "| Peak Memory | $GO_MEM_HR | $ZIG_MEM_HR | $(if [[ $ZIG_MEM -lt $GO_MEM ]]; then echo "Zig"; else echo "Go"; fi) |"

echo -e "\n${CYAN}Detailed results saved to /tmp/bench_*.json${NC}"
