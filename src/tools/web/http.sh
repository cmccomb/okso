#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared HTTP helper for web tools, wrapping curl with validation,
# retries, timeout defaults, header capture, and truncation safeguards.
#
# Usage:
#   source "${BASH_SOURCE[0]%/web/http.sh}/web/http.sh"
#   response_json=$(web_http_request "https://example.com" 1048576 --header 'Accept: */*')
#
# Environment variables:
#   WEB_HTTP_TIMEOUT (integer): overall timeout in seconds (default: 20).
#   WEB_HTTP_CONNECT_TIMEOUT (integer): connect timeout in seconds (default: 5).
#   WEB_HTTP_RETRIES (integer): retry attempts for transient failures (default: 1).
#   WEB_HTTP_RETRY_DELAY (integer): delay between retries in seconds (default: 1).
#
# Dependencies:
#   - bash 3.2+
#   - curl
#   - jq
#   - logging helpers from logging.sh
#
# Exit codes:
#   Non-zero on validation errors or curl failures.

WEB_HTTP_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC_ROOT=$(cd -- "${WEB_HTTP_DIR}/../.." && pwd)

# shellcheck source=../../lib/core/logging.sh disable=SC1091
source "${SRC_ROOT}/lib/core/logging.sh"

# web_http_validate_request ensures URL and byte limits are well-formed.
# Arguments:
#   $1 (string): URL to fetch.
#   $2 (integer): Maximum allowed bytes for the response body.
web_http_validate_request() {
	local url max_bytes
	url="$1"
	max_bytes="$2"

	if [[ -z "${url}" ]]; then
		log "ERROR" "missing url" "" >&2
		return 1
	fi

	if [[ -z "${max_bytes}" || ! "${max_bytes}" =~ ^[0-9]+$ ]]; then
		log "ERROR" "max_bytes must be integer" "${max_bytes}" >&2
		return 1
	fi

	if ((max_bytes < 1 || max_bytes > 5242880)); then
		log "ERROR" "max_bytes out of bounds" "${max_bytes}" >&2
		return 1
	fi

	return 0
}

# web_http_final_headers extracts the last response header block from curl output.
# Arguments:
#   $1 (string): path to the header capture file written by curl.
web_http_final_headers() {
	local header_file
	header_file="$1"
	awk 'BEGIN{block=0} /^HTTP/{block++} {blocks[block]=blocks[block] $0 "\n"} END{if (block>0) {printf "%s", blocks[block]}}' "${header_file}" |
		sed '/^$/d' |
		tr -d '\r'
}

# web_http_request executes an HTTP request with shared defaults and returns JSON metadata.
# Arguments:
#   $1 (string): URL to fetch.
#   $2 (integer): Maximum allowed bytes for the response body.
#   $3+ (string): Additional curl arguments (headers, query params, etc.).
#
# Output (JSON):
#   {
#     "status": <http status code>,
#     "final_url": "<effective url>",
#     "content_type": "<content type>",
#     "headers": "<final response headers>",
#     "bytes": <downloaded byte length>,
#     "truncated": <bool>,
#     "body_path": "<path to truncated body file>"
#   }
web_http_request() {
	local url max_bytes
	url="$1"
	max_bytes="$2"
	shift 2 || true
	local -a curl_args
	curl_args=("$@")

	if ! web_http_validate_request "${url}" "${max_bytes}"; then
		return 1
	fi

	local body_file header_file stderr_file
	body_file="$(mktemp)"
	header_file="$(mktemp)"
	stderr_file="$(mktemp)"

	local curl_output status
	curl_output=$(curl \
		--silent \
		--show-error \
		--location \
		--max-time "${WEB_HTTP_TIMEOUT:-20}" \
		--connect-timeout "${WEB_HTTP_CONNECT_TIMEOUT:-5}" \
		--retry "${WEB_HTTP_RETRIES:-1}" \
		--retry-delay "${WEB_HTTP_RETRY_DELAY:-1}" \
		--dump-header "${header_file}" \
		--output "${body_file}" \
		--write-out '%{http_code}\n%{url_effective}\n%{content_type}\n%{size_download}' \
		"${curl_args[@]+"${curl_args[@]}"}" \
		"${url}" \
		2>"${stderr_file}")
	status=$?

	if ((status != 0)); then
		log "ERROR" "curl request failed" "$(cat "${stderr_file}")" >&2
		rm -f "${body_file}" "${header_file}" "${stderr_file}"
		return 1
	fi

	local -a meta
	while IFS= read -r line; do
		meta+=("$line")
	done <<<"${curl_output}"
	local http_code final_url content_type downloaded_bytes
	http_code="${meta[0]:-0}"
	final_url="${meta[1]:-${url}}"
	content_type="${meta[2]:-application/octet-stream}"
	downloaded_bytes="${meta[3]:-0}"

	if [[ -z "${http_code}" || ! "${http_code}" =~ ^[0-9]{3}$ ]]; then
		log "ERROR" "invalid http status" "${http_code}" >&2
		rm -f "${body_file}" "${header_file}" "${stderr_file}"
		return 1
	fi

	local body_size truncated truncated_bool
	body_size=$(wc -c <"${body_file}")
	truncated=false
	if ((body_size > max_bytes)); then
		head -c "${max_bytes}" "${body_file}" >"${body_file}.trimmed"
		mv "${body_file}.trimmed" "${body_file}"
		truncated=true
	fi
	body_size=$(wc -c <"${body_file}")

	truncated_bool=false
	if [[ "${truncated}" == "true" ]]; then
		truncated_bool=true
	fi

	local final_headers
	final_headers=$(web_http_final_headers "${header_file}")
	rm -f "${header_file}" "${stderr_file}"

	jq -nc \
		--arg body_path "${body_file}" \
		--arg final_url "${final_url}" \
		--arg content_type "${content_type}" \
		--arg headers "${final_headers}" \
		--argjson status "${http_code}" \
		--argjson bytes "${body_size:-${downloaded_bytes}}" \
		--argjson truncated "${truncated_bool}" \
		'{status: $status, final_url: $final_url, content_type: $content_type, headers: $headers, bytes: $bytes, truncated: $truncated, body_path: $body_path}'
}
