#!/usr/bin/env bash
# shellcheck shell=bash
#
# File and content search tool using macOS Spotlight or fd/rg fallbacks.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/file_search.sh}/tools/file_search.sh"
#
# Environment variables:
#   TOOL_QUERY (string): query passed by the planner before handler execution.
#
# Dependencies:
#   - bash 5+
#   - mdfind (macOS, preferred when available)
#   - fd (optional)
#   - ripgrep (optional)
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero only when registration is misused.

# shellcheck source=../lib/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/file_search.sh}/lib/logging.sh"
# shellcheck source=./registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/file_search.sh}/registry.sh"

tool_file_search() {
	local query
	query=${TOOL_QUERY:-""}
	log "INFO" "Searching files" "${query}"

        if [[ "${IS_MACOS:-false}" == true ]] && command -v mdfind >/dev/null 2>&1; then
                if [[ -n "${query}" ]]; then
                        mdfind -onlyin "${PWD}" "${query}" || true
                else
                        mdfind -onlyin "${PWD}" "*" || true
                fi
        elif command -v fd >/dev/null 2>&1; then
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
		"file_search <terms_to_be_searched>" \
		"May read many files; avoid leaking secrets." \
		tool_file_search
}
