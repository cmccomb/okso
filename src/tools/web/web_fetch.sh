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
        local parsed_args url max_bytes body_file stderr_file http_code status body_size truncated response_body truncated_json
        body_file="$(mktemp)"
        stderr_file="$(mktemp)"

        parsed_args=$(web_fetch_parse_args)
        if [[ -z "${parsed_args}" ]]; then
                log "ERROR" "Invalid TOOL_ARGS for web_fetch" "${TOOL_ARGS:-}" >&2
                rm -f "${body_file}" "${stderr_file}"
                return 1
        fi

        url=$(jq -r '.url' <<<"${parsed_args}")
        max_bytes=$(jq -r '.max_bytes' <<<"${parsed_args}")

        log "INFO" "Fetching URL" "${url}" >&2

        http_code=$(curl \
                --silent \
                --show-error \
                --fail \
                --location \
                --max-time 20 \
                --connect-timeout 5 \
                --retry 1 \
                --retry-delay 1 \
                --output "${body_file}" \
                --write-out '%{http_code}' \
                --header 'Accept: */*' \
                "${url}" \
                2>"${stderr_file}")
        status=$?

        if ((status != 0)); then
                log "ERROR" "curl request failed" "$(cat "${stderr_file}")" >&2
                rm -f "${body_file}" "${stderr_file}"
                return 1
        fi

        body_size=$(wc -c <"${body_file}")
        truncated=false
        if ((body_size > max_bytes)); then
                head -c "${max_bytes}" "${body_file}" >"${body_file}.trimmed"
                mv "${body_file}.trimmed" "${body_file}"
                truncated=true
        fi

        response_body="$(cat "${body_file}")"
        rm -f "${body_file}" "${stderr_file}"

        if [[ "${truncated}" == "true" ]]; then
                truncated_json=true
        else
                truncated_json=false
        fi

        jq -nc --arg url "${url}" --arg body "${response_body}" --argjson status "${http_code:-0}" --argjson truncated "${truncated_json}" '{url: $url, status: $status, body: $body, truncated: $truncated}'
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
