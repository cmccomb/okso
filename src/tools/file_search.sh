#!/usr/bin/env bash
# shellcheck shell=bash
#
# File and content search tool using macOS Spotlight or fd/rg fallbacks.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/file_search.sh}/tools/file_search.sh"
#
# Environment variables:
#   TOOL_ARGS (JSON object): structured args including `query`.
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
	local query args_json
	args_json="${TOOL_ARGS:-}" || true
	query=""

	if [[ -n "${args_json}" ]]; then
		query=$(jq -er '
if type != "object" then error("args must be object") end
| if .query? == null then error("missing query") end
| if (.query | type) != "string" then error("query must be string") end
| if (.query | length) == 0 then error("query cannot be empty") end
| if ((del(.query) | length) != 0) then error("unexpected properties") end
| .query
' <<<"${args_json}" 2>/dev/null || true)
	fi

	if [[ -z "${query:-}" ]]; then
		log "ERROR" "Missing TOOL_ARGS.query" "${args_json}" >&2
		return 1
	fi

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
	local args_schema

	args_schema=$(
		cat <<'JSON'
{"type":"object","required":["query"],"properties":{"query":{"type":"string","minLength":1}},"additionalProperties":false}
JSON
	)
	register_tool \
		"file_search" \
		"Search project files by name and content using fd/rg." \
		"file_search <terms_to_be_searched>" \
		"May read many files; avoid leaking secrets." \
		tool_file_search \
		"${args_schema}"
}
