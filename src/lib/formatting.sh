#!/usr/bin/env bash
# shellcheck shell=bash
#
# Formatting helpers for tool descriptions and summaries.
#
# Usage:
#   source "${BASH_SOURCE[0]%/formatting.sh}/formatting.sh"
#
# Environment variables:
#   None.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on misuse.

FORMATTING_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./core/logging.sh disable=SC1091
source "${FORMATTING_LIB_DIR}/core/logging.sh"

format_tool_descriptions() {
	# Arguments:
	#   $1 - newline-delimited allowed tool names (string)
	#   $2 - callback to format a single tool line (function name)
	local allowed_tools formatter tool_lines tool formatted_line
	allowed_tools="$1"
	formatter="$2"
	tool_lines=""

	if [[ -z "${formatter}" ]]; then
		log "ERROR" "format_tool_descriptions requires a formatter" ""
		return 1
	fi

	if ! declare -F "${formatter}" >/dev/null 2>&1; then
		log "ERROR" "Unknown tool formatter" "${formatter}"
		return 1
	fi

	while IFS= read -r tool || [[ -n "${tool}" ]]; do
		[[ -z "${tool}" ]] && continue
		formatted_line="$("${formatter}" "${tool}")"
		if [[ -n "${formatted_line}" ]]; then
			tool_lines+="${formatted_line}"$'\n'
		fi
	done <<<"${allowed_tools}"

	printf '%s' "${tool_lines%$'\n'}"
}

format_tool_details() {
	# Arguments:
	#   $1 - tool name (string)
	#   $2 - include schema (bool, optional)
	local tool description command safety include_schema args_schema
	local -a details=()
	local detail_text=""
	tool="$1"
	include_schema="${2:-false}"
	description="$(tool_description "${tool}")"
	command="$(tool_command "${tool}")"
	safety="$(tool_safety "${tool}")"

	if [[ -n "${description}" ]]; then
		details+=("${description}")
	fi

	if [[ "${include_schema}" == true ]]; then
		args_schema="$(tool_args_schema "${tool}")"
		if [[ -n "${args_schema}" && "${args_schema}" != "{}" ]]; then
			details+=("Args Schema: ${args_schema}")
		fi
	fi

	if [[ -n "${command}" ]]; then
		details+=("Example: ${command}")
	fi

	if [[ -n "${safety}" ]]; then
		details+=("Safety: ${safety}")
	fi

	if ((${#details[@]} == 0)); then
		return 0
	fi

	for i in $(seq 0 $((${#details[@]} - 1))); do
		if ((i > 0)); then
			detail_text+=' | '
		fi
		detail_text+="${details[i]}"
	done

	printf '%s' "${detail_text}"
}

render_box() {
	# Arguments:
	#   $1 - content to wrap inside the box (string)
	local content terminal_width max_line_length line width_limit lines top_border bottom_border padding
	content="$1"
	terminal_width="${COLUMNS:-"$(tput cols 2>/dev/null || printf '80')"}"
	if ! [[ "${terminal_width}" =~ ^[0-9]+$ ]]; then
		terminal_width=80
	fi

	# Keep some breathing room for borders and ensure a sane minimum width.
	width_limit=$((terminal_width - 4))
	if ((width_limit < 20)); then
		width_limit=20
	fi

	lines=()
	while IFS= read -r line || [[ -n "${line}" ]]; do
		lines+=("${line}")
	done < <(printf '%s\n' "${content}" | fold -s -w "${width_limit}")

	if ((${#lines[@]} == 0)); then
		lines=("")
	fi

	max_line_length=0
	for line in "${lines[@]}"; do
		if ((${#line} > max_line_length)); then
			max_line_length=${#line}
		fi
	done

	top_border="┌$(printf '─%.0s' $(seq 1 $((max_line_length + 2))))┐"
	bottom_border="└$(printf '─%.0s' $(seq 1 $((max_line_length + 2))))┘"

	printf '%s\n' "${top_border}"
	for line in "${lines[@]}"; do
		padding=$((max_line_length - ${#line}))
		printf '│ %s%*s │\n' "${line}" "${padding}" ""
	done
	printf '%s\n' "${bottom_border}"
}

indent_block() {
	# Arguments:
	#   $1 - prefix applied to every line (string)
	#   $2 - content to indent (string)
	local prefix content line
	prefix="$1"
	content="$2"

	while IFS= read -r line || [[ -n "${line}" ]]; do
		printf '%s%s\n' "${prefix}" "${line}"
	done <<<"${content}"
}

format_box_section() {
	# Arguments:
	#   $1 - section title (string)
	#   $2 - section body (string)
	local title body
	title="$1"
	body="$2"

	if [[ -z "${body}" ]]; then
		body="(none)"
	fi

	printf '%s:\n%s' "${title}" "$(indent_block '  ' "${body}")"
}

render_boxed_summary() {
	# Arguments:
	#   $1 - user query (string)
	#   $2 - planner outline (string)
	#   $3 - tool invocation history (newline-delimited string)
	#   $4 - final answer (string)
	local user_query plan_outline tool_history final_answer formatted_tools formatted_content
	user_query="$1"
	plan_outline="$2"
	tool_history="$3"
	final_answer="$4"

	if [[ -z "${tool_history}" ]]; then
		formatted_tools="(none)"
	else
		formatted_tools="$(format_tool_history "${tool_history}")"
	fi

	formatted_content=$(printf '%s\n\n%s\n\n%s\n\n%s' \
		"$(format_box_section "Query" "${user_query}")" \
		"$(format_box_section "Plan" "${plan_outline}")" \
		"$(format_box_section "Tool runs" "${formatted_tools}")" \
		"$(format_box_section "Final answer" "${final_answer}")")

	if command -v gum >/dev/null 2>&1; then
		# gum format can be slow on large inputs, but for summaries it adds nice markdown rendering.
		formatted_content="$(printf '%s\n' "${formatted_content}" | gum format)"
	fi

	render_box "${formatted_content}"
}

format_tool_history() {
	# Arguments:
	#   $1 - tool invocation history (newline-delimited string)
	# Returns:
	#   Grouped, human-friendly bullet list of tool runs (string)
	local tool_history line current_step current_action current_observation collecting_observation
	local -a output_lines=()
	tool_history="$1"
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

	while IFS= read -r line || [[ -n "${line}" ]]; do
		# Try to parse line as a JSON entry from record_tool_execution
		if jq -e '.step != null and .action != null' <<<"${line}" >/dev/null 2>&1; then
			append_current_entry
			current_step=$(jq -r '.step' <<<"${line}")
			local tool args thought obs
			tool=$(jq -r '.action.tool' <<<"${line}")
			args=$(jq -c '.action.args' <<<"${line}")
			thought=$(jq -r '.thought' <<<"${line}")

			# Pretty print observation if it's JSON object
			if jq -e '.observation | type == "object"' <<<"${line}" >/dev/null 2>&1; then
				local obs_obj
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

			current_action="${thought} (tool: ${tool}, args: ${args})"
			current_observation="${obs}"
			append_current_entry
			continue
		fi

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

emit_boxed_summary() {
	# Arguments:
	#   $1 - user query (string)
	#   $2 - planner outline (string)
	#   $3 - tool invocation history (newline-delimited string)
	#   $4 - final answer (string)
	render_boxed_summary "$@"
}

format_tool_line() {
	# Arguments:
	#   $1 - tool name (string)
	local tool detail_text
	tool="$1"
	detail_text="$(format_tool_details "${tool}")"

	if [[ -n "${detail_text}" ]]; then
		printf -- '- %s: %s' "${tool}" "${detail_text}"
		return 0
	fi

	printf -- '- %s' "${tool}"
}

format_tool_summary_line() {
	format_tool_line "$1"
}

format_tool_example_line() {
	format_tool_line "$1"
}
