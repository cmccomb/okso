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
	local snippet cleaned
	snippet="$1"

	# Early exit if snippet is empty
	if [[ -z "${snippet}" ]]; then
		return 1
	fi

	# Clean snippet: remove terminal ellipses " ..."
	cleaned="$(sed -E 's/[[:space:]]*…$//; s/[[:space:]]*\.\.\.$//' <<<"${snippet}")"

	# Exit if cleaned snippet is empty
	if [[ -z "${cleaned}" ]]; then
		return 1
	fi

	printf '%s' "${cleaned}"
}

web_fetch_normalize_text() {
	# Normalizes text for token comparison.
	# Arguments:
	#   $1 - input text (string)
	# Returns:
	#   Normalized text (string)
	local text normalized
	text="$1"

	if [[ -z "${text}" ]]; then
		printf '%s' ""
		return 0
	fi

	normalized="$(
		printf '%s' "${text}" |
			sed -E \
				-e 's/[“”]/"/g' \
				-e "s/[‘’]/'/g" \
				-e 's/[—–]/-/g' \
				-e 's/…/.../g' |
			tr '[:upper:]' '[:lower:]' |
			sed -E \
				-e 's/(jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|may|jun(e)?|jul(y)?|aug(ust)?|sep(t(ember)?)?|oct(ober)?|nov(ember)?|dec(ember)?) +[0-9]{1,2},? +[0-9]{4}//g' \
				-e 's/[[:punct:]]+/ /g' \
				-e 's/[[:space:]]+/ /g; s/^ //; s/ $//'
	)"

	printf '%s' "${normalized}"
}

web_fetch_extract_tokens_with_positions() {
	# Extracts tokens with character spans from original text.
	# Arguments:
	#   $1 - input text (string)
	# Returns:
	#   Lines of: token<TAB>start_offset<TAB>end_offset (0-based, end exclusive)
	awk '
		BEGIN { pos = 0 }
		{
			line = $0
			while (match(line, /[[:alnum:]]+/)) {
				token = substr(line, RSTART, RLENGTH)
				start = pos + RSTART - 1
				end = start + RLENGTH
				printf "%s\t%d\t%d\n", token, start, end
				line = substr(line, RSTART + RLENGTH)
				pos += RSTART + RLENGTH - 1
			}
			pos += length(line) + 1
		}
	' <<<"$1"
}

web_fetch_best_token_window() {
	# Finds the best matching token window between snippet and body tokens.
	# Arguments:
	#   $1 - snippet tokens (space-delimited string)
	#   $2 - body tokens (space-delimited string)
	#   $3 - window size (int)
	#   $4 - step size (int)
	# Returns:
	#   "start_index end_index score" (0-based indexes, score float)
	awk -v snippet="$1" -v body="$2" -v win="$3" -v step="$4" '
		BEGIN {
			sn = split(snippet, s, " ")
			bn = split(body, b, " ")
			if (sn == 0 || bn == 0) {
				print "-1 -1 0"
				exit
			}
			if (step < 1) {
				step = 1
			}
			if (win > bn) {
				win = bn
			}
			for (i = 1; i <= sn; i++) {
				if (s[i] != "") {
					s_count[s[i]]++
				}
			}
			best = -1
			best_end = -1
			best_score = 0
			for (start = 1; start <= bn; start += step) {
				end = start + win - 1
				if (end > bn) {
					end = bn
				}
				delete seen
				inter = 0
				union = 0
				for (i = start; i <= end; i++) {
					if (b[i] == "") {
						continue
					}
					if (!(b[i] in seen)) {
						seen[b[i]] = 1
						union++
						if (b[i] in s_count) {
							inter++
						}
					}
				}
				for (token in s_count) {
					if (!(token in seen)) {
						union++
					}
				}
				score = union > 0 ? inter / union : 0
				if (score > best_score) {
					best_score = score
					best = start
					best_end = end
				}
			}
			if (best < 0) {
				print "-1 -1 0"
				exit
			}
			printf "%d %d %.6f\n", best - 1, best_end - 1, best_score
		}
	'
}

web_fetch_snippet_for_url() {
	# Retrieves a snippet for the URL from web_search metadata.
	# Checks both raw and normalized URLs so lookups match allowlist normalization.
	# Arguments:
	#   $1 - URL string
	# Returns:
	#   Prints snippet if found; returns non-zero otherwise.
	local url snippet
	url="$1"
	if [[ -z "${WEB_FETCH_SEARCH_SNIPPETS:-}" ]]; then
		return 1
	fi

	# If WEB_FETCH_SEARCH_SNIPPETS ends in double closing curly brackets, remove one of them
	if [[ "${WEB_FETCH_SEARCH_SNIPPETS}" == *"}}" ]]; then
		WEB_FETCH_SEARCH_SNIPPETS="${WEB_FETCH_SEARCH_SNIPPETS%?}"
	fi

	# Find the snippet for the exact URL
	snippet=$(jq -r \
		--arg url "${url}" \
		'if type == "object" then .[$url] // "" else "" end' \
		<<<"${WEB_FETCH_SEARCH_SNIPPETS}")

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
	local total_len window prefix suffix anchored_snippet
	local normalized_query normalized_body snippet_tokens body_token_lines
	local -a body_tokens body_starts body_ends
	local window_size window_step best_match best_start best_end best_span_start best_span_end
	body_markdown="$1"
	base_snippet="$2"
	anchor_query="$3"
	snippet_limit="$4"

	if [[ -z "${body_markdown}" || -z "${anchor_query}" ]]; then
		jq -nc --arg snippet "${base_snippet}" --argjson matched false '{snippet: $snippet, matched: $matched}'
		return 0
	fi

	normalized_query="$(web_fetch_normalize_text "${anchor_query}")"
	normalized_body="$(web_fetch_normalize_text "${body_markdown}")"

	if [[ -z "${normalized_query}" || -z "${normalized_body}" ]]; then
		jq -nc --arg snippet "${base_snippet}" --argjson matched false '{snippet: $snippet, matched: $matched}'
		return 0
	fi

	window_size=60
	window_step=$((window_size / 2))

	if ! body_token_lines="$(web_fetch_extract_tokens_with_positions "${body_markdown}")"; then
		jq -nc --arg snippet "${base_snippet}" --argjson matched false '{snippet: $snippet, matched: $matched}'
		return 0
	fi

	while IFS=$'\t' read -r raw_token raw_start raw_end; do
		if [[ -z "${raw_token}" ]]; then
			continue
		fi
		body_tokens+=("$(web_fetch_normalize_text "${raw_token}")")
		body_starts+=("${raw_start}")
		body_ends+=("${raw_end}")
	done <<<"${body_token_lines}"

	if ((${#body_tokens[@]} == 0)); then
		jq -nc --arg snippet "${base_snippet}" --argjson matched false '{snippet: $snippet, matched: $matched}'
		return 0
	fi

	local -a filtered_tokens filtered_starts filtered_ends
	local i token_lower next_token next_next_token
	local month_regex='^(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december)$'

	i=0
	while ((i < ${#body_tokens[@]})); do
		token_lower="${body_tokens[i]}"
		next_token="${body_tokens[i + 1]:-}"
		next_next_token="${body_tokens[i + 2]:-}"
		if [[ "${token_lower}" =~ ${month_regex} && "${next_token}" =~ ^[0-9]{1,2}$ && "${next_next_token}" =~ ^[0-9]{4}$ ]]; then
			i=$((i + 3))
			continue
		fi
		if [[ -n "${token_lower}" ]]; then
			filtered_tokens+=("${token_lower}")
			filtered_starts+=("${body_starts[i]}")
			filtered_ends+=("${body_ends[i]}")
		fi
		i=$((i + 1))
	done

	if ((${#filtered_tokens[@]} == 0)); then
		jq -nc --arg snippet "${base_snippet}" --argjson matched false '{snippet: $snippet, matched: $matched}'
		return 0
	fi

	snippet_tokens="${normalized_query}"
	best_match="$(web_fetch_best_token_window "${snippet_tokens}" "${filtered_tokens[*]}" "${window_size}" "${window_step}")"
	best_start="$(awk '{print $1}' <<<"${best_match}")"
	best_end="$(awk '{print $2}' <<<"${best_match}")"

	if [[ "${best_start}" -lt 0 || "${best_end}" -lt 0 ]]; then
		jq -nc --arg snippet "${base_snippet}" --argjson matched false '{snippet: $snippet, matched: $matched}'
		return 0
	fi

	best_span_start="${filtered_starts[best_start]}"
	best_span_end="${filtered_ends[best_end]}"

	if [[ -z "${best_span_start}" || -z "${best_span_end}" ]]; then
		jq -nc --arg snippet "${base_snippet}" --argjson matched false '{snippet: $snippet, matched: $matched}'
		return 0
	fi

	total_len=${#body_markdown}
	window=${body_markdown:${best_span_start}:$((best_span_end - best_span_start))}

	if ((${#window} > snippet_limit)); then
		window=${window:0:snippet_limit}
		best_span_end=$((best_span_start + snippet_limit))
	fi

	prefix=""
	suffix=""
	if ((best_span_start > 0)); then
		prefix="…"
	fi
	if ((best_span_end < total_len)); then
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

	local parsed_args url max_bytes response payload body_path content_type status_code
	local bytes
	local body_snippet preview_limit
	local anchor_query anchor_match snippet
	local converter_output body_markdown

	# Parse and validate arguments
	if ! parsed_args=$(web_fetch_parse_args); then
		return 1
	fi

	url="$(jq -r '.url' <<<"${parsed_args}")"
	max_bytes=${WEB_FETCH_MAX_BYTES:-5242880}
	preview_limit=1024
	anchor_match="false"
	anchor_query=""

	# Seed an anchor query from web_search snippet
	snippet="$(web_fetch_snippet_for_url "${url}")"
	anchor_query="$(web_fetch_normalize_snippet "${snippet}" 2>/dev/null || true)"

	# Fetch the URL with HTTP helper
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

	# Extract fields
	body_path="$(jq -r '.body_path' <<<"${payload}")"
	content_type="$(jq -r '.content_type // "application/octet-stream"' <<<"${payload}")"
	status_code="$(jq -r '.status // 0' <<<"${payload}")"
	bytes="$(jq -r '.bytes // 0' <<<"${payload}")"

	body_markdown=""
	body_snippet=""

	# Convert the body to markdown
	converter_output="$("${WEB_TOOLS_DIR}/markdownify.sh" --path "${body_path}" --content-type "${content_type}" --limit "${preview_limit}")"
	body_snippet="$(jq -r '.preview // ""' <<<"${converter_output}" 2>/dev/null)"
	body_markdown="$(jq -r '.markdown // ""' <<<"${converter_output}" 2>/dev/null)"

	# Anchor the preview around the query
	local anchor_result
	anchor_result="$(web_fetch_anchor_preview "${body_markdown}" "${body_snippet}" "${anchor_query}" "${preview_limit}")"
	anchor_match="$(jq -r '.matched // false' <<<"${anchor_result}" 2>/dev/null)"

	# Clean up body file now that we have preview
	rm -f "${body_path}"

	# Error shaping: keep it simple, but include preview + status
	if [[ "${status_code}" -ge 400 ]]; then
		jq -nc \
			--arg url "${url}" \
			--arg content_type "${content_type}" \
			--argjson bytes "${bytes}" \
			--arg error "HTTP ${status_code}" \
			--argjson status "${status_code}" \
			'{
				url: $url,
				status: $status,
				content_type: $content_type,
				bytes: $bytes,
				error: $error
			}'
		return 0
	fi

	jq -nc \
		--arg url "${url}" \
		--arg body_markdown "${body_markdown}" \
		--argjson anchor_match "$(if [[ "${anchor_match}" == "true" ]]; then printf 'true'; else printf 'false'; fi)" \
		'{
			url: $url,
			body_markdown: ($body_markdown | if length > 0 then . else null end),
			anchor_match: $anchor_match,
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
