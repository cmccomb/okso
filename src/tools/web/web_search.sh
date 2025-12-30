#!/usr/bin/env bash
# shellcheck shell=bash
#
# Web search tool backed by Google Custom Search API.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/web/web_search.sh}/tools/web/web_search.sh"
#
# Environment variables:
#   TOOL_ARGS (JSON object): structured args with required `query` (or `input` alias) and optional `num`.
#   GOOGLE_SEARCH_API_KEY (string): API key for Google Custom Search.
#   GOOGLE_SEARCH_CX (string): Custom search engine identifier.
#
# Dependencies:
#   - bash 3.2+
#   - curl
#   - jq
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Non-zero on validation errors, missing configuration, or API failures.

WEB_TOOLS_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC_ROOT=$(cd -- "${WEB_TOOLS_DIR}/../.." && pwd)

# shellcheck source=../../lib/core/logging.sh disable=SC1091
source "${SRC_ROOT}/lib/core/logging.sh"
# shellcheck source=./http.sh disable=SC1091
source "${WEB_TOOLS_DIR}/http.sh"
# shellcheck source=../registry.sh disable=SC1091
source "${SRC_ROOT}/tools/registry.sh"

web_search_parse_args() {
	# Parses TOOL_ARGS JSON for the web_search tool.
	# Returns a JSON object with `query` and `num`.
	local args_json err
	args_json="${TOOL_ARGS:-}" || true

	if ! err=$(jq -cer '
                if (type != "object") then error("args must be object") end
                | .query = (.query // .input)
                | if (.query? == null) then error("missing query") end
                | if (.query | type) != "string" or (.query | length) == 0 then error("query must be non-empty string") end
                | if (.num? != null) then
                        if (.num | type) != "number" or (.num | floor) != .num then error("num must be integer") end
                        | if (.num < 1 or .num > 10) then error("num must be between 1 and 10") end
                else
                        .num = 5
                end
                | if ((del(.query, .input, .num) | length) != 0) then error("unexpected properties") end
                | {query: .query, num: (.num // 1)}
        ' <<<"${args_json}" 2>&1); then
		log "ERROR" "Invalid web_search arguments" "${err}" >&2
		return 1
	fi
	printf '%s' "${err}"
}

tool_web_search() {
	# Executes a Google Custom Search request and emits structured JSON results.
	local parsed_args query num api_key cx helper_payload body_path response

	if ! parsed_args=$(web_search_parse_args); then
		return 1
	fi

	query=$(jq -r '.query' <<<"${parsed_args}")
	num=$(jq -r '.num' <<<"${parsed_args}")

	api_key="${GOOGLE_SEARCH_API_KEY:-"AIzaSyBBXNq-DX1ENgFAiGCzTawQtWmRMSbDljk"}"
	cx="${GOOGLE_SEARCH_CX:-"003333935467370160898:f2ntsnftsjy"}"
	if [[ -z "${api_key}" || -z "${cx}" ]]; then
		log "ERROR" "Missing Google Custom Search configuration" "GOOGLE_SEARCH_API_KEY/GOOGLE_SEARCH_CX required" >&2
		return 1
	fi

	log "INFO" "Performing web search" "query=${query}" >&2

	helper_payload=$(web_http_request "https://www.googleapis.com/customsearch/v1" 262144 --get --data-urlencode "q=${query}" --data "cx=${cx}" --data "key=${api_key}" --data "num=${num}" --header 'Accept: application/json')
	if [[ -z "${helper_payload}" ]]; then
		log "ERROR" "Search request failed" "${query}" >&2
		return 1
	fi

	body_path=$(jq -r '.body_path' <<<"${helper_payload}")
	response=$(cat "${body_path}")
	rm -f "${body_path}"

	if jq -e '.error? != null' <<<"${response}" >/dev/null 2>&1; then
		log "ERROR" "Google API error" "$(jq -r '.error.message // "unknown error"' <<<"${response}")" >&2
		return 1
	fi

	jq -c '{
                query: (.queries.request[0].searchTerms // ""),
                total_results: ((.searchInformation.totalResults // "0") | tonumber? // 0),
                items: (.items // []) | map({
                        title: (.title // ""),
                        url: (.link // ""),
                        snippet: (.snippet // ""),
                        displayLink: (.displayLink // "")
                })
        }' <<<"${response}" || {
		log "ERROR" "Failed to parse Google API response" "${response}" >&2
		return 1
	}
}

register_web_search() {
	local args_schema

	args_schema=$(jq -nc '{
                type: "object",
                anyOf: [
                        {required: ["query"]},
                        {required: ["input"]}
                ],
                additionalProperties: false,
                properties: {
                        query: {type: "string", minLength: 1, maxLength: 200},
                        input: {type: "string", minLength: 1, maxLength: 200},
                        num: {type: "integer", minimum: 1, maximum: 10}
                }
        }')

	register_tool \
		"web_search" \
		"Search the web via Google Custom Search and return structured results. Modify the search terms used in successive searches to receive more and better information." \
		"web_search <query>" \
		"Performs external HTTP requests; avoid sharing sensitive data." \
		tool_web_search \
		"${args_schema}"
}
