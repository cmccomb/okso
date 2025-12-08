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
#   - bash 5+
#   - coreutils (ls, pwd)
#   - fd, rg (optional for search tool)
#   - logging helpers from logging.sh
#   - register_tool utilities from tools/registry.sh
#
# Exit codes:
#   Functions emit errors via log and return non-zero when misused.

TOOLS_DIR="${BASH_SOURCE[0]%/tools.sh}/tools"
# shellcheck source=./errors.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools.sh}/errors.sh"
# shellcheck source=./logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools.sh}/logging.sh"
# shellcheck source=./tools/registry.sh disable=SC1091
source "${TOOLS_DIR}/registry.sh"
# shellcheck disable=SC2034
TOOL_NAME_ALLOWLIST=(
	"terminal"
	"file_search"
	"clipboard_copy"
	"clipboard_paste"
	"notes_create"
	"notes_append"
	"notes_list"
	"notes_search"
	"notes_read"
	"reminders_create"
	"reminders_list"
	"reminders_complete"
	"calendar_create"
	"calendar_list"
	"calendar_search"
	"mail_draft"
	"mail_send"
	"mail_search"
	"mail_list_inbox"
	"mail_list_unread"
	"applescript"
	"final_answer"
)
TOOL_WRITABLE_DIRECTORY_ALLOWLIST=(
	"${HOME}/.okso"
	"${XDG_CONFIG_HOME:-${HOME}/.config}/okso"
)
# shellcheck source=./tools/terminal.sh disable=SC1091
source "${TOOLS_DIR}/terminal.sh"
# shellcheck source=./tools/file_search.sh disable=SC1091
source "${TOOLS_DIR}/file_search.sh"
# shellcheck source=./tools/clipboard.sh disable=SC1091
source "${TOOLS_DIR}/clipboard.sh"
# shellcheck source=./tools/notes/index.sh disable=SC1091
source "${TOOLS_DIR}/notes/index.sh"
# shellcheck source=./tools/reminders/index.sh disable=SC1091
source "${TOOLS_DIR}/reminders/index.sh"
# shellcheck source=./tools/calendar/index.sh disable=SC1091
source "${TOOLS_DIR}/calendar/index.sh"
# shellcheck source=./tools/mail/index.sh disable=SC1091
source "${TOOLS_DIR}/mail/index.sh"
# shellcheck source=./tools/applescript.sh disable=SC1091
source "${TOOLS_DIR}/applescript.sh"
# shellcheck source=./tools/final_answer.sh disable=SC1091
source "${TOOLS_DIR}/final_answer.sh"

tools_normalize_path() {
	# Returns a normalized absolute path for allowlist checks.
	# Arguments:
	#   $1 - path to normalize (string)
	if command -v realpath >/dev/null 2>&1; then
		realpath -m "$1"
		return
	fi

	python - "$1" <<'PY'
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
	register_file_search
	register_clipboard_copy
	register_clipboard_paste
	register_notes_suite
	register_reminders_suite
	register_calendar_suite
	register_mail_suite
	register_applescript
	register_final_answer
}
