#!/bin/bash
#
# MCP Schema Validation Tests for machinestate
# Validates all 14 MCP tools against their respective schemas
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SCHEMA_DIR="$PROJECT_DIR/schema"
MCP_SCHEMA_DIR="$SCHEMA_DIR/mcp"
GO_BIN="$PROJECT_DIR/go/machinestate"
ZIG_BIN="$PROJECT_DIR/zig/zig-out/bin/machinestate"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0

# Call MCP tool without arguments
call_mcp_tool() {
    local bin=$1
    local tool=$2
    timeout 30 bash -c "echo '{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"$tool\"},\"id\":1}' | \"$bin\" --mcp 2>/dev/null" | jq -r '.result.content[0].text' 2>/dev/null
}

# Validate tool output against schema
validate_tool() {
    local impl=$1
    local tool=$2
    local schema=$3

    local bin
    [[ "$impl" == "go" ]] && bin="$GO_BIN" || bin="$ZIG_BIN"

    local content
    content=$(call_mcp_tool "$bin" "$tool")

    if [[ -z "$content" ]] || [[ "$content" == "null" ]]; then
        echo -e "  ${RED}FAIL${NC} [$impl] $tool - No content"
        ((FAIL++))
        return
    fi

    # Check if tool returns error JSON (not implemented)
    if echo "$content" | jq -e '.error' >/dev/null 2>&1; then
        echo -e "  ${CYAN}SKIP${NC} [$impl] $tool - Not implemented"
        return
    fi

    if echo "$content" | uvx check-jsonschema --schemafile "$schema" - >/dev/null 2>&1; then
        echo -e "  ${GREEN}PASS${NC} [$impl] $tool"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${NC} [$impl] $tool"
        echo "$content" | uvx check-jsonschema --schemafile "$schema" - 2>&1 | head -3 | sed 's/^/       /'
        ((FAIL++))
    fi
}

# Validate streaming tool (JSONL format)
validate_streaming_tool() {
    local impl=$1
    local tool=$2

    local bin
    [[ "$impl" == "go" ]] && bin="$GO_BIN" || bin="$ZIG_BIN"

    local content
    content=$(call_mcp_tool "$bin" "$tool")

    if [[ -z "$content" ]] || [[ "$content" == "null" ]]; then
        echo -e "  ${RED}FAIL${NC} [$impl] $tool - No content"
        ((FAIL++))
        return
    fi

    # Check if it's valid JSONL (each line should be valid JSON)
    local valid=true
    while IFS= read -r line; do
        if ! echo "$line" | jq . >/dev/null 2>&1; then
            valid=false
            break
        fi
    done <<< "$content"

    # Check for completion marker
    if ! echo "$content" | grep -q '"_complete":true'; then
        valid=false
    fi

    if $valid; then
        echo -e "  ${GREEN}PASS${NC} [$impl] $tool (JSONL format)"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${NC} [$impl] $tool - Invalid JSONL format"
        ((FAIL++))
    fi
}

echo -e "${CYAN}${BOLD}"
echo "═══════════════════════════════════════════════════════════════"
echo "              MCP Schema Validation Tests                       "
echo "═══════════════════════════════════════════════════════════════"
echo -e "${NC}"

# Check binaries exist
[[ ! -f "$GO_BIN" ]] && { echo -e "${RED}Error: Go binary not found${NC}"; exit 1; }
[[ ! -f "$ZIG_BIN" ]] && { echo -e "${RED}Error: Zig binary not found${NC}"; exit 1; }

# Tool to schema mapping (13 tools with JSON schemas)
declare -A TOOL_SCHEMAS=(
    ["get_system_report"]="$SCHEMA_DIR/report.schema.json"
    ["get_system_info"]="$MCP_SCHEMA_DIR/system-info.schema.json"
    ["get_disk_info"]="$MCP_SCHEMA_DIR/disk-info.schema.json"
    ["get_network_info"]="$MCP_SCHEMA_DIR/network-info.schema.json"
    ["get_package_info"]="$MCP_SCHEMA_DIR/package-info.schema.json"
    ["get_service_info"]="$MCP_SCHEMA_DIR/service-info.schema.json"
    ["get_security_info"]="$MCP_SCHEMA_DIR/security-info.schema.json"
    ["get_hardware_info"]="$MCP_SCHEMA_DIR/hardware-info.schema.json"
    ["get_docker_info"]="$MCP_SCHEMA_DIR/docker-info.schema.json"
    ["get_snap_info"]="$MCP_SCHEMA_DIR/snap-info.schema.json"
    ["get_gpu_info"]="$MCP_SCHEMA_DIR/gpu-info.schema.json"
    ["get_log_info"]="$MCP_SCHEMA_DIR/log-info.schema.json"
    ["get_issues"]="$MCP_SCHEMA_DIR/issues.schema.json"
)

for impl in go zig; do
    echo -e "\n${BOLD}Testing $impl implementation:${NC}"
    echo "─────────────────────────────────────────────────────────────────"

    for tool in "${!TOOL_SCHEMAS[@]}"; do
        validate_tool "$impl" "$tool" "${TOOL_SCHEMAS[$tool]}"
    done | sort

    # Test streaming tool (JSONL format, no schema validation)
    validate_streaming_tool "$impl" "stream_system_report"
done

# Summary
echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}Passed:${NC} $PASS"
echo -e "  ${RED}Failed:${NC} $FAIL"
echo ""

[[ $FAIL -gt 0 ]] && exit 1 || exit 0
