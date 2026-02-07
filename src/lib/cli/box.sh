#!/usr/bin/env bash
# shellcheck shell=bash
#
# Box-rendering helpers for terminal output.
#
# Usage:
#   source "${BASH_SOURCE[0]%/box.sh}/box.sh"

render_box() {
	# Renders content inside a box drawn with box-drawing characters.
	# Arguments:
	#   $1 - content to wrap inside the box (string)
	# Returns:
	#   Boxed content rendered to stdout
	local width_limit wrapped_lines
	width_limit="$(output_box_width_limit)"
	wrapped_lines="$(output_wrap_lines "${width_limit}" "$1")"
	output_render_box_lines "${wrapped_lines}"
}

output_terminal_width() {
	local terminal_width
	terminal_width="${COLUMNS:-"$(tput cols 2>/dev/null || printf '80')"}"
	if ! [[ "${terminal_width}" =~ ^[0-9]+$ ]]; then
		terminal_width=80
	fi
	printf '%s' "${terminal_width}"
}

output_box_width_limit() {
	local terminal_width width_limit
	terminal_width="$(output_terminal_width)"
	width_limit=$((terminal_width - 4))
	if ((width_limit < 20)); then
		width_limit=20
	fi
	printf '%s' "${width_limit}"
}

output_wrap_lines() {
	# Wraps text into newline-delimited lines constrained by width.
	# Arguments:
	#   $1 - width limit
	#   $2 - text content
	local width_limit text
	width_limit="$1"
	text="$2"

	printf '%s\n' "${text}" | fold -s -w "${width_limit}"
}

output_render_box_lines() {
	# Renders a box around provided newline-delimited lines.
	# Arguments:
	#   $1 - newline-delimited lines
	local lines_text line max_line_length padding top_border bottom_border
	local -a lines=()
	lines_text="$1"

	while IFS= read -r line || [[ -n "${line}" ]]; do
		lines+=("${line}")
	done <<<"${lines_text}"

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
