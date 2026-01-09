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

web_fetch_normalize_snippet() {
	# Normalizes a snippet for anchor matching.
	# Arguments:
	#   $1 - snippet text (string)
	# Returns:
	#   Normalized snippet text (string)
	local snippet cleaned phrase
	local max_words max_chars
	snippet="$1"
	max_words=8
	max_chars=80

	if [[ -z "${snippet}" ]]; then
		return 1
	fi

	cleaned=$(printf '%s' "${snippet}" | tr '\r\n' ' ' | sed -E 's/\.{3,}/ /g; s/…/ /g; s/[[:punct:]]+/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//')
	if [[ -z "${cleaned}" ]]; then
		return 1
	fi

	phrase=$(printf '%s' "${cleaned}" | awk -v max_words="${max_words}" '{for (i=1;i<=NF && i<=max_words;i++){printf (i==1?$i:" "$i)}}')
	if ((${#phrase} > max_chars)); then
		phrase="${phrase:0:max_chars}"
		phrase="$(printf '%s' "${phrase}" | sed -E 's/[[:space:]]+$//')"
	fi

	printf '%s' "${phrase}"
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

web_fetch_anchor_preview() {
	# Anchors a preview snippet around a query if possible.
	# Arguments:
	#   $1 - body markdown (string)
	#   $2 - base snippet (string)
	#   $3 - anchor query (string)
	#   $4 - snippet limit (int)
	# Returns:
	#   JSON payload with keys: snippet (string), matched (bool)
	local body_markdown base_snippet anchor_query snippet_limit
	local match_pos snippet_start snippet_end total_len window prefix suffix anchored_snippet
	body_markdown="$1"
	base_snippet="$2"
	anchor_query="$3"
	snippet_limit="$4"

	if [[ -z "${body_markdown}" || -z "${anchor_query}" ]]; then
		jq -nc --arg snippet "${base_snippet}" --argjson matched false '{snippet: $snippet, matched: $matched}'
		return 0
	fi

	match_pos=$(
		awk -v q="${anchor_query}" '
			BEGIN { q = tolower(q); off = 0 }
			{
				line = tolower($0)
				p = index(line, q)
				if (p > 0) { print off + p; exit }
				off += length($0) + 1  # +1 for the newline awk strips
			}
		' <<<"${body_markdown}"
	)

	if [[ -z "${match_pos}" ]]; then
		jq -nc --arg snippet "${base_snippet}" --argjson matched false '{snippet: $snippet, matched: $matched}'
		return 0
	fi

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
	anchored_snippet="${prefix}${window}${suffix}"

	jq -nc --arg snippet "${anchored_snippet}" --argjson matched true '{snippet: $snippet, matched: $matched}'
}

tool_web_fetch() {
	# Downloads the response body for a URL, enforcing size limits and returning JSON metadata.
	# Arguments:
	#   None (reads from TOOL_ARGS)
	# Returns:
	#   JSON object with fetch results or error observation.
	local parsed_args url max_bytes response payload body_path content_type truncated body_size headers final_url
	local body_encoding body_snippet snippet_limit body_markdown
	local anchor_query anchor_match anchor_note anchor_source snippet raw_snippet normalized_snippet

	# Parse and validate arguments
	if ! parsed_args=$(web_fetch_parse_args); then
		return 1
	fi

	# Extract URL
	url=$(jq -r '.url' <<<"${parsed_args}")
	max_bytes=${WEB_FETCH_MAX_BYTES:-5242880}
	anchor_match="false"

	# Attempt to get snippet from web_search results
	if snippet=$(web_fetch_snippet_for_url "${url}" 2>/dev/null); then
		raw_snippet="${snippet}"
		normalized_snippet="$(web_fetch_normalize_snippet "${raw_snippet}" 2>/dev/null || true)"
		if [[ -n "${normalized_snippet}" ]]; then
			anchor_query="${normalized_snippet}"
		else
			anchor_query="${raw_snippet}"
		fi
		anchor_source="web_search"
	else
		anchor_query="$(web_fetch_generate_search_query "${url}")"
		anchor_source="rephrase"
	fi

	# Perform HTTP request
	log "INFO" "Fetching URL" "${url}" >&2
	response=$(web_http_request "${url}" "${max_bytes}" --header 'Accept: */*')
	if [[ -z "${response}" ]]; then
		log "ERROR" "Failed to fetch URL" "${url}" >&2
		return 1
	fi

	# Parse HTTP helper payload
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
		# IMPORTANT: body_snippet must remain valid base64 if body_encoding=base64.
		body_snippet=$(head -c "${snippet_limit}" "${body_path}" | base64 | tr -d '\n')
	else
		local converter_output
		if converter_output=$("${WEB_TOOLS_DIR}/markdownify.sh" --path "${body_path}" --content-type "${content_type}" --limit "${snippet_limit}" 2>&1); then
			if body_markdown=$(jq -er '.markdown' <<<"${converter_output}" 2>/dev/null) &&
				body_snippet=$(jq -er '.preview' <<<"${converter_output}" 2>/dev/null); then
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

		# If we have markdown + an anchor query, attempt to center the preview window
		# around the *first* match (case-insensitive), using an absolute offset into the full markdown.
		if [[ -n "${body_markdown}" && -n "${anchor_query}" ]]; then
			local anchor_result fallback_query

			anchor_result="$(web_fetch_anchor_preview "${body_markdown}" "${body_snippet}" "${anchor_query}" "${snippet_limit}")"
			body_snippet="$(jq -r '.snippet' <<<"${anchor_result}")"
			anchor_match="$(jq -r '.matched' <<<"${anchor_result}")"

			if [[ "${anchor_match}" != "true" && "${anchor_source}" == "web_search" ]]; then
				fallback_query="$(web_fetch_generate_search_query "${url}")"
				if [[ -n "${fallback_query}" ]]; then
					anchor_query="${fallback_query}"
					anchor_source="rephrase"
					anchor_result="$(web_fetch_anchor_preview "${body_markdown}" "${body_snippet}" "${anchor_query}" "${snippet_limit}")"
					body_snippet="$(jq -r '.snippet' <<<"${anchor_result}")"
					anchor_match="$(jq -r '.matched' <<<"${anchor_result}")"
				fi
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
			'{ observation: "Failed to fetch \($url): HTTP \($status). Response body: \($body)" }'
		return 0
	fi

	# Only append anchor_note to body_snippet when body_snippet is text.
	# For base64 previews, appending plain text would corrupt the base64 payload.
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

	if [[ -n "${anchor_note}" && "${body_encoding}" == "text" ]]; then
		local note_sep note_len avail
		note_sep=$'\n\n'
		note_len=$((${#note_sep} + ${#anchor_note}))

		# If note somehow exceeds limit (unlikely), degrade gracefully.
		if ((note_len >= snippet_limit)); then
			body_snippet="${anchor_note:0:snippet_limit}"
		else
			avail=$((snippet_limit - note_len))
			# Trim preview to make room for the note, then append.
			if ((${#body_snippet} > avail)); then
				body_snippet="${body_snippet:0:avail}"
			fi
			body_snippet="${body_snippet}${note_sep}${anchor_note}"
		fi
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
		'{
			url: $url,
			final_url: $final_url,
			status: $status,
			content_type: $content_type,
			headers: $headers,
			bytes: $bytes,
			truncated: $truncated,
			body_encoding: $body_encoding,
			body_snippet: $body_snippet,
			body_markdown: (if ($body_markdown | length) > 0 then $body_markdown else null end),
			anchor_query: (if ($anchor_query | length) > 0 then $anchor_query else null end),
			anchor_match: $anchor_match
		}'
}

register_web_fetch() {
	local args_schema

	args_schema=$(jq -nc '{
                type: "object",
                required: ["url"],
                properties: {
                        url: {type: "string", format: "uri", minLength: 1},
                }
        }')

	register_tool \
		"web_fetch" \
		"Retrieve the raw HTTP response body for a URL. Only retrieve URLs that you know exist (e.g. from web_search results)." \
		"Performs external HTTP requests; avoid sharing sensitive data." \
		tool_web_fetch \
		"${args_schema}"
}
