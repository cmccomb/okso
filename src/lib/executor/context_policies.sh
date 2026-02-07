#!/usr/bin/env bash
# shellcheck shell=bash
#
# Context policy helpers for executor tool argument controls.
#
# Usage:
#   source "${BASH_SOURCE[0]%/context_policies.sh}/context_policies.sh"
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on validation failures.

EXECUTOR_CONTEXT_DIR=${EXECUTOR_CONTEXT_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)}

# shellcheck source=src/lib/core/logging.sh
source "${EXECUTOR_CONTEXT_DIR}/../core/logging.sh"
# shellcheck source=src/tools/registry.sh
source "${EXECUTOR_CONTEXT_DIR}/../../tools/registry.sh"

extract_urls_from_text() {
	# Extracts absolute URLs from plain text.
	# Arguments:
	#   $1 - text blob
	local text
	text="$1"

	if [[ -z "${text}" ]]; then
		return 0
	fi

	printf '%s' "${text}" | grep -Eo 'https?://[^[:space:]\")\]<>]+' 2>/dev/null || true
}

collect_notes_allowlist() {
	# Builds a JSON array of allowed note titles for notes_read/notes_append.
	# Arguments:
	#   $1 - history text (newline-delimited JSON entries)
	local history_text titles_json
	history_text="$1"

	if [[ -z "${history_text}" ]]; then
		printf '[]'
		return 0
	fi

	titles_json=$(
		jq -n -r '
                        def parse_entry:
                          if type == "string" then
                            try (fromjson) catch empty
                          elif type == "object" then
                            .
                          else
                            empty
                          end;

                        def unwrap_observation:
                          if (.observation | type) == "object" and (.observation | has("output")) and (.observation | has("exit_code")) then
                            .observation.output
                          else
                            .observation
                          end;

                        def trim: gsub("^\\s+|\\s+$"; "");

                        def note_items($obs):
                          if ($obs | type) == "string" then
                            ($obs | split("\n") | map(trim) | map(select(length > 0)))
                          elif ($obs | type) == "array" then
                            ($obs | map(tostring | trim) | map(select(length > 0)))
                          else
                            []
                          end;

                        [inputs | select(length > 0) | parse_entry]
                        | map(select(type == "object"))
                        | map(select(.action.tool == "notes_list" or .action.tool == "notes_search" or .action.tool == "notes_create"))
                        | map((unwrap_observation) as $obs | note_items($obs))
                        | (if length == 0 then [] else (reduce .[] as $entry ([]; . + $entry)) end)
                        | unique
                ' <<<"${history_text}" 2>/dev/null || true
	)

	if [[ -z "${titles_json}" ]]; then
		printf '[]'
		return 0
	fi

	printf '%s' "${titles_json}"
}

collect_reminders_allowlist() {
	# Builds a JSON array of allowed reminder titles for reminders_complete.
	# Arguments:
	#   $1 - history text (newline-delimited JSON entries)
	local history_text titles_json
	history_text="$1"

	if [[ -z "${history_text}" ]]; then
		printf '[]'
		return 0
	fi

	titles_json=$(
		jq -n -r '
                        def parse_entry:
                          if type == "string" then
                            try (fromjson) catch empty
                          elif type == "object" then
                            .
                          else
                            empty
                          end;

                        def unwrap_observation:
                          if (.observation | type) == "object" and (.observation | has("output")) and (.observation | has("exit_code")) then
                            .observation.output
                          else
                            .observation
                          end;

                        def trim: gsub("^\\s+|\\s+$"; "");

                        def reminder_items($obs):
                          if ($obs | type) == "array" then
                            ($obs | map(tostring | trim) | map(select(length > 0)))
                          elif ($obs | type) == "string" then
                            (if ($obs | contains("\n")) then
                              ($obs | split("\n") | map(trim) | map(select(length > 0)))
                            else
                              ([($obs | trim)] | map(select(length > 0)))
                            end)
                          else
                            []
                          end;

                        [inputs | select(length > 0) | parse_entry]
                        | map(select(type == "object"))
                        | map(select(.action.tool == "reminders_list" or .action.tool == "reminders_create"))
                        | map((unwrap_observation) as $obs | reminder_items($obs))
                        | (if length == 0 then [] else (reduce .[] as $entry ([]; . + $entry)) end)
                        | unique
                ' <<<"${history_text}" 2>/dev/null || true
	)

	if [[ -z "${titles_json}" ]]; then
		printf '[]'
		return 0
	fi

	printf '%s' "${titles_json}"
}

patch_schema_enum_property() {
	# Applies an enum allowlist to a tool args property in the registry schema.
	# Arguments:
	#   $1 - tool name
	#   $2 - property name
	#   $3 - enum values JSON array
	#   $4 - warning emitted when enum list is empty
	local tool_name property_name enum_json empty_warning base_schema patched_schema
	tool_name="$1"
	property_name="$2"
	enum_json="$3"
	empty_warning="$4"

	base_schema="$(tool_args_schema "${tool_name}")"
	if [[ -z "${base_schema}" ]]; then
		base_schema='{}'
	fi

	patched_schema="$(jq -c \
		--arg key "${property_name}" \
		--argjson values "${enum_json}" \
		'
                .type = "object"
                | .properties = (.properties // {})
                | .properties[$key] = ((.properties[$key] // {type:"string"}) + {type:"string", enum:$values})
                | .required = ((.required // []) + [$key] | unique)
        ' <<<"${base_schema}")"

	if [[ -z "${patched_schema}" ]]; then
		log "WARN" "Failed to patch schema enum property" "tool=${tool_name} property=${property_name}" || true
		return 0
	fi

	if [[ "${enum_json}" == "[]" && -n "${empty_warning}" ]]; then
		log "WARN" "${empty_warning}" "" || true
	fi

	update_tool_args_schema "${tool_name}" "${patched_schema}" || true
}

patch_notes_schema() {
	# Applies a title allowlist to notes_read and notes_append schemas.
	# Arguments:
	#   $1 - JSON array of allowed note titles
	local titles_json
	titles_json="$1"

	patch_schema_enum_property \
		"notes_read" \
		"input" \
		"${titles_json}" \
		"No allowlisted note titles; notes_read/notes_append will reject all titles"
	patch_schema_enum_property \
		"notes_append" \
		"title" \
		"${titles_json}" \
		""
}

patch_reminders_schema() {
	# Applies a title allowlist to reminders_complete schema.
	# Arguments:
	#   $1 - JSON array of allowed reminder titles
	local titles_json
	titles_json="$1"

	patch_schema_enum_property \
		"reminders_complete" \
		"input" \
		"${titles_json}" \
		"No allowlisted reminder titles; reminders_complete will reject all titles"
}

prepare_notes_context() {
	# Prepares allowlist schema for notes_read and notes_append.
	# Arguments:
	#   $1 - history text (newline-delimited JSON entries)
	local history_text titles_json
	history_text="$1"

	titles_json="$(collect_notes_allowlist "${history_text}")"
	patch_notes_schema "${titles_json}"
}

prepare_reminders_context() {
	# Prepares allowlist schema for reminders_complete.
	# Arguments:
	#   $1 - history text (newline-delimited JSON entries)
	local history_text titles_json
	history_text="$1"

	titles_json="$(collect_reminders_allowlist "${history_text}")"
	patch_reminders_schema "${titles_json}"
}

normalize_web_fetch_url() {
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

	printf '%s\n' "${url}" | sed -E 's/[),.]+$//'
}

collect_web_fetch_allowlist() {
	# Builds a JSON array of allowed URLs for web_fetch.
	# Handles web_search observations stored directly or wrapped in tool output metadata.
	# Normalizes URLs by stripping trailing punctuation.
	# Arguments:
	#   $1 - history text (newline-delimited JSON entries)
	#   $2 - user query
	#   $3 - plan outline
	#   $4 - planner thought
	local history_text user_query plan_outline planner_thought urls_json
	history_text="$1"
	user_query="$2"
	plan_outline="$3"
	planner_thought="$4"

	# Use history + current text sources so direct user-provided URLs are not blocked.
	urls_json=$(
		{
			if [[ -n "${history_text}" ]]; then
				jq -n -r '
                        def parse_entry:
                          if type == "string" then
                            try (fromjson) catch empty
                          elif type == "object" then
                            .
                          else
                            empty
                          end;

                        def search_items:
                          if (.observation | type) != "object" then
                            []
                          elif (.observation.items? | type) == "array" then
                            .observation.items
                          elif (.observation.output? | type) == "string" then
                            (try (.observation.output | fromjson) catch empty | .items? // [])
                          else
                            []
                          end;

                        [inputs | select(length > 0) | parse_entry]
                        | map(select(type == "object"))
                        | .[]
                        | select(.action.tool == "web_search")
                        | search_items
                        | .[]?
                        | .url
                ' <<<"${history_text}" 2>/dev/null || true
			fi
			extract_urls_from_text "${user_query}"
			extract_urls_from_text "${plan_outline}"
			extract_urls_from_text "${planner_thought}"
		} | while IFS= read -r url; do
			normalize_web_fetch_url "${url}"
		done | sort -u | jq -Rsc 'split("\n") | map(select(length>0))'
	)

	printf '%s' "${urls_json}"
}

collect_web_fetch_snippet_map() {
	# Builds a JSON object mapping URLs to web_search snippets for web_fetch.
	# Stores snippets under both raw and normalized URLs to match allowlist normalization.
	# Arguments:
	#   $1 - history text (newline-delimited JSON entries)
	local history_text snippet_json snippet_entries snippet_map entry url snippet normalized_url
	history_text="$1"

	snippet_json=$(
		if [[ -z "${history_text}" ]]; then
			printf '{}'
			return 0
		fi

		snippet_entries="$(jq -n -c '
                        def parse_entry:
                          if type == "string" then
                            try (fromjson) catch empty
                          elif type == "object" then
                            .
                          else
                            empty
                          end;

                        def search_items:
                          if (.observation | type) != "object" then
                            []
                          elif (.observation.items? | type) == "array" then
                            .observation.items
                          elif (.observation.output? | type) == "string" then
                            (try (.observation.output | fromjson) catch empty | .items? // [])
                          else
                            []
                          end;

                        [inputs | select(length > 0) | parse_entry]
                        | map(select(type == "object"))
                        | .[]
                        | select(.action.tool == "web_search")
                        | search_items
                        | .[]?
                        | select((.url? | type) == "string" and (.snippet? | type) == "string")
                        | select((.url | length) > 0 and (.snippet | length) > 0)
                        | {url: .url, snippet: .snippet}
                ' <<<"${history_text}" 2>/dev/null)" || true

		snippet_map='{}'
		while IFS= read -r entry; do
			[[ -z "${entry}" ]] && continue
			url="$(jq -r '.url' <<<"${entry}")"
			snippet="$(jq -r '.snippet' <<<"${entry}")"
			if [[ -z "${url}" || -z "${snippet}" ]]; then
				continue
			fi
			normalized_url="$(normalize_web_fetch_url "${url}")"
			# Mirror snippet under both keys because allowlist matching uses normalized URLs.
			snippet_map="$(jq -c \
				--arg url "${url}" \
				--arg snippet "${snippet}" \
				--arg normalized_url "${normalized_url}" \
				'. + {($url): $snippet} + (if ($normalized_url | length) > 0 and $normalized_url != $url then {($normalized_url): $snippet} else {} end)' \
				<<<"${snippet_map}")"
		done <<<"${snippet_entries}"

		printf '%s' "${snippet_map}"
	)

	printf '%s' "${snippet_json}"
}

validate_web_fetch_snippet_map() {
	# Validates the web_fetch snippet map JSON and defaults to {} on failure.
	# Arguments:
	#   $1 - snippet map JSON (string)
	local snippet_json
	snippet_json="${1:-}"

	if [[ -z "${snippet_json}" ]]; then
		printf '{}'
		return 0
	fi

	if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"${snippet_json}"; then
		log "WARN" "Invalid WEB_FETCH_SEARCH_SNIPPETS; defaulting to {}" "${snippet_json}" || true
		printf '{}'
		return 0
	fi

	printf '%s' "${snippet_json}"
}

patch_web_fetch_schema() {
	# Applies a URL allowlist to the web_fetch schema.
	# Arguments:
	#   $1 - JSON array of allowed URLs
	local urls_json
	urls_json="$1"

	patch_schema_enum_property \
		"web_fetch" \
		"url" \
		"${urls_json}" \
		"No allowlisted URLs for web_fetch; schema will reject all URLs"
}

prepare_web_fetch_context() {
	# Prepares allowlist schema and snippet map for web_fetch.
	# Arguments:
	#   $1 - history text (newline-delimited JSON entries)
	#   $2 - user query text
	#   $3 - plan outline text
	#   $4 - planner thought text
	#   $5 - (optional) name of variable to receive snippet map JSON
	# Returns:
	#   If $5 is set, assigns snippet map JSON to that variable and prints nothing.
	#   Otherwise prints snippet map JSON.

	local history_text user_query plan_outline planner_thought out_var
	local allowlist_json snippet_json

	history_text="$1"
	user_query="$2"
	plan_outline="$3"
	planner_thought="$4"
	out_var="${5:-}"

	allowlist_json="$(collect_web_fetch_allowlist "${history_text}" "${user_query}" "${plan_outline}" "${planner_thought}")"
	patch_web_fetch_schema "${allowlist_json}"

	snippet_json="$(collect_web_fetch_snippet_map "${history_text}")"
	snippet_json="$(validate_web_fetch_snippet_map "${snippet_json}")"

	if [[ -n "${out_var}" ]]; then
		# Support pass-by-name to avoid mixing function output with caller stdout streams.
		printf -v "${out_var}" '%s' "${snippet_json}"
		return 0
	fi

	printf '%s' "${snippet_json}"
}

context_policy_for_tool() {
	# Resolves a context policy name for a given tool.
	# Arguments:
	#   $1 - tool name
	# Returns:
	#   policy name on stdout.
	case "$1" in
	notes_read | notes_append)
		printf '%s' "notes"
		;;
	reminders_complete)
		printf '%s' "reminders"
		;;
	web_fetch)
		printf '%s' "web_fetch"
		;;
	*)
		printf '%s' "none"
		;;
	esac
}

prepare_tool_context_for_action() {
	# Applies tool-specific context preparation policy.
	# Arguments:
	#   $1 - tool name
	#   $2 - history text
	#   $3 - user query text
	#   $4 - plan outline text
	#   $5 - planner thought text
	#   $6 - optional name of variable to receive additional context payload
	local tool policy history_text user_query plan_outline planner_thought out_var
	tool="$1"
	history_text="$2"
	user_query="$3"
	plan_outline="$4"
	planner_thought="$5"
	out_var="${6:-}"

	policy="$(context_policy_for_tool "${tool}")"
	case "${policy}" in
	notes)
		prepare_notes_context "${history_text}"
		;;
	reminders)
		prepare_reminders_context "${history_text}"
		;;
	web_fetch)
		prepare_web_fetch_context "${history_text}" "${user_query}" "${plan_outline}" "${planner_thought}" "${out_var}"
		;;
	none) ;;
	esac
}

export -f extract_urls_from_text
export -f collect_notes_allowlist
export -f collect_reminders_allowlist
export -f patch_notes_schema
export -f patch_reminders_schema
export -f prepare_notes_context
export -f prepare_reminders_context
export -f normalize_web_fetch_url
export -f collect_web_fetch_allowlist
export -f collect_web_fetch_snippet_map
export -f validate_web_fetch_snippet_map
export -f prepare_web_fetch_context
export -f patch_web_fetch_schema
export -f context_policy_for_tool
export -f prepare_tool_context_for_action
