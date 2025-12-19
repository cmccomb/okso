#!/usr/bin/env bash
# shellcheck shell=bash
#
# Web fetch tool that retrieves HTTP response bodies with size safeguards.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/web/web_fetch.sh}/tools/web/web_fetch.sh"
#
# Environment variables:
#   TOOL_ARGS (JSON object): structured args with required `url` and optional `max_bytes`.
#
# Dependencies:
#   - bash 5+
#   - curl
#   - jq
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Non-zero on validation errors, network failures, or oversized payload handling.

WEB_TOOLS_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC_ROOT=$(cd -- "${WEB_TOOLS_DIR}/../.." && pwd)

# shellcheck source=../../lib/logging.sh disable=SC1091
source "${SRC_ROOT}/lib/logging.sh"
# shellcheck source=./http.sh disable=SC1091
source "${WEB_TOOLS_DIR}/http.sh"
# shellcheck source=../registry.sh disable=SC1091
source "${SRC_ROOT}/tools/registry.sh"

web_fetch_parse_args() {
	# Parses TOOL_ARGS JSON for the web_fetch tool.
	# Returns a JSON object with `url` and `max_bytes`.
	local args_json
	args_json="${TOOL_ARGS:-}" || true

	jq -cer '
                if (type != "object") then error("args must be object") end
                | if (.url? == null) then error("missing url") end
                | if (.url | type) != "string" or (.url | length) == 0 then error("url must be non-empty string") end
                | if (.max_bytes? != null) then
                        if (.max_bytes | type) != "number" or (.max_bytes | floor) != .max_bytes then error("max_bytes must be integer") end
                        | if (.max_bytes < 1 or .max_bytes > 5242880) then error("max_bytes must be between 1 and 5242880") end
                else
                        .max_bytes = 1048576
                end
                | if ((del(.url, .max_bytes) | length) != 0) then error("unexpected properties") end
                | {url: .url, max_bytes: (.max_bytes // 1)}
        ' <<<"${args_json}" 2>/dev/null
}

tool_web_fetch() {
	# Downloads the response body for a URL, enforcing size limits and returning JSON metadata.
	local parsed_args url max_bytes response payload body_path content_type truncated body_size headers final_url body_encoding body_snippet snippet_limit

	parsed_args=$(web_fetch_parse_args)
	if [[ -z "${parsed_args}" ]]; then
		log "ERROR" "Invalid TOOL_ARGS for web_fetch" "${TOOL_ARGS:-}" >&2
		return 1
	fi

	url=$(jq -r '.url' <<<"${parsed_args}")
	max_bytes=$(jq -r '.max_bytes' <<<"${parsed_args}")

	log "INFO" "Fetching URL" "${url}" >&2

	response=$(web_http_request "${url}" "${max_bytes}" --header 'Accept: */*')
	if [[ -z "${response}" ]]; then
		log "ERROR" "Failed to fetch URL" "${url}" >&2
		return 1
	fi

	payload=$(jq -er '.' <<<"${response}" 2>/dev/null) || {
		log "ERROR" "Invalid HTTP helper payload" "${response}" >&2
		return 1
	}

	body_path=$(jq -r '.body_path' <<<"${payload}")
	content_type=$(jq -r '.content_type // "application/octet-stream"' <<<"${payload}")
	truncated=$(jq -r '.truncated' <<<"${payload}")
	body_size=$(jq -r '.bytes // 0' <<<"${payload}")
	headers=$(jq -r '.headers // ""' <<<"${payload}")
	final_url=$(jq -r '.final_url // ""' <<<"${payload}")

	snippet_limit=4096
	body_encoding="text"
	if [[ -n "${content_type}" ]]; then
		case "${content_type,,}" in
		text/* | *json* | *xml* | *+json) ;;
		*)
			body_encoding="base64"
			;;
		esac
	fi

	if [[ "${body_encoding}" == "base64" ]]; then
		body_snippet=$(head -c "${snippet_limit}" "${body_path}" | base64 | tr -d '\n')
	else
		body_snippet=$(head -c "${snippet_limit}" "${body_path}")
	fi

	rm -f "${body_path}"

	jq -nc \
		--arg url "${url}" \
		--arg final_url "${final_url:-${url}}" \
		--arg content_type "${content_type}" \
		--arg headers "${headers}" \
		--arg body_snippet "${body_snippet}" \
		--arg body_encoding "${body_encoding}" \
		--argjson status "$(jq -r '.status' <<<"${payload}")" \
		--argjson bytes "${body_size}" \
		--argjson truncated "${truncated}" \
		'{url: $url, final_url: $final_url, status: $status, content_type: $content_type, headers: $headers, bytes: $bytes, truncated: $truncated, body_encoding: $body_encoding, body_snippet: $body_snippet}'
}

register_web_fetch() {
	local args_schema

	args_schema=$(jq -nc '{
                type: "object",
                required: ["url"],
                additionalProperties: false,
                properties: {
                        url: {type: "string", format: "uri", minLength: 1},
                        max_bytes: {type: "integer", minimum: 1, maximum: 5242880}
                }
        }')

	register_tool \
		"web_fetch" \
		"Retrieve the raw HTTP response body for a URL." \
		"web_fetch <url>" \
		"Performs external HTTP requests; avoid sharing sensitive data." \
		tool_web_fetch \
		"${args_schema}"
}
