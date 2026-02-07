#!/usr/bin/env bash
# shellcheck shell=bash
#
# Streaming UI renderer helpers for okso CLI.
#
# Usage:
#   source "${BASH_SOURCE[0]%/render.sh}/render.sh"
#
# Environment variables:
#   OKSO_PROGRESS (0|1): emit one-line progress events.
#   OKSO_TRACE (0|1): emit expanded trace blocks.
#   OKSO_TRACE_VERBOSE (0|1): include schema-heavy trace details.
#   OKSO_UI_WIDTH (int): target line width for one-line output (default 110).
#   OKSO_UI_RUN_STARTED_AT (epoch seconds): run start time for elapsed clock.
#
# Exit codes:
#   Functions return 0 on success.

UI_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

ui_width_target() {
	local width
	width="${OKSO_UI_WIDTH:-110}"
	if ! [[ "${width}" =~ ^[0-9]+$ ]]; then
		width=110
	fi
	# Clamp width so one-line progress remains legible on small terminals and
	# avoids over-expanding in wider desktop panes.
	if ((width < 80)); then
		width=80
	fi
	if ((width > 140)); then
		width=140
	fi
	printf '%s' "${width}"
}

ui_trim_spaces() {
	local text
	text="$1"
	# Collapse newlines/tabs/spaces to single spaces.
	text="$(printf '%s' "${text}" | tr '\n\r\t' '   ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
	printf '%s' "${text}"
}

ui_truncate_line() {
	local text limit
	text="$(ui_trim_spaces "$1")"
	limit="$(ui_width_target)"
	if ((${#text} > limit)); then
		# Reserve three characters for the ellipsis suffix.
		printf '%s...' "${text:0:$((limit - 3))}"
		return 0
	fi
	printf '%s' "${text}"
}

ui_progress_enabled() {
	if [[ "${OKSO_TRACE:-0}" == "1" || "${OKSO_PROGRESS:-0}" == "1" ]]; then
		return 0
	fi
	return 1
}

ui_trace_enabled() {
	[[ "${OKSO_TRACE:-0}" == "1" ]]
}

ui_trace_verbose_enabled() {
	[[ "${OKSO_TRACE_VERBOSE:-0}" == "1" ]]
}

ui_format_elapsed() {
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

ui_elapsed_since_start() {
	local start now elapsed
	start="${OKSO_UI_RUN_STARTED_AT:-$(date +%s)}"
	now="$(date +%s)"
	if ! [[ "${start}" =~ ^[0-9]+$ ]]; then
		start="${now}"
	fi
	elapsed=$((now - start))
	if ((elapsed < 0)); then
		elapsed=0
	fi
	ui_format_elapsed "${elapsed}"
}

ui_domain_for_url() {
	local url stripped host
	url="$1"
	stripped="${url#http://}"
	stripped="${stripped#https://}"
	host="${stripped%%/*}"
	if [[ -z "${host}" ]]; then
		host="${url}"
	fi
	printf '%s' "${host}"
}

ui_shorten_url() {
	local url stripped host path path_stub
	url="$1"
	if [[ -z "${url}" ]]; then
		printf '%s' ""
		return 0
	fi
	stripped="${url#http://}"
	stripped="${stripped#https://}"
	host="${stripped%%/*}"
	if [[ "${stripped}" == */* ]]; then
		path="/${stripped#*/}"
	else
		path="/"
	fi
	path="${path%%\?*}"
	path="${path%%\#*}"
	if ((${#path} > 30)); then
		path_stub="${path:0:27}..."
	else
		path_stub="${path}"
	fi
	printf '%s%s' "${host}" "${path_stub}"
}

ui_display_url() {
	local url
	url="$1"
	if ui_trace_enabled; then
		# Trace mode prioritizes full-fidelity diagnostics.
		printf '%s' "${url}"
	else
		# Normal progress mode favors compact URLs for line budget.
		ui_shorten_url "${url}"
	fi
}

ui_status() {
	local query phase elapsed line
	query="$1"
	phase="$2"
	elapsed="$3"
	if ! ui_progress_enabled; then
		return 0
	fi
	query="$(ui_truncate_line "${query}")"
	# Keep field names stable for downstream parsers and tests.
	line="okso ▸ query: \"${query}\"  phase=${phase}  t=${elapsed}"
	printf '%s\n' "$(ui_truncate_line "${line}")" >&2
}

ui_event() {
	local level message line
	level="$1"
	message="$2"
	if ! ui_progress_enabled; then
		return 0
	fi
	line="• ${level}: ${message}"
	printf '%s\n' "$(ui_truncate_line "${line}")" >&2
}

ui_hit() {
	local rank site title url_display line
	rank="$1"
	site="$2"
	title="$3"
	url_display="$4"
	if ! ui_progress_enabled; then
		return 0
	fi
	line="• search: hit  [${rank}] ${site} — ${title}"
	if [[ -n "${url_display}" ]]; then
		line+=" (${url_display})"
	fi
	printf '%s\n' "$(ui_truncate_line "${line}")" >&2
}

ui_trace_block() {
	local title content
	title="$1"
	content="$2"
	if ! ui_trace_enabled; then
		return 0
	fi
	printf '%s\n' "trace: $(ui_trim_spaces "${title}")" >&2
	if [[ -n "${content}" ]]; then
		printf '%s\n' "${content}" >&2
	fi
}

ui_final_summary() {
	local deadlines_block sources_block
	deadlines_block="$1"
	sources_block="$2"

	printf 'DEADLINES (timeline-first)\n'
	if [[ -n "${deadlines_block}" ]]; then
		printf '%s\n' "${deadlines_block}"
	else
		printf '  • No deadlines identified.\n'
	fi
	printf 'SOURCES (top hits)\n'
	if [[ -n "${sources_block}" ]]; then
		printf '%s\n' "${sources_block}"
	else
		printf '  (no web sources captured)\n'
	fi
}
