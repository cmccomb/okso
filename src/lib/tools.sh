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

# shellcheck source=./core/errors.sh disable=SC1091
source "${TOOLS_LIB_DIR}/core/errors.sh"
# shellcheck source=./core/logging.sh disable=SC1091
source "${TOOLS_LIB_DIR}/core/logging.sh"
# shellcheck source=./dependency_guards/dependency_guards.sh disable=SC1091
source "${TOOLS_LIB_DIR}/dependency_guards/dependency_guards.sh"
# shellcheck source=../tools/registry.sh disable=SC1091
source "${TOOLS_DIR}/registry.sh"
TOOL_WRITABLE_DIRECTORY_ALLOWLIST=(
	"${HOME}/.okso"
	"${XDG_CONFIG_HOME:-${HOME}/.config}/okso"
)
# shellcheck source=./tools/terminal/index.sh disable=SC1091
source "${TOOLS_DIR}/terminal/index.sh"
# shellcheck source=./tools/python_repl/index.sh disable=SC1091
source "${TOOLS_DIR}/python_repl/index.sh"
# shellcheck source=./tools/notes/index.sh disable=SC1091
source "${TOOLS_DIR}/notes/index.sh"
# shellcheck source=./tools/reminders/index.sh disable=SC1091
source "${TOOLS_DIR}/reminders/index.sh"
# shellcheck source=./tools/calendar/index.sh disable=SC1091
source "${TOOLS_DIR}/calendar/index.sh"
# shellcheck source=./tools/mail/index.sh disable=SC1091
source "${TOOLS_DIR}/mail/index.sh"
# shellcheck source=./tools/final_answer/index.sh disable=SC1091
source "${TOOLS_DIR}/final_answer/index.sh"
# shellcheck source=./tools/feedback/index.sh disable=SC1091
source "${TOOLS_DIR}/feedback/index.sh"
# shellcheck source=./tools/web/index.sh disable=SC1091
source "${TOOLS_DIR}/web/index.sh"

tools_normalize_path() {
	# Returns a normalized absolute path for allowlist checks.
	# Arguments:
	#   $1 - path to normalize (string)
	if command -v realpath >/dev/null 2>&1 && realpath -m / >/dev/null 2>&1; then
		realpath -m "$1"
		return
	fi

	if ! require_python3_available "path normalization fallback"; then
		return 1
	fi

	python3 - "$1" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
}

tools_writable_directory_allowed() {
	# Validates that a directory is within the writable allowlist.
	# Arguments:
	#   $1 - target directory (string)
	local candidate normalized allowed normalized_allowed
	candidate="$1"
	normalized=$(tools_normalize_path "${candidate}") || return 1

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
	local candidate
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
