#!/usr/bin/env bash
# shellcheck shell=bash
#
# Markdown conversion helper for web_fetch.
#
# Usage:
#   ./markdownify.sh --path /tmp/body --content-type text/html --limit 400
#
# Environment variables: none
#
# Dependencies:
#   - bash 3.2+
#   - jq (for JSON formatting and output)
#   - xmllint (for XML pretty-printing)
#   - One of: w3m, links, lynx (for HTML to text conversion)
#
# Exit codes:
#   0 - conversion succeeded
#   1 - invalid arguments
#   2 - conversion failed

set -euo pipefail

print_usage() {
	cat <<'USAGE' >&2
Markdownify converts HTTP responses to Markdown with a preview snippet.

Required arguments:
  --path PATH           Path to the response body file
  --content-type TYPE   Content-Type header for the response
  --limit N             Preview character limit (positive integer)
USAGE
}

normalize_content_type() {
	local raw
	raw=${1:-}
	printf '%s' "${raw%%;*}" | tr '[:upper:]' '[:lower:]'
}

build_preview() {
	# Arguments:
	#   $1 - markdown text
	#   $2 - preview limit (positive integer)
	local markdown limit ellipsis truncated_len
	markdown=$1
	limit=$2
	ellipsis="…"

	if [[ -z ${limit} || ${limit} -lt 1 ]]; then
		printf '%s\n' "preview limit must be positive" >&2
		return 1
	fi

	if [[ ${#markdown} -le ${limit} ]]; then
		printf '%s' "${markdown}"
		return 0
	fi

	truncated_len=$((limit - ${#ellipsis}))
	if [[ ${truncated_len} -lt 0 ]]; then
		truncated_len=0
	fi
	printf '%s%s' "${markdown:0:${truncated_len}}" "${ellipsis}"
}

convert_html() {
	# Arguments:
	#   $1 - body path
	local body_path converter output
	body_path=$1

	for converter in w3m links lynx; do
		if command -v "${converter}" >/dev/null 2>&1; then
			break
		fi
		converter=""
	done

	if [[ -z ${converter} ]]; then
		printf '%s\n' "no HTML text-mode browser available" >&2
		return 1
	fi

	case "${converter}" in
	w3m)
		output=$(w3m -dump -T text/html "${body_path}" 2>/dev/null || w3m -dump "${body_path}" 2>/dev/null || true)
		;;
	links)
		output=$(links -dump -force-html "${body_path}" 2>/dev/null || links -dump -stdin <"${body_path}" 2>/dev/null || true)
		;;
	lynx)
		output=$(lynx -dump -stdin <"${body_path}" 2>/dev/null || lynx -dump "${body_path}" 2>/dev/null || true)
		;;
	esac

	output=$(printf '%s\n' "${output}" | sed 's/[[:space:]]\+$//' | sed '/^[[:space:]]*$/d')

	if [[ -z ${output} ]]; then
		printf '%s\n' "empty output from HTML conversion" >&2
		return 1
	fi

	printf '%s' "${output}"
}

convert_json() {
	# Arguments:
	#   $1 - body path
	local body_path formatted
	body_path=$1
	if ! formatted=$(jq --indent 2 . <"${body_path}" 2>/dev/null); then
		printf '%s\n' "invalid JSON" >&2
		return 1
	fi
	printf '%s\n%s\n%s\n' '```json' "${formatted}" '```'
}

convert_xml() {
	# Arguments:
	#   $1 - body path
	local body_path formatted
	body_path=$1
	if ! command -v xmllint >/dev/null 2>&1; then
		printf '%s\n' "xmllint not available" >&2
		return 1
	fi
	if ! formatted=$(xmllint --format "${body_path}" 2>/dev/null); then
		printf '%s\n' "invalid XML" >&2
		return 1
	fi
	printf '%s\n%s\n%s\n' '```xml' "${formatted}" '```'
}

convert_plain() {
	# Arguments:
	#   $1 - body path
	local body_path
	body_path=$1
	sed 's/[[:space:]]\+$//' <"${body_path}" | sed '/^[[:space:]]*$/d'
}

convert_body() {
	# Arguments:
	#   $1 - body path
	#   $2 - content type
	local body_path content_type normalized markdown
	body_path=$1
	content_type=$2

	normalized=$(normalize_content_type "${content_type}")

	if [[ ${normalized} == *html* ]]; then
		markdown=$(convert_html "${body_path}") || return 2
	elif [[ ${normalized} == *json* ]]; then
		markdown=$(convert_json "${body_path}") || return 2
	elif [[ ${normalized} == *xml* ]]; then
		markdown=$(convert_xml "${body_path}") || return 2
	elif [[ ${normalized} == text/* ]]; then
		markdown=$(convert_plain "${body_path}") || return 2
	else
		printf '%s\n' "unsupported content type: ${content_type}" >&2
		return 2
	fi

	if [[ -z ${markdown} ]]; then
		printf '%s\n' "empty markdown output" >&2
		return 2
	fi

	printf '%s' "${markdown}"
}

parse_args() {
	local path content_type limit
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--path)
			path=${2:-}
			shift 2
			;;
		--content-type)
			content_type=${2:-}
			shift 2
			;;
		--limit)
			limit=${2:-}
			shift 2
			;;
		-h | --help)
			print_usage
			exit 1
			;;
		*)
			printf '%s\n' "unknown argument: $1" >&2
			return 1
			;;
		esac
	done

	if [[ -z ${path:-} || -z ${content_type:-} || -z ${limit:-} ]]; then
		print_usage
		return 1
	fi

	if [[ ! -f ${path} ]]; then
		printf '%s\n' "body path does not exist: ${path}" >&2
		return 1
	fi

	if ! [[ ${limit} =~ ^[0-9]+$ ]] || [[ ${limit} -lt 1 ]]; then
		printf '%s\n' "limit must be a positive integer" >&2
		return 1
	fi

	printf '%s\n' "${path}|${content_type}|${limit}"
}

main() {
	local parsed path content_type limit markdown preview

	if ! parsed=$(parse_args "$@"); then
		return 1
	fi

	path=${parsed%%|*}
	content_type=${parsed#*|}
	content_type=${content_type%%|*}
	limit=${parsed##*|}

	if ! markdown=$(convert_body "${path}" "${content_type}"); then
		return 2
	fi

	if ! preview=$(build_preview "${markdown}" "${limit}"); then
		return 2
	fi

	jq -nc --arg markdown "${markdown}" --arg preview "${preview}" '{markdown:$markdown, preview:$preview}'
}

main "$@"
