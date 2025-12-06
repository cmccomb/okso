#!/usr/bin/env bash
# shellcheck shell=bash
#
# Tool registration aggregator for the do assistant CLI.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools.sh}/tools.sh"
#
# Environment variables:
#   NOTES_DIR (string): location to store notes; defaults set by caller.
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
# shellcheck source=./tools/os_nav.sh disable=SC1091
source "${TOOLS_DIR}/os_nav.sh"
# shellcheck source=./tools/file_search.sh disable=SC1091
source "${TOOLS_DIR}/file_search.sh"
# shellcheck source=./tools/notes.sh disable=SC1091
source "${TOOLS_DIR}/notes.sh"
# shellcheck source=./tools/mail_stub.sh disable=SC1091
source "${TOOLS_DIR}/mail_stub.sh"
# shellcheck source=./tools/applescript.sh disable=SC1091
source "${TOOLS_DIR}/applescript.sh"

initialize_tools() {
	register_os_nav
	register_file_search
	register_notes
	register_mail_stub
	register_applescript
}
