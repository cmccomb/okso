#!/usr/bin/env bash
# shellcheck shell=bash
#
# Read local files and emit markdown-friendly pages.
#
# Usage:
#   source "${BASH_SOURCE[0]%/file_read/index.sh}/file_read/index.sh"
#
# Environment variables:
#   FILE_READ_PAGE_SIZE (int): max characters per page (default: 4000).
#
# Dependencies:
#   - bash 3.2+
#   - jq
#   - logging helpers from logging.sh
#   - register_tool utilities from tools/registry.sh
#
# Exit codes:
#   Returns non-zero when arguments are invalid or file access fails.

# shellcheck source=src/tools/registry.sh
source "${BASH_SOURCE[0]%/file_read/index.sh}/registry.sh"
# shellcheck source=src/lib/core/logging.sh
source "${BASH_SOURCE[0]%/tools/file_read/index.sh}/lib/core/logging.sh"

file_read_page_size() {
	printf '%s' "${FILE_READ_PAGE_SIZE:-4000}"
}

file_read_extract_path() {
	jq -r '.path // empty' <<<"${TOOL_ARGS:-}"
}

file_read_split_pages() {
	# Arguments:
	#   $1 - content
	#   $2 - page size
	local content page_size offset chunk
	content=$1
	page_size=$2
	offset=0

	if [[ -z ${page_size} || ${page_size} -lt 1 ]]; then
		printf '%s\n' "invalid page size" >&2
		return 1
	fi

	if [[ -z ${content} ]]; then
		printf '%s\n' "" && return 0
	fi

	while [[ ${offset} -lt ${#content} ]]; do
		chunk=${content:${offset}:${page_size}}
		printf '%s\n' "${chunk}"
		offset=$((offset + page_size))
	done
}

tool_file_read() {
	local path page_size content pages_json page
	path=$(file_read_extract_path)

	if [[ -z ${path} ]]; then
		log "ERROR" "file_read requires a path" || true
		return 1
	fi

	if [[ ! -f ${path} ]]; then
		log "ERROR" "file_read path does not exist" "${path}" || true
		return 1
	fi

	page_size=$(file_read_page_size)
	content=$(cat "${path}")

	pages_json='[]'
	while IFS= read -r page; do
		formatted_page=$'```text\n'"${page}"$'\n```'
		pages_json=$(jq -c --arg page "${formatted_page}" '. + [$page]' <<<"${pages_json}")
	done < <(file_read_split_pages "${content}" "${page_size}")

	if [[ ${pages_json} == '[]' ]]; then
		pages_json=$(jq -c --arg page $'```text\n\n```' '. + [$page]' <<<"${pages_json}")
	fi

	jq -nc --argjson pages "${pages_json}" '{pages:$pages}'
}

register_file_read() {
	local args_schema

	args_schema=$(
		cat <<'JSON'
{"type":"object","properties":{"path":{"type":"string"}},"required":["path"],"additionalProperties":false}
JSON
	)

	register_tool \
		"file_read" \
		"Read a local file and return paginated markdown text." \
		"Only reads local files provided by the user." \
		tool_file_read \
		"${args_schema}"
}
