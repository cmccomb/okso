#!/usr/bin/env bash
# shellcheck shell=bash
#
# MCP client registrations for remote and local endpoints.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/mcp.sh}/tools/mcp.sh"
#
# Environment variables:
#   TOOL_QUERY (string): human query to forward to the MCP endpoint.
#   MCP_HUGGINGFACE_URL (string): remote Hugging Face MCP endpoint URL.
#   MCP_HUGGINGFACE_TOKEN_ENV (string): env var that stores the Hugging Face token.
#   MCP_LOCAL_SOCKET (string): unix socket or filesystem path for a local MCP server.
#
# Dependencies:
#   - bash 5+
#   - python 3+
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero when required configuration is missing.

# shellcheck source=../lib/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/mcp.sh}/lib/logging.sh"
# shellcheck source=./registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/mcp.sh}/registry.sh"

mcp_print_connection_json() {
	# Emit a JSON blob describing the resolved MCP transport without secrets.
	# Arguments:
	#   $1 - provider label (string)
	#   $2 - transport type (string)
	#   $3 - endpoint URL (string)
	#   $4 - socket path (string)
	#   $5 - token environment variable name (string)
	local provider transport endpoint socket_path token_env
	provider="$1"
	transport="$2"
	endpoint="$3"
	socket_path="$4"
	token_env="$5"

	MCP_PROVIDER="${provider}" \
		MCP_TRANSPORT="${transport}" \
		MCP_ENDPOINT="${endpoint}" \
		MCP_SOCKET="${socket_path}" \
		MCP_TOKEN_ENV="${token_env}" \
		MCP_QUERY="${TOOL_QUERY:-}" \
		python3 - <<'PY'
import json
import os

payload = {
    "provider": os.environ.get("MCP_PROVIDER", ""),
    "transport": os.environ.get("MCP_TRANSPORT", ""),
    "endpoint": os.environ.get("MCP_ENDPOINT", ""),
    "socket": os.environ.get("MCP_SOCKET", ""),
    "token_env": os.environ.get("MCP_TOKEN_ENV", ""),
    "query": os.environ.get("MCP_QUERY", ""),
}
print(json.dumps(payload, separators=(",", ":")))
PY
}

mcp_validate_remote_config() {
	local url token_env
	url="$1"
	token_env="$2"

	if [[ -z "${url}" ]]; then
		log "ERROR" "MCP remote endpoint not configured" ""
		return 1
	fi

	if [[ -z "${token_env}" ]]; then
		log "ERROR" "MCP token env var name missing" ""
		return 1
	fi

	if [[ -z "${!token_env:-}" ]]; then
		log "ERROR" "MCP token not exported" "${token_env}"
		return 1
	fi

	return 0
}

tool_mcp_huggingface() {
	# Connect to the configured remote MCP server hosted on Hugging Face.
	local url token_env
	url="${MCP_HUGGINGFACE_URL:-}"             # string remote endpoint
	token_env="${MCP_HUGGINGFACE_TOKEN_ENV:-}" # string token env var name

	if ! mcp_validate_remote_config "${url}" "${token_env}"; then
		return 1
	fi

	mcp_print_connection_json "huggingface" "http" "${url}" "" "${token_env}"
}

tool_mcp_local_server() {
	# Connect to a bundled local MCP server via socket or filesystem path.
	local socket_path
	socket_path="${MCP_LOCAL_SOCKET:-}" # string local socket path

	if [[ -z "${socket_path}" ]]; then
		log "ERROR" "Local MCP socket missing" ""
		return 1
	fi

	mcp_print_connection_json "local_demo" "unix" "" "${socket_path}" ""
}

register_mcp_endpoints() {
	register_tool \
		"mcp_huggingface" \
		"Connect to the configured Hugging Face MCP endpoint with the provided query." \
		"mcp_huggingface <query>" \
		"Requires a valid Hugging Face token; do not print secrets in tool calls." \
		tool_mcp_huggingface

	register_tool \
		"mcp_local_server" \
		"Connect to the bundled local MCP server over a unix socket." \
		"mcp_local_server <query>" \
		"Uses a local socket; ensure the path is trusted before writing." \
		tool_mcp_local_server
}
