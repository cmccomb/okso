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

        mapfile -t lines < <(printf '%s\n' "${content}" | fold -s -w "${width_limit}")
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
        local user_query plan_outline tool_history final_answer formatted_tools summary_sections formatted_content
        user_query="$1"
        plan_outline="$2"
        tool_history="$3"
        final_answer="$4"

        if [[ -z "${tool_history}" ]]; then
                formatted_tools="(none)"
        else
                formatted_tools="$(printf '%s\n' "${tool_history}" | sed '/^$/d; s/^/ - /')"
        fi

        summary_sections=$(cat <<'EOF'
Query:
%s

Plan:
%s

Tool runs:
%s

Final answer:
%s
EOF
        )

        formatted_content=$(printf "${summary_sections}" "${user_query}" "${plan_outline:-"(none)"}" "${formatted_tools}" "${final_answer}")
        if command -v gum >/dev/null 2>&1; then
                formatted_content="$(printf '%s\n' "${formatted_content}" | gum format)"
        fi

        render_box "${formatted_content}"
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
	local tool
	tool="$1"
	printf -- '- %s: %s' "${tool}" "$(tool_description "${tool}")"
}

format_tool_example_line() {
	# Arguments:
	#   $1 - tool name (string)
	local tool
	tool="$1"
	printf -- '- %s: %s (example query: %s)' "${tool}" "$(tool_description "${tool}")" "$(tool_command "${tool}")"
}
