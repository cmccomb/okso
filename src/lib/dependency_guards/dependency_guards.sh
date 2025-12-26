#!/usr/bin/env bash
# shellcheck shell=bash
#
# Guard helpers for common platform and dependency requirements.
#
# Usage:
#   source "${BASH_SOURCE[0]%/dependency_guards.sh}/dependency_guards.sh"
#
# Environment variables:
#   LLAMA_AVAILABLE (bool): indicates whether llama.cpp is available for inference.
#   IS_MACOS (bool): signals whether the host is macOS.
#
# Dependencies:
#   - bash 3.2+
#   - logging helpers from logging.sh
#
# Exit codes:
#   Functions return non-zero when requirements are unmet.

DEPENDENCY_GUARDS_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=../core/logging.sh disable=SC1091
source "${DEPENDENCY_GUARDS_LIB_DIR}/../core/logging.sh"

require_llama_available() {
	# Ensures llama-backed features only run when llama.cpp is available.
	# Arguments:
	#   $1 - feature name for logging context (string; optional)
	local feature
	feature=${1:-"llama-backed functionality"}

	if [[ "${LLAMA_AVAILABLE:-}" == true ]]; then
		return 0
	fi

	log "ERROR" "llama.cpp is required for ${feature}" "LLAMA_AVAILABLE=${LLAMA_AVAILABLE:-}" || true
	return 1
}

require_macos_capable_terminal() {
	# Enforces macOS availability for macOS-specific terminal or automation tools.
	# Arguments:
	#   $1 - warning message when unsupported (string; optional)
	#   $2 - log severity when unsupported (string; optional; default WARN)
	local warning severity
	warning=${1:-"macOS-only functionality is unavailable on this platform"}
	severity=${2:-"WARN"}

	if [[ "${IS_MACOS:-}" == true ]]; then
		return 0
	fi

	log "${severity}" "${warning}" "IS_MACOS=${IS_MACOS:-}" || true
	return 1
}

require_python3_available() {
	# Ensures python3 is available before invoking Python-dependent helpers.
	# Arguments:
	#   $1 - feature name for logging context (string; optional)
	local feature python_status
	feature=${1:-"python3-dependent functionality"}
	python_status=127

	hash -r 2>/dev/null || true

	if command -v python3 >/dev/null 2>&1; then
		python3 --version >/dev/null 2>&1
		python_status=$?
		if [[ ${python_status} -eq 0 ]]; then
			return 0
		fi
	fi

	log "ERROR" "python3 is required for ${feature}" "python3 unavailable or failed (exit_status=${python_status})" || true
	return 1
}

jsonschema_cli() {
	# Executes the JSON Schema CLI using Homebrew (preferred) or npx as a fallback.
	# Arguments:
	#   Remaining arguments - forwarded to the jsonschema CLI.
	local -a cli_cmd=()

	if command -v jsonschema >/dev/null 2>&1; then
		cli_cmd=(jsonschema)
	elif command -v npx >/dev/null 2>&1; then
		cli_cmd=(npx --yes @sourcemeta/jsonschema)
	else
		return 127
	fi

	"${cli_cmd[@]}" "$@"
}

require_jsonschema_cli_available() {
	# Ensures the sourcemeta JSON Schema CLI is available.
	# Arguments:
	#   $1 - feature name for logging context (string; optional)
	local feature cli_status
	feature=${1:-"JSON Schema validation"}
	cli_status=127

	hash -r 2>/dev/null || true

	if jsonschema_cli version >/dev/null 2>&1; then
		return 0
	fi

	log "ERROR" "jsonschema CLI is required for ${feature}" "jsonschema CLI unavailable; install with brew install sourcemeta/apps/jsonschema" || true
	return 1
}

export -f require_llama_available
export -f require_macos_capable_terminal
export -f require_python3_available
export -f jsonschema_cli
export -f require_jsonschema_cli_available
