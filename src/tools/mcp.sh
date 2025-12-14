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
#   MCP_LOCAL_SOCKET (string): unix socket or filesystem path for a local MCP server.
#   MCP_ENDPOINTS_JSON (string): JSON array of MCP endpoint definitions.
#   MCP_SKIP_USAGE_DISCOVERY (bool): skip HTTP usage discovery when true.
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
		log "ERROR" "MCP remote endpoint not configured" "$1"
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

mcp_render_usage_from_tool_listing() {
        # Generate a concise usage string from a remote MCP tool listing.
        # Arguments:
        #   $1 - JSON payload returned by a tools endpoint (string)
        local tools_json
        tools_json="$1"

        MCP_TOOLS_PAYLOAD="${tools_json}" python3 - <<'PY'
"""Summarize a tools listing into a human-readable usage string."""

import json
import os
import sys
from typing import Iterable, Tuple


def extract_tools(payload: dict) -> Iterable[Tuple[str, str]]:
    tools = payload.get("tools")
    if isinstance(tools, list):
        for entry in tools:
            name = entry.get("name") if isinstance(entry, dict) else None
            description = entry.get("description", "") if isinstance(entry, dict) else ""
            if name:
                yield name, description
        return

    # fall back to direct list
    if isinstance(payload, list):
        for entry in payload:
            name = entry.get("name") if isinstance(entry, dict) else None
            description = entry.get("description", "") if isinstance(entry, dict) else ""
            if name:
                yield name, description


def main() -> None:
    raw = os.environ.get("MCP_TOOLS_PAYLOAD", "").strip()
    if not raw:
        return

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return

    entries = list(extract_tools(payload))
    if not entries:
        return

    formatted = "; ".join(
        f"{name}: {description}" if description else name for name, description in entries
    )
    sys.stdout.write(f"Available tools -> {formatted}")


if __name__ == "__main__":
    main()
PY
}

mcp_infer_usage_from_http() {
        # Attempt to derive a usage string from a remote MCP HTTP endpoint.
        # Arguments:
        #   $1 - base HTTP endpoint URL (string)
        #   $2 - token environment variable name (string)
        local endpoint token_env url auth_header
        endpoint="$1"
        token_env="$2"

        if [[ -z "${endpoint}" ]]; then
                return 1
        fi

        url="${endpoint%/}/tools"
        auth_header=()

        if [[ -n "${token_env}" && -n "${!token_env:-}" ]]; then
                auth_header=(-H "Authorization: Bearer ${!token_env}")
        fi

        local listing
        if ! listing=$(curl -sfSL --connect-timeout 2 --max-time 5 "${auth_header[@]}" "${url}"); then
                return 1
        fi

        mcp_render_usage_from_tool_listing "${listing}"
}

mcp_resolved_endpoint_definitions() {
        local raw_json
        raw_json="${MCP_ENDPOINTS_JSON:-}" # string JSON array

        if [[ -z "${raw_json// /}" ]]; then
                raw_json="[]"
        fi

        MCP_ENDPOINTS_PAYLOAD="${raw_json}" python3 - <<'PY'
import json
import os
import re
import sys

raw = os.environ.get("MCP_ENDPOINTS_PAYLOAD", "").strip()
if not raw:
    json.dump([], sys.stdout)
    sys.exit(0)

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

for index, entry in enumerate(definitions):
    if not isinstance(entry, dict):
        sys.stderr.write(f"Entry {index} is not an object\n")
        sys.exit(1)

    required = ["name", "provider", "description", "safety", "transport"]
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
        if not entry.get("endpoint"):
            sys.stderr.write(f"HTTP endpoint missing for {entry['name']}\n")
            sys.exit(1)
        if not entry.get("token_env"):
            sys.stderr.write(f"token_env missing for {entry['name']}\n")
            sys.exit(1)
    elif transport == "unix":
        if not entry.get("socket"):
            sys.stderr.write(f"socket missing for {entry['name']}\n")
            sys.exit(1)

    normalized.append(
        {
            "name": entry["name"],
            "provider": entry["provider"],
            "description": entry["description"],
            "usage": entry.get("usage", ""),
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

        local skip_usage_discovery
        skip_usage_discovery=${MCP_SKIP_USAGE_DISCOVERY:-false}

        if [[ -z "${usage}" && "${skip_usage_discovery}" != true && "${skip_usage_discovery}" != 1 ]]; then
                if [[ "${transport}" == "http" ]]; then
                        usage="$(mcp_infer_usage_from_http "${endpoint}" "${token_env}" 2>/dev/null)" || usage=""
                fi
        fi

        if [[ -z "${usage}" ]]; then
                usage="${name} <query>"
        fi

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
