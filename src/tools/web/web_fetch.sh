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

web_fetch_normalize_url() {
	# Normalizes URLs by stripping trailing punctuation to align with web_fetch allowlists.
	# Arguments:
	#   $1 - URL string
	# Returns:
	#   Normalized URL string.
	local url
	url="$1"

	if [[ -z "${url}" ]]; then
		return 1
	fi

	printf '%s' "${url}" | sed -E 's/[),.]+$//'
}

web_fetch_snippet_for_url() {
	# Retrieves a snippet for the URL from web_search metadata.
	# Checks both raw and normalized URLs so lookups match allowlist normalization.
	# Arguments:
	#   $1 - URL string
	# Returns:
	#   Prints snippet if found; returns non-zero otherwise.
	local url normalized_url snippet
	url="$1"
	normalized_url="$(web_fetch_normalize_url "${url}")" || normalized_url=""

	if [[ -z "${WEB_FETCH_SEARCH_SNIPPETS:-}" ]]; then
		return 1
	fi

	if ! snippet=$(jq -r \
		--arg url "${url}" \
		--arg normalized_url "${normalized_url}" \
		'if type == "object" then .[$url] // .[$normalized_url] // "" else "" end' \
		<<<"${WEB_FETCH_SEARCH_SNIPPETS}" 2>/dev/null); then
		return 1
	fi

	if [[ -z "${snippet}" ]]; then
		return 1
	fi

	printf '%s' "${snippet}"
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
	# Downloads the response body for a URL, enforcing size limits and returning a small, LM-friendly JSON.
	#
	# Output (always):
	#   {
	#     url, final_url, status, content_type, headers, bytes, truncated,
	#     body_encoding: "text"|"base64",
	#     body_snippet: "<=1024 chars",
	#     body_markdown: "<=1024 chars" | null,
	#     anchor_query: "<=80 chars",
	#     anchor_match: true|false,
	#     error: null|string
	#   }
	#
	# Notes:
	# - Does NOT return the full response body.
	# - Guarantees body_snippet <= 1024 chars for both text and base64.
	# - Anchors text previews only when markdownify output is available.

	local parsed_args url max_bytes response payload body_path content_type final_url status_code
	local headers bytes truncated
	local body_encoding body_snippet preview_limit
	local anchor_query anchor_match snippet raw_snippet normalized_snippet
	local bytes_in converter_output body_markdown

	# Parse and validate arguments
	if ! parsed_args=$(web_fetch_parse_args); then
		return 1
	fi

	url="$(jq -r '.url' <<<"${parsed_args}")"
	max_bytes=${WEB_FETCH_MAX_BYTES:-5242880}
	preview_limit=1024
	anchor_match="false"
	anchor_query=""

	# Seed an anchor query (from web_search snippet when possible)
	if snippet="$(web_fetch_snippet_for_url "${url}" 2>/dev/null)"; then
		raw_snippet="${snippet}"
		normalized_snippet="$(web_fetch_normalize_snippet "${raw_snippet}" 2>/dev/null || true)"
		anchor_query="${normalized_snippet:-${raw_snippet}}"
	fi

	# Fetch
	log "INFO" "Fetching URL" "${url}" >&2
	response="$(web_http_request "${url}" "${max_bytes}" --header 'Accept: */*')"
	if [[ -z "${response}" ]]; then
		log "ERROR" "Failed to fetch URL" "${url}" >&2
		return 1
	fi

	# Parse HTTP helper payload
	payload="$(jq -er '.' <<<"${response}" 2>/dev/null)" || {
		log "ERROR" "Invalid HTTP helper payload" "${response}" >&2
		return 1
	}

	body_path="$(jq -r '.body_path' <<<"${payload}")"
	content_type="$(jq -r '.content_type // "application/octet-stream"' <<<"${payload}")"
	final_url="$(jq -r '.final_url // ""' <<<"${payload}")"
	status_code="$(jq -r '.status // 0' <<<"${payload}")"
	headers="$(jq -r '.headers // ""' <<<"${payload}")"
	bytes="$(jq -r '.bytes // 0' <<<"${payload}")"
	truncated="$(jq -r '.truncated // false' <<<"${payload}")"

	# Decide encoding
	body_encoding="text"
	if [[ -n "${content_type}" ]]; then
		local ct_lower
		ct_lower="$(printf '%s' "${content_type}" | tr '[:upper:]' '[:lower:]')"
		case "${ct_lower}" in
		text/* | *json* | *xml*) ;;
		*) body_encoding="base64" ;;
		esac
	fi

	body_markdown=""
	body_snippet=""

	if [[ "${body_encoding}" == "base64" ]]; then
		# 1024 base64 chars corresponds to 768 bytes input (1024 * 3/4)
		bytes_in=768
		body_snippet="$(head -c "${bytes_in}" "${body_path}" | base64 | tr -d '\n' | head -c "${preview_limit}")"
		body_markdown=""
	else
		# Prefer markdownify for cleaner text + anchoring
		if converter_output="$("${WEB_TOOLS_DIR}/markdownify.sh" --path "${body_path}" --content-type "${content_type}" --limit "${preview_limit}" 2>&1)"; then
			# preview is already limited by markdownify
			body_snippet="$(jq -r '.preview // ""' <<<"${converter_output}" 2>/dev/null)"
			body_markdown="$(jq -r '.markdown // ""' <<<"${converter_output}" 2>/dev/null)"
		else
			log "WARN" "Markdown conversion failed" "${converter_output}" >&2
			body_snippet="$(head -c "${preview_limit}" "${body_path}")"
			body_markdown=""
		fi

		# Anchor the preview around the query when we have markdown
		if [[ -n "${body_markdown}" && -n "${anchor_query}" ]]; then
			local anchor_result
			anchor_result="$(web_fetch_anchor_preview "${body_markdown}" "${body_snippet}" "${anchor_query}" "${preview_limit}")"
			body_snippet="$(jq -r '.snippet // ""' <<<"${anchor_result}" 2>/dev/null)"
			anchor_match="$(jq -r '.matched // false' <<<"${anchor_result}" 2>/dev/null)"
		fi

		# Hard cap, just in case (defensive)
		if ((${#body_snippet} > preview_limit)); then
			body_snippet="${body_snippet:0:preview_limit}"
		fi
	fi

	# Clean up body file now that we have preview
	rm -f "${body_path}"

	# Error shaping: keep it simple, but include preview + status
	if [[ "${status_code}" -ge 400 ]]; then
		jq -nc \
			--arg url "${url}" \
			--arg final_url "${final_url:-${url}}" \
			--arg content_type "${content_type}" \
			--arg headers "${headers}" \
			--argjson bytes "${bytes}" \
			--argjson truncated "${truncated}" \
			--arg body_encoding "${body_encoding}" \
			--arg body_snippet "${body_snippet}" \
			--arg body_markdown "${body_markdown}" \
			--arg anchor_query "${anchor_query}" \
			--arg error "HTTP ${status_code}" \
			--argjson status "${status_code}" \
			--argjson anchor_match "$(if [[ "${anchor_match}" == "true" ]]; then printf 'true'; else printf 'false'; fi)" \
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
				body_markdown: ($body_markdown | if length > 0 then . else null end),
				anchor_query: $anchor_query,
				anchor_match: $anchor_match,
				error: $error
			}'
		return 0
	fi

	jq -nc \
		--arg url "${url}" \
		--arg final_url "${final_url:-${url}}" \
		--arg content_type "${content_type}" \
		--arg headers "${headers}" \
		--argjson bytes "${bytes}" \
		--argjson truncated "${truncated}" \
		--arg body_encoding "${body_encoding}" \
		--arg body_snippet "${body_snippet}" \
		--arg body_markdown "${body_markdown}" \
		--arg anchor_query "${anchor_query}" \
		--argjson status "${status_code}" \
		--argjson anchor_match "$(if [[ "${anchor_match}" == "true" ]]; then printf 'true'; else printf 'false'; fi)" \
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
			body_markdown: ($body_markdown | if length > 0 then . else null end),
			anchor_query: $anchor_query,
			anchor_match: $anchor_match,
			error: null
		}'
}

register_web_fetch() {
	local args_schema

	args_schema=$(
		jq -c . <<'JSON'
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

	register_tool \
		"web_fetch" \
		"Retrieve the raw HTTP response body for a URL. Only retrieve URLs that you know exist (e.g. from web_search results)." \
		"Performs external HTTP requests; avoid sharing sensitive data." \
		tool_web_fetch \
		"${args_schema}"
}
