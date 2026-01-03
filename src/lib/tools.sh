#!/usr/bin/env bash
# shellcheck shell=bash
#
# Tool registration aggregator for the okso assistant CLI.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools.sh}/tools.sh"
#
# Environment variables:
#   TOOL_QUERY (string): populated before handler execution.
#   IS_MACOS (bool): platform flag used by macOS-only tools.
#
# Dependencies:
#   - bash 3.2+
#   - coreutils (ls, pwd)
#   - logging helpers from logging.sh
#   - register_tool utilities from tools/registry.sh
#
# Exit codes:
#   Functions emit errors via log and return non-zero when misused.

TOOLS_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOOLS_SRC_ROOT=$(cd -- "${TOOLS_LIB_DIR}/.." && pwd)
TOOLS_DIR="${TOOLS_SRC_ROOT}/tools"

# shellcheck source=src/lib/core/errors.sh
source "${TOOLS_LIB_DIR}/core/errors.sh"
# shellcheck source=src/lib/core/logging.sh
source "${TOOLS_LIB_DIR}/core/logging.sh"
# shellcheck source=src/tools/registry.sh
source "${TOOLS_DIR}/registry.sh"
TOOL_WRITABLE_DIRECTORY_ALLOWLIST=(
	"${HOME}/.okso"
	"${XDG_CONFIG_HOME:-${HOME}/.config}/okso"
)
# shellcheck source=src/tools/terminal/index.sh
source "${TOOLS_DIR}/terminal/index.sh"
# shellcheck source=src/tools/python_repl/index.sh
source "${TOOLS_DIR}/python_repl/index.sh"
# shellcheck source=src/tools/notes/index.sh
source "${TOOLS_DIR}/notes/index.sh"
# shellcheck source=src/tools/reminders/index.sh
source "${TOOLS_DIR}/reminders/index.sh"
# shellcheck source=src/tools/calendar/index.sh
source "${TOOLS_DIR}/calendar/index.sh"
# shellcheck source=src/tools/mail/index.sh
source "${TOOLS_DIR}/mail/index.sh"
# shellcheck source=src/tools/final_answer/index.sh
source "${TOOLS_DIR}/final_answer/index.sh"
# shellcheck source=src/tools/feedback/index.sh
source "${TOOLS_DIR}/feedback/index.sh"
# shellcheck source=src/tools/web/index.sh
source "${TOOLS_DIR}/web/index.sh"

tools_normalize_path() {
	# Returns a normalized absolute path for allowlist checks.
	# Arguments:
	#   $1 - path to normalize (string)
	# Returns:
	#   normalized absolute path on stdout; non-zero on failure.

	local input_path directory basename_part normalized_parts
	input_path="$1"

	# Use realpath if available
	if command -v realpath >/dev/null 2>&1 && realpath -m / >/dev/null 2>&1; then
		realpath -m "${input_path}"
		return
	fi

	# Fallback normalization
	if [[ -e "${input_path}" || -L "${input_path}" ]]; then
		directory=$(cd -- "$(dirname -- "${input_path}")" && pwd -P) || return 1
		basename_part=$(basename -- "${input_path}")
		printf '%s\n' "${directory%/}/${basename_part}"
		return 0
	fi

	# Manual normalization for non-existent paths
	if [[ "${input_path}" != /* ]]; then
		input_path="$(pwd -P)/${input_path}"
	fi

	# Split and process path components
	IFS='/' read -r -a normalized_parts <<<"${input_path}"
	directory=()
	for part in "${normalized_parts[@]}"; do
		case "${part}" in
		"" | ".")
			continue
			;;
		"..")
			if [[ ${#directory[@]} -gt 0 ]]; then
				unset 'directory[${#directory[@]}-1]'
			fi
			;;
		*)
			directory+=("${part}")
			;;
		esac
	done

	printf '/%s\n' "$(
		IFS=/
		echo "${directory[*]}"
	)"
}

tools_writable_directory_allowed() {
	# Validates that a directory is within the writable allowlist.
	# Arguments:
	#   $1 - target directory (string)
	# Returns:
	#   None; returns non-zero if the directory is not allowed.
	local candidate normalized allowed normalized_allowed
	candidate="$1"
	normalized=$(tools_normalize_path "${candidate}") || return 1

	# Check against allowlist
	for allowed in "${TOOL_WRITABLE_DIRECTORY_ALLOWLIST[@]}"; do
		normalized_allowed=$(tools_normalize_path "${allowed}") || continue
		if [[ "${normalized}" == "${normalized_allowed}"* ]]; then
			return 0
		fi
	done

	log "ERROR" "Writable directory not allowed" "${candidate}" || true
	return 1
}

validate_writable_directories() {
	# Confirms all configured writable directories are allowlisted.
	# Returns:
	#   None; returns non-zero on failure.
	local candidate

	# Check NOTES_DIR and CONFIG_DIR
	for candidate in "${NOTES_DIR:-${HOME}/.okso}" "${CONFIG_DIR:-${XDG_CONFIG_HOME:-${HOME}/.config}/okso}"; do
		if [[ -z "${candidate}" ]]; then
			continue
		fi
		if ! tools_writable_directory_allowed "${candidate}"; then
			return 1
		fi
	done

	return 0
}

initialize_tools() {
	# Initializes and registers all available tools.
	# Returns:
	#   None; returns non-zero on failure.

	if ! validate_writable_directories; then
		return 1
	fi

	register_terminal
	register_python_repl
	register_notes_suite
	register_reminders_suite
	register_calendar_suite
	register_mail_suite
	register_final_answer
	register_feedback
	register_web_suite
}
