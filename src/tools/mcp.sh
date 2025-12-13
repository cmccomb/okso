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
#   MCP_ENDPOINTS_JSON (string): JSON array of MCP endpoint definitions.
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

mcp_validate_unix_config() {
	local socket_path
	socket_path="$1"

	if [[ -z "${socket_path}" ]]; then
		log "ERROR" "Local MCP socket missing" ""
		return 1
	fi

	return 0
}

mcp_dispatch_endpoint() {
	# Arguments:
	#   $1 - provider label (string)
	#   $2 - transport type (string)
	#   $3 - HTTP endpoint URL (string)
	#   $4 - unix socket path (string)
	#   $5 - token environment variable name (string)
	local provider transport endpoint socket_path token_env
	provider="$1"
	transport="$2"
	endpoint="$3"
	socket_path="$4"
	token_env="$5"

	case "${transport}" in
	http)
		if ! mcp_validate_remote_config "${endpoint}" "${token_env}"; then
			return 1
		fi
		mcp_print_connection_json "${provider}" "${transport}" "${endpoint}" "" "${token_env}"
		;;
	unix)
		if ! mcp_validate_unix_config "${socket_path}"; then
			return 1
		fi
		mcp_print_connection_json "${provider}" "${transport}" "" "${socket_path}" ""
		;;
	*)
		log "ERROR" "Unsupported MCP transport" "${transport}"
		return 1
		;;
	esac
}

mcp_default_endpoints_json() {
	cat <<JSON
[
  {
    "name": "mcp_huggingface",
    "provider": "huggingface",
    "description": "Connect to the configured Hugging Face MCP endpoint with the provided query.",
    "usage": "mcp_huggingface <query>",
    "safety": "Requires a valid Hugging Face token; do not print secrets in tool calls.",
    "transport": "http",
    "endpoint": "${MCP_HUGGINGFACE_URL:-}",
    "token_env": "${MCP_HUGGINGFACE_TOKEN_ENV:-HUGGINGFACEHUB_API_TOKEN}"
  },
  {
    "name": "mcp_local_server",
    "provider": "local_demo",
    "description": "Connect to the bundled local MCP server over a unix socket.",
    "usage": "mcp_local_server <query>",
    "safety": "Uses a local socket; ensure the path is trusted before writing.",
    "transport": "unix",
    "socket": "${MCP_LOCAL_SOCKET:-${TMPDIR:-/tmp}/okso-mcp.sock}"
  }
]
JSON
}

mcp_resolved_endpoint_definitions() {
        local raw_json
        raw_json="${MCP_ENDPOINTS_JSON:-}" # string JSON array
        local allow_partial_default
        allow_partial_default=${MCP_ENDPOINTS_ALLOW_PARTIAL_DEFAULT:-false}

        if [[ -z "${raw_json// /}" ]]; then
                raw_json="$(mcp_default_endpoints_json)"
                allow_partial_default=true
	fi

	MCP_ENDPOINTS_PAYLOAD="${raw_json}" MCP_ENDPOINTS_ALLOW_PARTIAL_DEFAULT="${allow_partial_default}" python3 - <<'PY'
import json
import os
import re
import sys

raw = os.environ.get("MCP_ENDPOINTS_PAYLOAD", "").strip()
if not raw:
    sys.stderr.write("Empty MCP endpoint configuration\n")
    sys.exit(1)

try:
    definitions = json.loads(raw)
except json.JSONDecodeError as exc:  # pragma: no cover - handled in tests
    sys.stderr.write(f"Failed to parse MCP_ENDPOINTS_JSON: {exc}\n")
    sys.exit(1)

if not isinstance(definitions, list):
    sys.stderr.write("MCP endpoint configuration must be a JSON array\n")
    sys.exit(1)

name_pattern = re.compile(r"^[a-z0-9_]+$")
normalized = []
allow_partial = os.environ.get("MCP_ENDPOINTS_ALLOW_PARTIAL_DEFAULT", "").lower() == "true"

for index, entry in enumerate(definitions):
    if not isinstance(entry, dict):
        sys.stderr.write(f"Entry {index} is not an object\n")
        sys.exit(1)

    required = ["name", "provider", "description", "usage", "safety", "transport"]
    missing = [field for field in required if not entry.get(field)]
    if missing:
        sys.stderr.write(f"Entry {index} missing fields: {', '.join(missing)}\n")
        sys.exit(1)

    if not name_pattern.match(entry["name"]):
        sys.stderr.write(f"Invalid MCP tool name: {entry['name']}\n")
        sys.exit(1)

    transport = entry.get("transport")
    if transport not in {"http", "unix"}:
        sys.stderr.write(f"Unsupported transport for {entry['name']}: {transport}\n")
        sys.exit(1)

    if transport == "http":
        if not entry.get("endpoint") and not allow_partial:
            sys.stderr.write(f"HTTP endpoint missing for {entry['name']}\n")
            sys.exit(1)
        if not entry.get("token_env"):
            sys.stderr.write(f"token_env missing for {entry['name']}\n")
            sys.exit(1)
    elif transport == "unix":
        if not entry.get("socket") and not allow_partial:
            sys.stderr.write(f"socket missing for {entry['name']}\n")
            sys.exit(1)

    normalized.append(
        {
            "name": entry["name"],
            "provider": entry["provider"],
            "description": entry["description"],
            "usage": entry["usage"],
            "safety": entry["safety"],
            "transport": transport,
            "endpoint": entry.get("endpoint", ""),
            "socket": entry.get("socket", ""),
            "token_env": entry.get("token_env", ""),
        }
    )

json.dump(normalized, sys.stdout)
PY
}

mcp_register_endpoint_from_definition() {
	# Arguments:
	#   $1 - JSON for a single endpoint definition
	local definition_json name handler_name provider description usage safety transport endpoint socket_path token_env
	definition_json="$1"

	name="$(jq -r '.name' <<<"${definition_json}")"
	provider="$(jq -r '.provider' <<<"${definition_json}")"
	description="$(jq -r '.description' <<<"${definition_json}")"
	usage="$(jq -r '.usage' <<<"${definition_json}")"
	safety="$(jq -r '.safety' <<<"${definition_json}")"
	transport="$(jq -r '.transport' <<<"${definition_json}")"
	endpoint="$(jq -r '.endpoint' <<<"${definition_json}")"
	socket_path="$(jq -r '.socket' <<<"${definition_json}")"
	token_env="$(jq -r '.token_env' <<<"${definition_json}")"

	handler_name="tool_${name}"

	local handler_body
	printf -v handler_body "%s" "$(printf 'mcp_dispatch_endpoint %q %q %q %q %q' "${provider}" "${transport}" "${endpoint}" "${socket_path}" "${token_env}")"

	eval "${handler_name}() { ${handler_body}; }"

	register_tool "${name}" "${description}" "${usage}" "${safety}" "${handler_name}"
}

register_mcp_endpoints() {
	local definitions_json definitions_count
	if ! definitions_json="$(mcp_resolved_endpoint_definitions)"; then
		log "ERROR" "Failed to parse MCP endpoint definitions" ""
		return 1
	fi

	definitions_count="$(jq 'length' <<<"${definitions_json}")"

	local index
	for index in $(seq 0 $((definitions_count - 1))); do
		if ! mcp_register_endpoint_from_definition "$(jq -c --argjson i "${index}" '.[$i]' <<<"${definitions_json}")"; then
			return 1
		fi
	done
}
