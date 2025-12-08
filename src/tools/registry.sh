#!/usr/bin/env bash
# shellcheck shell=bash
#
# Tool registry utilities shared across individual tool modules.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/registry.sh}/tools/registry.sh"
#
# Environment variables:
#   None
#
# Dependencies:
#   - bash 5+
#   - logging helpers from logging.sh
#
# Exit codes:
#   Functions emit errors via log and return non-zero when misused.

# shellcheck source=../logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/registry.sh}/logging.sh"

# shellcheck disable=SC2034
declare -A TOOL_DESCRIPTION=()
# shellcheck disable=SC2034
declare -A TOOL_COMMAND=()
# shellcheck disable=SC2034
declare -A TOOL_SAFETY=()
# shellcheck disable=SC2034
declare -A TOOL_HANDLER=()
# shellcheck disable=SC2034
TOOLS=()

init_tool_registry() {
	TOOL_DESCRIPTION=()
	TOOL_COMMAND=()
	TOOL_SAFETY=()
	TOOL_HANDLER=()
	TOOLS=()
}

register_tool() {
	# Arguments:
	#   $1 - name
	#   $2 - description
	#   $3 - invocation command (string)
	#   $4 - safety notes
	#   $5 - handler function name
	if [[ $# -lt 5 ]]; then
		log "ERROR" "register_tool requires five arguments" "$*"
		return 1
	fi

	local name
	name="$1"

	if [[ ! "${name}" =~ ^[a-z0-9_]+$ ]]; then
		log "ERROR" "tool names must be alphanumeric with underscores" "${name}" || true
		return 1
	fi

	if [[ -n "${TOOL_NAME_ALLOWLIST[*]:-}" ]]; then
		local allowed
		allowed=false
		for allowed in "${TOOL_NAME_ALLOWLIST[@]}"; do
			if [[ "${name}" == "${allowed}" ]]; then
				allowed=true
				break
			fi
		done

		if [[ "${allowed}" != true ]]; then
			log "ERROR" "tool name not in allowlist" "${name}" || true
			return 1
		fi
	fi
	# shellcheck disable=SC2034
	TOOLS+=("${name}")
	# shellcheck disable=SC2034
	TOOL_DESCRIPTION["${name}"]="$2"
	# shellcheck disable=SC2034
	TOOL_COMMAND["${name}"]="$3"
	# shellcheck disable=SC2034
	TOOL_SAFETY["${name}"]="$4"
	# shellcheck disable=SC2034
	TOOL_HANDLER["${name}"]="${5:-}"
}
