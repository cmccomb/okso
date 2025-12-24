#!/usr/bin/env bash
# shellcheck shell=bash
#
# Deterministic summarization utilities for tool observations.
#
# Usage:
#   source "${BASH_SOURCE[0]%/observation_summary.sh}/observation_summary.sh"
#
# Environment variables:
#   None.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on invalid input or serialization failures.

OBS_HEAD_TAIL_BYTES=120

# summarize_text_block produces a bounded summary for a text payload.
# Arguments:
#   $1 - text payload (string)
# Outputs:
#   JSON object string with {lines,bytes,head,tail}.
summarize_text_block() {
	local text_payload head tail line_count byte_count
	text_payload="$1"

	head=$(printf '%s' "${text_payload}" | head -c "${OBS_HEAD_TAIL_BYTES}")
	tail=$(printf '%s' "${text_payload}" | tail -c "${OBS_HEAD_TAIL_BYTES}")
	line_count=$(printf '%s' "${text_payload}" | wc -l | tr -d ' ')
	byte_count=$(printf '%s' "${text_payload}" | wc -c | tr -d ' ')

	jq -ncS --arg head "${head}" --arg tail "${tail}" --argjson lines "${line_count}" --argjson bytes "${byte_count}" \
		'{lines:$lines,bytes:$bytes,head:$head,tail:$tail}'
}

# summarize_terminal_output builds a deterministic summary for command-style observations.
# Arguments:
#   $1 - observation JSON with output, error, exit_code, optional cwd (string)
#   $2 - fallback cwd (string)
# Outputs:
#   JSON object string with exit_code, cwd, output/error summaries.
summarize_terminal_output() {
	local observation fallback_cwd exit_code output error cwd output_summary error_summary
	observation="$1"
	fallback_cwd="$2"

	exit_code=$(jq -r '.exit_code // 0' <<<"${observation}" 2>/dev/null || printf '0')
	output=$(jq -r '.output // ""' <<<"${observation}" 2>/dev/null || printf '')
	error=$(jq -r '.error // ""' <<<"${observation}" 2>/dev/null || printf '')
	cwd=$(jq -r '.cwd // empty' <<<"${observation}" 2>/dev/null || printf '')
	if [[ -z "${cwd}" ]]; then
		cwd="${fallback_cwd}" || true
	fi

	output_summary=$(summarize_text_block "${output}")
	error_summary=$(summarize_text_block "${error}")

	jq -ncS \
		--argjson exit_code "${exit_code}" \
		--arg cwd "${cwd}" \
		--argjson output "${output_summary}" \
		--argjson error "${error_summary}" \
		'{exit_code:$exit_code,cwd:$cwd,output:$output,error:$error}'
}

# summarize_web_search_results emits a bounded summary of web search payloads.
# Arguments:
#   $1 - observation JSON (string) with output containing search results JSON
# Outputs:
#   JSON object string with counts and top items.
summarize_web_search_results() {
	local observation output parsed top_count
	observation="$1"

	output=$(jq -r '.output // ""' <<<"${observation}" 2>/dev/null || printf '')
	if ! parsed=$(jq -c '.' <<<"${output}" 2>/dev/null); then
		parsed=$(jq -nc '{query:"",items:[],total_results:0}')
	fi

	top_count=3
	jq -ncS \
		--argjson parsed "${parsed}" \
		--argjson top_count "${top_count}" \
		'($parsed // {}) as $p | {
                        query: ($p.query // ""),
                        total_results: ($p.total_results // 0),
                        item_count: (($p.items // []) | length),
                        top_items: (($p.items // []) | [.[0:$top_count][] | {title: (.title // ""), url: (.url // ""), snippet: ((.snippet // "") | .[0:120])}])
                }'
}

# summarize_file_ops creates a deterministic summary for file operation observations.
# Arguments:
#   $1 - observation JSON (string)
#   $2 - fallback cwd (string)
# Outputs:
#   JSON object string describing counts of mutated paths and output snippets.
summarize_file_ops() {
	local observation fallback_cwd cwd created updated deleted output_summary
	observation="$1"
	fallback_cwd="$2"

	cwd=$(jq -r '.cwd // empty' <<<"${observation}" 2>/dev/null || printf '')
	if [[ -z "${cwd}" ]]; then
		cwd="${fallback_cwd}" || true
	fi

	created=$(jq -cr '(.created // []) | map(tostring)' <<<"${observation}" 2>/dev/null || printf '[]')
	updated=$(jq -cr '(.updated // []) | map(tostring)' <<<"${observation}" 2>/dev/null || printf '[]')
	deleted=$(jq -cr '(.deleted // []) | map(tostring)' <<<"${observation}" 2>/dev/null || printf '[]')

	output_summary=$(summarize_text_block "$(jq -r '.output // ""' <<<"${observation}" 2>/dev/null || printf '')")

	jq -ncS \
		--arg cwd "${cwd}" \
		--argjson created "${created}" \
		--argjson updated "${updated}" \
		--argjson deleted "${deleted}" \
		--argjson output "${output_summary}" \
		'{cwd:$cwd,created:$created,updated:$updated,deleted:$deleted,output:$output}'
}

# summarize_observation selects a tool-aware summarizer for the provided observation.
# Arguments:
#   $1 - tool name (string)
#   $2 - observation payload (string)
#   $3 - fallback cwd (string)
# Outputs:
#   Compact JSON string summary.
summarize_observation() {
	local tool observation fallback_cwd
	tool="$1"
	observation="$2"
	fallback_cwd="$3"

	case "${tool}" in
	web_search)
		summarize_web_search_results "${observation}"
		;;
	terminal)
		summarize_terminal_output "${observation}" "${fallback_cwd}"
		;;
	*)
		if jq -e '.created? or .updated? or .deleted?' <<<"${observation}" >/dev/null 2>&1; then
			summarize_file_ops "${observation}" "${fallback_cwd}"
		else
			summarize_terminal_output "${observation}" "${fallback_cwd}"
		fi
		;;
	esac
}

# select_observation_summary extracts a provided summary or computes one deterministically.
# Arguments:
#   $1 - tool name (string)
#   $2 - observation payload (string)
#   $3 - fallback cwd (string)
# Outputs:
#   Compact JSON string summary.
select_observation_summary() {
	local tool observation fallback_cwd existing_summary
	tool="$1"
	observation="$2"
	fallback_cwd="$3"

	existing_summary=$(jq -r '.summary // empty' <<<"${observation}" 2>/dev/null || printf '')
	if [[ -n "${existing_summary}" && "${existing_summary}" != "null" ]]; then
		printf '%s' "${existing_summary}"
		return 0
	fi

	summarize_observation "${tool}" "${observation}" "${fallback_cwd}"
}
