#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared Apple application helpers for osascript-backed tools.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/apple_app.sh}/tools/apple_app.sh"
#
# Dependencies:
#   - bash 3.2+
#   - osascript helpers from osascript_helpers.sh
#
# Exit codes:
#   Functions return non-zero on invalid arguments.

# shellcheck source=src/tools/osascript_helpers.sh
source "${BASH_SOURCE[0]%/tools/apple_app.sh}/tools/osascript_helpers.sh"

apple_script_escape_string() {
	# Escapes double quotes for safe inclusion in AppleScript string literals.
	# Arguments:
	#   $1 - raw string
	local value
	value="$1"
	printf '%s' "${value//\"/\\\"}"
}

apple_app_run_script() {
	# Runs AppleScript from stdin through a selected osascript binary.
	# Arguments:
	#   $1 - osascript binary path (defaults to osascript)
	#   $@ - arguments forwarded to osascript
	local bin
	bin="${1:-osascript}"
	shift || true
	osascript_run_piped "${bin}" "$@"
}

apple_script_resolve_in_default_account() {
	# Emits AppleScript to resolve an item under default account.
	# Arguments:
	#   $1 - item kind (e.g., folder, list)
	#   $2 - item name
	#   $3 - target variable name in AppleScript
	#   $4 - label for not-found error message
	local item_kind item_name target_var label escaped_name
	item_kind="$1"
	item_name="$2"
	target_var="$3"
	label="$4"
	escaped_name="$(apple_script_escape_string "${item_name}")"

	printf '        set targetAccount to default account\n'
	printf '        if not (exists %s "%s" of targetAccount) then\n' "${item_kind}" "${escaped_name}"
	printf '                error "%s not found: %s"\n' "${label}" "${escaped_name}"
	printf '        end if\n'
	printf '        set %s to %s "%s" of targetAccount\n' "${target_var}" "${item_kind}" "${escaped_name}"
}

apple_script_resolve_top_level() {
	# Emits AppleScript to resolve a top-level item.
	# Arguments:
	#   $1 - item kind (e.g., calendar)
	#   $2 - item name
	#   $3 - target variable name in AppleScript
	#   $4 - label for not-found error message
	local item_kind item_name target_var label escaped_name
	item_kind="$1"
	item_name="$2"
	target_var="$3"
	label="$4"
	escaped_name="$(apple_script_escape_string "${item_name}")"

	printf '        if not (exists %s "%s") then\n' "${item_kind}" "${escaped_name}"
	printf '                error "%s not found: %s"\n' "${label}" "${escaped_name}"
	printf '        end if\n'
	printf '        set %s to %s "%s"\n' "${target_var}" "${item_kind}" "${escaped_name}"
}

export -f apple_script_escape_string
export -f apple_app_run_script
export -f apple_script_resolve_in_default_account
export -f apple_script_resolve_top_level
