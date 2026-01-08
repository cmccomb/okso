#!/usr/bin/env bash
# shellcheck shell=bash
#
# Web fetch tool that retrieves HTTP response bodies with size safeguards.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/web/web_fetch.sh}/tools/web/web_fetch.sh"
#
# Environment variables:
#   TOOL_ARGS (JSON object): structured args with required `url`.
#   WEB_FETCH_SEARCH_SNIPPETS (JSON object): optional mapping of url -> snippet from web_search results.
#
# Dependencies:
#   - bash 3.2+
#   - curl
#   - jq
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Non-zero on validation errors, network failures, or oversized payload handling.

WEB_TOOLS_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC_ROOT=$(cd -- "${WEB_TOOLS_DIR}/../.." && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${SRC_ROOT}/lib/core/logging.sh"
# shellcheck source=src/tools/web/http.sh
source "${WEB_TOOLS_DIR}/http.sh"
# shellcheck source=src/tools/registry.sh
source "${SRC_ROOT}/tools/registry.sh"
# shellcheck source=src/lib/planning/rephrasing.sh
source "${SRC_ROOT}/lib/planning/rephrasing.sh"

web_fetch_parse_args() {
	# Parses TOOL_ARGS JSON for the web_fetch tool.
	# Arguments:
	#   None
	# Returns:
	#   A JSON object with `url`.
	local args_json err
	args_json="${TOOL_ARGS:-}" || true

	if ! err=$(jq -cer '
                if (type != "object") then error("args must be object") end
                | if (.url? == null) then error("missing url") end
                | if (.url | type) != "string" or (.url | length) == 0 then error("url must be non-empty string") end
                | if ((del(.url) | length) != 0) then error("unexpected properties") end
                | {url: .url}
        ' <<<"${args_json}" 2>&1); then
		log "ERROR" "Invalid web_fetch arguments" "${err}" >&2
		return 1
	fi
	printf '%s' "${err}"
}

web_fetch_snippet_for_url() {
	# Retrieves a snippet for the URL from web_search metadata.
	# Arguments:
	#   $1 - URL string
	# Returns:
	#   Prints snippet if found; returns non-zero otherwise.
	local url snippet
	url="$1"

	if [[ -z "${WEB_FETCH_SEARCH_SNIPPETS:-}" ]]; then
		return 1
	fi

	if ! snippet=$(jq -r --arg url "${url}" 'if type == "object" then .[$url] // "" else "" end' <<<"${WEB_FETCH_SEARCH_SNIPPETS}" 2>/dev/null); then
		return 1
	fi

	if [[ -z "${snippet}" ]]; then
		return 1
	fi

	printf '%s' "${snippet}"
}

web_fetch_build_search_seed() {
	# Builds a base search query using the URL hostname and path.
	# Arguments:
	#   $1 - URL string
	# Returns:
	#   Prints a seed query string.
	local url host path path_query seed
	url="$1"

	host=$(printf '%s' "${url}" | sed -E 's#^[a-zA-Z]+://##; s#/.*##; s#:.*##')
	path=$(printf '%s' "${url}" | sed -E 's#^[a-zA-Z]+://##; s#^[^/]+##; s#[?#].*##')
	path=${path#/}
	path_query=$(printf '%s' "${path}" | tr '/_?-' '    ' | tr -s ' ')

	if [[ -n "${host}" ]]; then
		seed="site:${host}"
		if [[ -n "${path_query}" ]]; then
			seed+=" ${path_query}"
		fi
	else
		seed="${url}"
	fi

	printf '%s' "${seed}"
}

web_fetch_generate_search_query() {
	# Generates a search query using the rephrasing utilities.
	# Arguments:
	#   $1 - URL string
	# Returns:
	#   Prints a query string.
	local url seed queries query llama_available
	url="$1"

	seed="$(web_fetch_build_search_seed "${url}")"

	llama_available="${LLAMA_AVAILABLE:-false}"
	export LLAMA_AVAILABLE="${llama_available}"

	if ! queries="$(planner_generate_search_queries "${seed}" 2>/dev/null)"; then
		printf '%s' "${seed}"
		return 0
	fi

	query="$(jq -r 'if type == "array" then .[0] // "" else "" end' <<<"${queries}" 2>/dev/null)"
	if [[ -z "${query}" ]]; then
		query="${seed}"
	fi

	printf '%s' "${query}"
}

tool_web_fetch() {
	# Downloads the response body for a URL, enforcing size limits and returning JSON metadata.
	local parsed_args url max_bytes response payload body_path content_type truncated body_size headers final_url body_encoding body_snippet snippet_limit body_markdown
	local anchor_query anchor_match anchor_note anchor_source snippet

	if ! parsed_args=$(web_fetch_parse_args); then
		return 1
	fi

	url=$(jq -r '.url' <<<"${parsed_args}")
	max_bytes=${WEB_FETCH_MAX_BYTES:-5242880}
	anchor_match="false"
	if snippet=$(web_fetch_snippet_for_url "${url}" 2>/dev/null); then
		anchor_query="${snippet}"
		anchor_source="web_search"
	else
		anchor_query="$(web_fetch_generate_search_query "${url}")"
		anchor_source="rephrase"
	fi

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

	# snippet_limit (integer): maximum characters for preview snippets.
	snippet_limit=1024
	body_encoding="text"
	body_markdown=""
	if [[ -n "${content_type}" ]]; then
		local content_type_lower
		content_type_lower=$(printf '%s' "${content_type}" | tr '[:upper:]' '[:lower:]')
		case "${content_type_lower}" in
		text/* | *json* | *xml*) ;;
		*)
			body_encoding="base64"
			;;
		esac
	fi

	if [[ "${body_encoding}" == "base64" ]]; then
		body_snippet=$(head -c "${snippet_limit}" "${body_path}" | base64 | tr -d '\n')
	else
		local converter_output
		if converter_output=$("${WEB_TOOLS_DIR}/markdownify.sh" --path "${body_path}" --content-type "${content_type}" --limit "${snippet_limit}" 2>&1); then
			if body_markdown=$(jq -er '.markdown' <<<"${converter_output}" 2>/dev/null) && body_snippet=$(jq -er '.preview' <<<"${converter_output}" 2>/dev/null); then
				true
			else
				log "WARN" "Invalid markdownify output" "${converter_output}" >&2
				body_markdown=""
				body_snippet=$(head -c "${snippet_limit}" "${body_path}")
			fi
		else
			log "WARN" "Markdown conversion failed" "${converter_output}" >&2
			body_snippet=$(head -c "${snippet_limit}" "${body_path}")
		fi

		if [[ -n "${body_markdown}" && -n "${anchor_query}" ]]; then
			local match_pos snippet_start snippet_end total_len prefix suffix window
			match_pos=$(awk -v q="${anchor_query}" 'BEGIN{IGNORECASE=1} {pos=index(tolower($0), tolower(q)); if (pos>0) {print pos; exit}}' <<<"${body_markdown}")
			if [[ -n "${match_pos}" ]]; then
				total_len=${#body_markdown}
				snippet_start=$((match_pos - 1 - (snippet_limit / 2)))
				if ((snippet_start < 0)); then
					snippet_start=0
				fi
				snippet_end=$((snippet_start + snippet_limit))
				if ((snippet_end > total_len)); then
					snippet_end=${total_len}
				fi
				window=${body_markdown:${snippet_start}:$((snippet_end - snippet_start))}
				prefix=""
				suffix=""
				if ((snippet_start > 0)); then
					prefix="…"
				fi
				if ((snippet_end < total_len)); then
					suffix="…"
				fi
				body_snippet="${prefix}${window}${suffix}"
				anchor_match="true"
			else
				anchor_match="false"
			fi
		fi
	fi

	local status_code
	status_code=$(jq -r '.status' <<<"${payload}")

	rm -f "${body_path}"

	if [[ "${status_code}" -ge 400 ]]; then
		jq -nc \
			--arg url "${url}" \
			--arg status "${status_code}" \
			--arg body "${body_snippet}" \
			' { observation: "Failed to fetch \($url): HTTP \($status). Response body: \($body)" }'
		return 0
	fi

	if [[ "${anchor_source}" == "web_search" ]]; then
		if [[ "${anchor_match}" == "true" ]]; then
			anchor_note="... [Showing content surrounding search match]"
		elif [[ -n "${anchor_query}" ]]; then
			anchor_note="... [Search match not found; showing start of page]"
		else
			anchor_note=""
		fi
	else
		anchor_note=""
	fi

	if [[ -n "${anchor_note}" ]]; then
		body_snippet="${body_snippet}"$'\n\n'"${anchor_note}"
	fi

	jq -nc \
		--arg url "${url}" \
		--arg final_url "${final_url:-${url}}" \
		--arg content_type "${content_type}" \
		--arg headers "${headers}" \
		--arg body_snippet "${body_snippet}" \
		--arg body_markdown "${body_markdown}" \
		--arg body_encoding "${body_encoding}" \
		--arg anchor_query "${anchor_query}" \
		--argjson anchor_match "$(if [[ "${anchor_match}" == "true" ]]; then printf 'true'; else printf 'false'; fi)" \
		--argjson status "$(jq -r '.status' <<<"${payload}")" \
		--argjson bytes "${body_size}" \
		--argjson truncated "${truncated}" \
		'{url: $url, final_url: $final_url, status: $status, content_type: $content_type, headers: $headers, bytes: $bytes, truncated: $truncated, body_encoding: $body_encoding, body_snippet: $body_snippet, body_markdown: (if ($body_markdown | length) > 0 then $body_markdown else null end), anchor_query: (if ($anchor_query | length) > 0 then $anchor_query else null end), anchor_match: $anchor_match}'
}

register_web_fetch() {
	local args_schema

	schema_text=$(
		cat <<'JSON'
{
  "type": "object",
  "required": ["url"],
  "properties": {
    "url": {
      "type": "string",
      "format": "uri",
      "minLength": 1
      }
  }
}
JSON
	)

	args_schema=$(jq -n --argjson schema "$schema_text" '$schema')

	register_tool \
		"web_fetch" \
		"Retrieve the raw HTTP response body for a URL. Only retrieve URLs that you know exist (e.g. from web_search results)." \
		"Performs external HTTP requests; avoid sharing sensitive data." \
		tool_web_fetch \
		"${args_schema}"
}
