#!/usr/bin/env bash
# shellcheck shell=bash
#
# User-facing output and formatting helpers for the okso assistant CLI.
#
# Usage:
#   source "${BASH_SOURCE[0]%/output.sh}/output.sh"
#
# Environment variables:
#   None.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return 0 on success.

OUTPUT_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=src/lib/cli/box.sh
source "${OUTPUT_LIB_DIR}/box.sh"
# shellcheck source=src/lib/ui/render.sh
source "${OUTPUT_LIB_DIR}/../ui/render.sh"
# shellcheck source=src/tools/registry.sh
source "${OUTPUT_LIB_DIR}/../../tools/registry.sh"

# Emits a message to stdout without an automatic trailing newline.
# Arguments:
#   $1 - message (string)
# Returns:
#   None.
user_output() {
	local message
	message="$1"
	printf '%s' "${message}"
}

# Emits a message followed by a newline to stdout.
# Arguments:
#   $1 - message (string)
# Returns:
#   None.
user_output_line() {
	local message
	message="$1"
	printf '%s\n' "${message}"
}

# Emits each provided argument as a separate line to stdout.
# Arguments:
#   $@ - messages (string array)
user_output_lines() {
	local line
	for line in "$@"; do
		user_output_line "${line}"
	done
}

format_tool_descriptions() {
	# Arguments:
	#   $1 - newline-delimited allowed tool names (string)
	#   $2 - callback to format a single tool line (function name)
	# Returns:
	#   Concatenated formatted tool lines (string)

	local allowed_tools formatter tool_lines tool formatted_line
	allowed_tools="$1"
	formatter="$2"
	tool_lines=""

	# Format each tool line using the provided formatter callback
	while IFS= read -r tool || [[ -n "${tool}" ]]; do
		[[ -z "${tool}" ]] && continue
		formatted_line="$("${formatter}" "${tool}")"
		if [[ -n "${formatted_line}" ]]; then
			tool_lines+="${formatted_line}"$'\n'
		fi
	done <<<"${allowed_tools}"

	# Return the concatenated tool lines without trailing newline
	printf '%s' "${tool_lines%$'\n'}"
}

format_tool_details() {
	# Arguments:
	#   $1 - tool name (string)
	#   $2 - include schema (bool, optional)
	# Returns:
	#   Formatted tool details (string)
	local tool description include_schema args_schema
	local -a details=()
	local detail_text=""
	tool="$1"
	include_schema="${2:-false}"
	description="$(tool_description "${tool}")"

	# Collect available details
	if [[ -n "${description}" ]]; then
		details+=("${description}")
	fi

	# Include args schema if requested
	if [[ "${include_schema}" == true ]]; then
		args_schema="$(tool_args_schema "${tool}")"
		if [[ -n "${args_schema}" && "${args_schema}" != "{}" ]]; then
			details+=("Args Schema: ${args_schema}")
		fi
	fi

	# Combine details into a single string
	if ((${#details[@]} == 0)); then
		return 0
	fi

	# Join details with separator
	for i in $(seq 0 $((${#details[@]} - 1))); do
		if ((i > 0)); then
			detail_text+=' | '
		fi
		detail_text+="${details[i]}"
	done

	# Return the detail text
	printf '%s' "${detail_text}"
}

format_duration_seconds() {
	# Formats a duration in seconds into H:MM:SS or MM:SS.
	# Arguments:
	#   $1 - duration in seconds (int)
	# Returns:
	#   Formatted duration string
	local total_seconds hours minutes seconds
	total_seconds="$1"
	if ! [[ "${total_seconds}" =~ ^[0-9]+$ ]]; then
		total_seconds=0
	fi
	hours=$((total_seconds / 3600))
	minutes=$(((total_seconds % 3600) / 60))
	seconds=$((total_seconds % 60))

	if ((hours > 0)); then
		printf '%d:%02d:%02d' "${hours}" "${minutes}" "${seconds}"
	else
		printf '%02d:%02d' "${minutes}" "${seconds}"
	fi
}

format_duration_from() {
	# Formats the elapsed duration from a start timestamp.
	# Arguments:
	#   $1 - start timestamp in seconds (int)
	# Returns:
	#   Formatted duration string
	local start_time now elapsed
	start_time="$1"
	now="$(date +%s)"
	if ! [[ "${start_time}" =~ ^[0-9]+$ ]]; then
		start_time="${now}"
	fi
	elapsed=$((now - start_time))
	if ((elapsed < 0)); then
		elapsed=0
	fi
	format_duration_seconds "${elapsed}"
}

format_header_line() {
	# Formats a header line with left/right aligned segments.
	# Arguments:
	#   $1 - left text (string)
	#   $2 - right text (string)
	#   $3 - width limit (int)
	# Returns:
	#   Header line string
	local left right width padding
	left="$1"
	right="$2"
	width="$3"

	if ((width < 0)); then
		width=0
	fi

	if ((${#left} + ${#right} + 1 > width)); then
		printf '%s | %s' "${left}" "${right}"
		return 0
	fi

	padding=$((width - ${#left} - ${#right}))
	printf '%s%*s%s' "${left}" "${padding}" "" "${right}"
}

render_step_box() {
	# Renders lifecycle details as a trace block when trace mode is enabled.
	# Arguments:
	#   $1 - step name (string)
	#   $2 - duration string (string)
	#   $3 - body content (string)
	# Returns:
	#   None.
	local step_name duration body header_line
	step_name="$1"
	duration="$2"
	body="$3"
	header_line="$(format_header_line "${step_name}" "${duration}" "$(ui_width_target)")"

	if [[ -z "${body}" ]]; then
		body="(none)"
	fi

	ui_trace_block "${header_line}" "${body}"
}

indent_block() {
	# Indents each line of the given content with the specified prefix.
	# Arguments:
	#   $1 - prefix applied to every line (string)
	#   $2 - content to indent (string)
	# Returns:
	#  Indented content (string)
	local prefix content line
	prefix="$1"
	content="$2"

	# Indent each line with the given prefix
	while IFS= read -r line || [[ -n "${line}" ]]; do
		printf '%s%s\n' "${prefix}" "${line}"
	done <<<"${content}"
}

format_box_section() {
	# Formats a section for boxed summary output.
	# Arguments:
	#   $1 - section title (string)
	#   $2 - section body (string)
	# Returns:
	#   Formatted box section (string)
	local title body
	title="$1"
	body="$2"

	if [[ -z "${body}" ]]; then
		body="(none)"
	fi

	printf '%s:\n%s' "${title}" "$(indent_block '  ' "${body}")"
}

render_boxed_summary() {
	# Renders a full execution summary only in trace mode.
	# Arguments:
	#   $1 - user query (string)
	#   $2 - planner outline (string)
	#   $3 - tool invocation history (newline-delimited string)
	#   $4 - final answer (string)
	# Returns:
	#   None.

	local user_query plan_outline tool_history final_answer formatted_tools formatted_content
	user_query="$1"
	plan_outline="$2"
	tool_history="$3"
	final_answer="$4"

	# Format tool history
	if [[ -z "${tool_history}" ]]; then
		formatted_tools="(none)"
	else
		formatted_tools="$(format_tool_history "${tool_history}")"
	fi

	# Combine all sections into the boxed content
	formatted_content=$(printf '%s\n\n%s\n\n%s\n\n%s' \
		"$(format_box_section "Query" "${user_query}")" \
		"$(format_box_section "Plan" "${plan_outline}")" \
		"$(format_box_section "Tool runs" "${formatted_tools}")" \
		"$(format_box_section "Final answer" "${final_answer}")")

	ui_trace_block "run summary" "${formatted_content}"
}

format_plan_summary() {
	# Formats a plan identification summary body.
	# Arguments:
	#   $1 - plan outline (string)
	#   $2 - required tools (newline-delimited string)
	#   $3 - plan entries JSON array (string)
	# Returns:
	#   Formatted summary body string
	local plan_outline required_tools plan_entries tool_lines step_count
	plan_outline="$1"
	required_tools="$2"
	plan_entries="$3"

	step_count="0"
	if [[ -n "${plan_entries}" ]]; then
		step_count="$(jq -r 'if type=="array" then length else 0 end' <<<"${plan_entries}" 2>/dev/null || printf '0')"
	fi

	if [[ -n "${required_tools}" ]]; then
		tool_lines="$(format_tool_descriptions "${required_tools}" "format_tool_example_line")"
	else
		tool_lines="(none)"
	fi

	printf '%s\n\n%s\n\n%s' \
		"$(format_box_section "Outline" "${plan_outline}")" \
		"$(format_box_section "Tools" "${tool_lines}")" \
		"$(format_box_section "Steps" "${step_count}")"
}

format_execution_steps_summary() {
	# Formats the execution steps summary body.
	# Arguments:
	#   $1 - tool history text (string)
	# Returns:
	#   Formatted summary body string
	local history_text formatted_history
	history_text="$1"

	if [[ -z "${history_text}" ]]; then
		formatted_history="(no tool runs)"
	else
		formatted_history="$(format_tool_history "${history_text}")"
	fi

	format_box_section "Steps" "${formatted_history}"
}

format_execution_step_summary() {
	# Formats a single execution step summary body.
	# Arguments:
	#   $1 - tool history JSON line (string)
	# Returns:
	#   Formatted summary body string
	local line step tool args thought observation action_line
	line="$1"

	step="$(jq -r '.step' <<<"${line}")"
	tool="$(jq -r '.action.tool' <<<"${line}")"
	args="$(jq -c '.action.args' <<<"${line}")"
	thought="$(jq -r '.thought' <<<"${line}")"
	observation="$(format_tool_observation_pretty "${line}" "${tool}")"

	if [[ -n "${thought}" ]]; then
		action_line="${thought} (tool: ${tool}, args: ${args})"
	else
		action_line="tool: ${tool}, args: ${args}"
	fi

	printf '%s\n\n%s' \
		"$(format_box_section "Step ${step} action" "${action_line}")" \
		"$(format_box_section "Observation" "${observation}")"
}

format_final_answer_summary() {
	# Formats the final answer summary body.
	# Arguments:
	#   $1 - final answer text (string)
	# Returns:
	#   Formatted summary body string
	format_box_section "Answer" "$1"
}

format_validation_summary() {
	# Formats the evaluation summary body.
	# Arguments:
	#   $1 - evaluation status (string)
	#   $2 - evaluation reasoning (string, optional)
	# Returns:
	#   Formatted summary body string
	local status reasoning
	status="$1"
	reasoning="${2:-}"

	if [[ -n "${reasoning}" ]]; then
		printf '%s\n\n%s' \
			"$(format_box_section "Status" "${status}")" \
			"$(format_box_section "Reason" "${reasoning}")"
	else
		format_box_section "Status" "${status}"
	fi
}

format_tool_line() {
	# Arguments:
	#   $1 - tool name (string)
	#   $2 - include schema (bool, optional)
	# Returns:
	#   Formatted tool line (string)
	local tool include_schema detail_text
	tool="$1"
	include_schema="${2:-true}"
	detail_text="$(format_tool_details "${tool}" "${include_schema}")"

	if [[ -n "${detail_text}" ]]; then
		printf -- '- %s: %s' "${tool}" "${detail_text}"
		return 0
	fi

	printf -- '- %s' "${tool}"
}

format_tool_example_line() {
	# Formats a single tool line with example command only.
	# Arguments:
	#   $1 - tool name (string)
	# Returns:
	#   Formatted tool line (string)
	if ui_trace_verbose_enabled; then
		format_tool_line "$1" true
	else
		format_tool_line "$1" false
	fi
}

format_tool_observation_raw() {
	# Formats a tool observation for machine-readable logs.
	# Arguments:
	#   $1 - tool history JSON line (string)
	#   $2 - tool name (string)
	# Returns:
	#   Compact JSON or raw string observation (string)
	local line
	line="$1"

	if jq -e '.observation | type == "string"' <<<"${line}" >/dev/null 2>&1; then
		jq -r '.observation' <<<"${line}"
		return 0
	fi

	jq -c '.observation' <<<"${line}"
}

format_tool_observation_pretty() {
	# Formats a tool observation for human-readable logs.
	# Arguments:
	#   $1 - tool history JSON line (string)
	#   $2 - tool name (string)
	# Returns:
	#   Human-friendly observation string
	local line tool obs obs_obj
	line="$1"
	tool="$2"

	if jq -e '.observation | type == "object"' <<<"${line}" >/dev/null 2>&1; then
		obs_obj=$(jq -c '.observation' <<<"${line}")

		# Check for enriched format first to handle failures generally
		if jq -e '.output != null and .exit_code != null' <<<"${obs_obj}" >/dev/null 2>&1; then
			local exit_code output error
			exit_code=$(jq -r '.exit_code' <<<"${obs_obj}")
			output=$(jq -r '.output' <<<"${obs_obj}")
			error=$(jq -r '.error' <<<"${obs_obj}")

			if ((exit_code != 0)); then
				obs="FAILED (exit code ${exit_code})"
				if [[ -n "${output}" ]]; then
					obs+=$'\n'"Output: ${output}"
				fi
				if [[ -n "${error}" ]]; then
					obs+=$'\n'"Error: ${error}"
				fi
			else
				# Success, try tool-specific formatting on the output string
				if [[ "${tool}" == "web_search" ]]; then
					if jq -e '.items | type == "array"' <<<"${output}" >/dev/null 2>&1; then
						obs=$(jq -r '.items | map("- " + .title + ": " + .snippet + " (URL: " + .url + ")") | join("\n")' <<<"${output}")
						[[ -z "${obs}" ]] && obs="(no results)"
					else
						obs=$(jq -r '.observation // .' <<<"${output}")
					fi
				elif [[ "${tool}" == "web_fetch" ]]; then
					if jq -e '.url != null and .body_snippet != null' <<<"${output}" >/dev/null 2>&1; then
						obs=$(jq -r '"URL: " + .url + "\nContent: " + .body_snippet' <<<"${output}")
					else
						obs=$(jq -r '.observation // .' <<<"${output}")
					fi
				elif jq -e '.observation != null' <<<"${output}" >/dev/null 2>&1; then
					obs=$(jq -r '.observation' <<<"${output}" 2>/dev/null || printf '%s' "${output}")
				else
					obs="${output}"
				fi
			fi
		else
			# Object but not enriched format (backward compatibility or direct state)
			if [[ "${tool}" == "web_search" ]]; then
				if jq -e '.items | type == "array"' <<<"${obs_obj}" >/dev/null 2>&1; then
					obs=$(jq -r '.items | map("- " + .title + ": " + .snippet + " (URL: " + .url + ")") | join("\n")' <<<"${obs_obj}")
					[[ -z "${obs}" ]] && obs="(no results)"
				else
					obs=$(jq -r '.observation // .' <<<"${obs_obj}")
				fi
			elif [[ "${tool}" == "web_fetch" ]]; then
				if jq -e '.url != null and .body_snippet != null' <<<"${obs_obj}" >/dev/null 2>&1; then
					obs=$(jq -r '"URL: " + .url + "\nContent: " + .body_snippet' <<<"${obs_obj}")
				else
					obs=$(jq -r '.observation // .' <<<"${obs_obj}")
				fi
			elif jq -e '.observation != null' <<<"${obs_obj}" >/dev/null 2>&1; then
				obs=$(jq -r '.observation' <<<"${obs_obj}" 2>/dev/null || printf '%s' "${obs_obj}")
			else
				obs=$(jq -c '.' <<<"${obs_obj}")
			fi
		fi
	elif jq -e '.observation | type == "string"' <<<"${line}" >/dev/null 2>&1; then
		obs=$(jq -r '.observation' <<<"${line}")
	else
		obs=$(jq -c '.observation' <<<"${line}")
	fi

	printf '%s' "${obs}"
}

format_tool_history_with_formatter() {
	# Arguments:
	#   $1 - tool invocation history (newline-delimited string)
	#   $2 - observation formatter function name (string)
	# Returns:
	#   Grouped tool run list (string)
	local tool_history formatter line current_step current_action current_observation collecting_observation
	local -a output_lines=()
	tool_history="$1"
	formatter="$2"
	current_step=""
	current_action=""
	current_observation=""
	collecting_observation=false

	append_current_entry() {
		if [[ -z "${current_step}" ]]; then
			return
		fi

		output_lines+=("- Step ${current_step}")
		if [[ -n "${current_action}" ]]; then
			output_lines+=("  action: ${current_action}")
		fi
		if [[ -n "${current_observation}" ]]; then
			output_lines+=("  observation: ${current_observation//$'\n'/$'\n'"  "}")
		fi

		current_step=""
		current_action=""
		current_observation=""
		collecting_observation=false
	}

	# Parse tool history line by line
	while IFS= read -r line || [[ -n "${line}" ]]; do
		# Try to parse line as a JSON entry from record_tool_execution
		if jq -e '.step != null and .action != null' <<<"${line}" >/dev/null 2>&1; then
			append_current_entry
			current_step=$(jq -r '.step' <<<"${line}")
			local tool args thought obs
			tool=$(jq -r '.action.tool' <<<"${line}")
			args=$(jq -c '.action.args' <<<"${line}")
			thought=$(jq -r '.thought' <<<"${line}")
			obs="$("${formatter}" "${line}" "${tool}")"

			current_action="${thought} (tool: ${tool}, args: ${args})"
			current_observation="${obs}"
			append_current_entry
			continue
		fi

		# Parse custom formatted history lines
		if [[ "${line}" =~ ^[[:space:]-]*Step[[:space:]]+([0-9]+)[[:space:]]*(.*)$ ]]; then
			append_current_entry

			current_step="${BASH_REMATCH[1]}"
			current_action="${BASH_REMATCH[2]}"
			current_action="${current_action#"${current_action%%[![:space:]]*}"}"
			current_action="${current_action%"${current_action##*[![:space:]]}"}"
			current_action="${current_action#action }"
			current_action="${current_action#action: }"
			current_action="${current_action#Action }"
			current_action="${current_action#Action: }"
			collecting_observation=false
			continue
		fi

		if [[ "${line}" =~ ^[[:space:]-]*[Oo][Bb][Ss][Ee][Rr][Vv][Aa][Tt][Ii][Oo][Nn]:?[[:space:]]*(.*)$ ]]; then
			current_observation="${BASH_REMATCH[1]}"
			collecting_observation=true
			continue
		fi

		if [[ -z "${current_step}" ]]; then
			if [[ "${line}" =~ ^[[:space:]]*-[[:space:]]+(.*)$ ]]; then
				output_lines+=("${line}")
			else
				output_lines+=(" - ${line}")
			fi
			continue
		fi

		# Strip existing action/observation prefixes if we are re-formatting
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line#"${line##*[![:space:]]}"}"
		line="${line#action: }"
		line="${line#Action: }"
		line="${line#observation: }"
		line="${line#Observation: }"

		if [[ "${collecting_observation}" == true ]]; then
			if [[ -n "${current_observation}" ]]; then
				current_observation+=$'\n'"${line}"
			else
				current_observation="${line}"
			fi
		else
			if [[ -n "${current_action}" ]]; then
				current_action+=" ${line}"
			else
				current_action="${line}"
			fi
		fi
	done <<<"${tool_history}"

	append_current_entry

	printf '%s\n' "${output_lines[@]}"
}

format_tool_history() {
	# Arguments:
	#   $1 - tool invocation history (newline-delimited string)
	# Returns:
	#   Grouped, machine-readable tool run list (string)
	format_tool_history_with_formatter "$1" format_tool_observation_raw
}

format_tool_history_pretty() {
	# Arguments:
	#   $1 - tool invocation history (newline-delimited string)
	# Returns:
	#   Grouped, human-friendly tool run list (string)
	format_tool_history_with_formatter "$1" format_tool_observation_pretty
}

emit_boxed_summary() {
	# Arguments:
	#   $1 - user query (string)
	#   $2 - planner outline (string)
	#   $3 - tool invocation history (newline-delimited string)
	#   $4 - final answer (string)
	# Returns:
	#   None; outputs boxed summary to stdout
	render_boxed_summary "$@"
}

output_clean_line() {
	# Normalizes arbitrary text for one-line summaries.
	# Arguments:
	#   $1 - raw text
	# Returns:
	#   normalized single-line text.
	ui_trim_spaces "$1"
}

collect_web_sources_json() {
	# Collects flattened search hit objects from executor history.
	# Arguments:
	#   $1 - newline-delimited history entries
	# Returns:
	#   JSON array of objects with title/url.
	local history_text
	history_text="$1"

	printf '%s\n' "${history_text}" | jq -Rsc '
		split("\n")
		| map(select(length > 0) | (try fromjson catch empty))
		| [ .[]
				| select(.action.tool == "web_search")
				| (.observation
						| if (type == "object" and has("output") and has("exit_code")) then
								(try (.output | fromjson) catch {})
							else
								.
							end
					)
				| .items[]?
				| {
						title: (.title // "Untitled"),
						url: (.url // "")
					}
			]
	' 2>/dev/null || printf '[]'
}

format_sources_block_from_history() {
	# Builds source lines from history for the final answer section.
	# Arguments:
	#   $1 - newline-delimited history entries
	# Returns:
	#   newline-delimited source lines.
	local history_text sources_json line url title
	local rank seen_urls
	history_text="$1"
	rank=0
	seen_urls=""

	sources_json="$(collect_web_sources_json "${history_text}")"
	while IFS= read -r line || [[ -n "${line}" ]]; do
		url="$(jq -r '.url // ""' <<<"${line}")"
		title="$(jq -r '.title // "Untitled"' <<<"${line}")"
		if [[ -z "${url}" ]]; then
			continue
		fi
		if grep -Fqx "${url}" <<<"${seen_urls}"; then
			continue
		fi
		seen_urls+="${url}"$'\n'
		rank=$((rank + 1))
		printf '[%d] %s — %s\n' "${rank}" "${title}" "${url}"
		if ((rank >= 5)); then
			break
		fi
	done < <(jq -c '.[]' <<<"${sources_json}" 2>/dev/null || true)

	if ((rank == 0)); then
		printf '(no web sources captured)\n'
	fi
}

emit_final_timeline_summary() {
	# Emits the final answer and supporting source list.
	# Arguments:
	#   $1 - final answer text
	#   $2 - history lines
	# Returns:
	#   None.
	local final_answer history_text sources_block
	final_answer="$1"
	history_text="${2:-}"

	sources_block="$(format_sources_block_from_history "${history_text}")"
	ui_final_summary "${final_answer}" "${sources_block}"
}

format_tool_event_message() {
	# Creates a one-line tool event message from tool + args.
	# Arguments:
	#   $1 - tool name
	#   $2 - args JSON
	# Returns:
	#   one-line message text.
	local tool args_json query url compact
	tool="$1"
	args_json="$2"

	case "${tool}" in
	web_search)
		query="$(jq -r '.query // .input // empty' <<<"${args_json}" 2>/dev/null || true)"
		if [[ -n "${query}" ]]; then
			printf '%s  query="%s"' "${tool}" "$(ui_truncate_line "${query}")"
		else
			printf '%s' "${tool}"
		fi
		;;
	web_fetch)
		url="$(jq -r '.url // empty' <<<"${args_json}" 2>/dev/null || true)"
		if [[ -n "${url}" ]]; then
			printf '%s  %s' "${tool}" "$(ui_display_url "${url}")"
		else
			printf '%s' "${tool}"
		fi
		;;
	final_answer)
		printf '%s' "composing ..."
		;;
	*)
		compact="$(jq -c '.' <<<"${args_json}" 2>/dev/null || printf '{}')"
		printf '%s  %s' "${tool}" "$(ui_truncate_line "${compact}")"
		;;
	esac
}
