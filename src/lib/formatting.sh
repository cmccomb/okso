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
#   - bash 5+
#   - jq
#
# Exit codes:
#   Functions return non-zero on misuse.

LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./logging.sh disable=SC1091
source "${LIB_DIR}/logging.sh"

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

	while IFS= read -r tool; do
		[[ -z "${tool}" ]] && continue
		formatted_line="$(${formatter} "${tool}")"
		if [[ -n "${formatted_line}" ]]; then
			tool_lines+="${formatted_line}"$'\n'
		fi
	done <<<"${allowed_tools}"

	printf '%s' "${tool_lines%$'\n'}"
}

format_tool_details() {
	# Arguments:
	#   $1 - tool name (string)
	local tool description command safety
	local -a details=()
	local detail_text=""
	tool="$1"
	description="$(tool_description "${tool}")"
	command="$(tool_command "${tool}")"
	safety="$(tool_safety "${tool}")"

	if [[ -n "${description}" ]]; then
		details+=("${description}")
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

	for i in "${!details[@]}"; do
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
	while IFS= read -r line || [ -n "${line}" ]; do
		lines+=("${line}")
	done <<EOF
$(printf '%s\n' "${content}" | fold -s -w "${width_limit}")
EOF

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

	formatted_content=$(
		cat <<EOF
Query:
${user_query}

Plan:
${plan_outline:-"(none)"}

Tool runs:
${formatted_tools}

Final answer:
${final_answer}
EOF
	)
	if command -v gum >/dev/null 2>&1; then
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

		output_lines+=(" - Step ${current_step}")
		if [[ -n "${current_action}" ]]; then
			output_lines+=("   action: ${current_action}")
		fi
		if [[ -n "${current_observation}" ]]; then
			output_lines+=("   observation: ${current_observation//$'\n'/$'\n'"   "}")
		fi

		current_step=""
		current_action=""
		current_observation=""
		collecting_observation=false
	}

	while IFS= read -r line || [ -n "${line}" ]; do
		if [[ "${line}" =~ ^[[:space:]]*Step[[:space:]]+([0-9]+)[[:space:]]*(.*)$ ]]; then
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
		if [[ "${line}" =~ ^[[:space:]]*[Oo][Bb][Ss][Ee][Rr][Vv][Aa][Tt][Ii][Oo][Nn]:[[:space:]]*(.*)$ ]]; then
			current_observation="${BASH_REMATCH[1]}"
			collecting_observation=true
			continue
		fi
		if [[ -z "${current_step}" ]]; then
			output_lines+=(" - ${line}")
			continue
		fi

		if [[ "${collecting_observation}" == true ]]; then
			if [[ -n "${current_observation}" ]]; then
				current_observation+=$'\n'"${line}"
			else
				current_observation="${line}"
			fi
			continue
		fi

		if [[ -n "${current_action}" ]]; then
			current_action+=" ${line}"
		else
			current_action="${line}"
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
	render_boxed_summary "$1" "$2" "$3" "$4"
}

format_tool_summary_line() {
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

format_tool_example_line() {
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
