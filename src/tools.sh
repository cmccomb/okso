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
# shellcheck source=./logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools.sh}/logging.sh"
# shellcheck source=./tools/registry.sh disable=SC1091
source "${TOOLS_DIR}/registry.sh"
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

initialize_tools() {
	register_terminal
	register_file_search
	register_clipboard_copy
	register_clipboard_paste
	register_notes_suite
	register_reminders_suite
	register_calendar_suite
	register_mail_suite
	register_applescript
}
