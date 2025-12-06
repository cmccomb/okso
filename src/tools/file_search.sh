#!/usr/bin/env bash
# shellcheck shell=bash
#
# File and content search tool using fd/rg fallbacks.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/file_search.sh}/tools/file_search.sh"
#
# Environment variables:
#   TOOL_QUERY (string): query passed by the planner before handler execution.
#
# Dependencies:
#   - bash 5+
#   - fd (optional)
#   - ripgrep (optional)
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero only when registration is misused.

# shellcheck source=../logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/file_search.sh}/logging.sh"
# shellcheck source=./registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/file_search.sh}/registry.sh"

tool_file_search() {
	local query
	query=${TOOL_QUERY:-""}
	log "INFO" "Searching files" "${query}"

	if command -v fd >/dev/null 2>&1; then
		fd --hidden --color=never --max-depth 5 "${query:-.}" . || true
	else
		find . -maxdepth 5 -iname "*${query}*" || true
	fi

	if command -v rg >/dev/null 2>&1 && [[ -n "${query}" ]]; then
		rg --line-number --hidden --color=never "${query}" || true
	fi
}

register_file_search() {
	register_tool \
		"file_search" \
		"Search project files by name and content using fd/rg." \
		"fd or find combined with ripgrep." \
		"May read many files; avoid leaking secrets." \
		tool_file_search
}
