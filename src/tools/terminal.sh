#!/usr/bin/env bash
# shellcheck shell=bash
#
# Operating-system navigation tool that exposes a persistent, command-limited
# shell session for the agent.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/terminal.sh}/tools/terminal.sh"
#
# Environment variables:
#   TOOL_QUERY (string): command to run within the session (defaults to "status").
#   IS_MACOS (bool): enables the macOS-specific `open` command when true.
#   TERMINAL_SESSION_ID (string, optional): reused session identifier for logging.
#   TERMINAL_WORKDIR (string, optional): starting working directory for the session.
#
# Dependencies:
#   - bash 5+
#   - coreutils (ls, pwd, cat, head, tail, stat, wc, du, base64, cp, mv, rm, mkdir, rmdir, touch)
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero only when registration is misused.

# shellcheck source=../lib/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/terminal.sh}/lib/logging.sh"
# shellcheck source=./registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/terminal.sh}/registry.sh"

TERMINAL_ALLOWED_COMMANDS=(
	"status"
	"pwd"
	"ls"
	"cd"
	"cat"
	"head"
	"tail"
	"find"
	"grep"
	"open"
	"mkdir"
	"rmdir"
	"mv"
	"cp"
	"touch"
	"rm"
	"stat"
	"wc"
	"du"
	"base64"
)

TERMINAL_SESSION_ID="${TERMINAL_SESSION_ID:-}" # string session identifier
TERMINAL_WORKDIR="${TERMINAL_WORKDIR:-}"       # string working directory for the persistent session

derive_terminal_query() {
        # Arguments:
        #   $1 - user query (string)
        local user_query lower_query
        user_query="$1"
        lower_query=$(printf '%s' "${user_query}" | tr '[:upper:]' '[:lower:]')

        if [[ "${user_query}" =~ \`([^\`]+)\` ]]; then
                printf '%s\n' "${BASH_REMATCH[1]}"
                return
        fi

        if [[ "${lower_query}" == *"todo"* ]]; then
                printf 'rg -n "TODO" .\n'
                return
        fi

        if [[ "${lower_query}" == *"list files"* || "${lower_query}" == *"show directory"* || "${lower_query}" == *"show folder"* ]]; then
                printf 'ls -la\n'
                return
        fi

        if [[ "${user_query}" =~ (^|[[:space:]])(ls|cd|cat|grep|find|pwd|rg)([[:space:]]|$) ]]; then
                printf '%s\n' "${BASH_REMATCH[2]}"
                return
        fi

        printf 'status\n'
}

terminal_args_from_json() {
        # Parses TOOL_ARGS into a command and argument array.
        # Sets two global variables:
        #   TERMINAL_CMD (string)
        #   TERMINAL_CMD_ARGS (array)
        local args_json
        args_json=${TOOL_ARGS:-"{}"}

        if ! TERMINAL_CMD=$(jq -er '(.command // "")' <<<"${args_json}" 2>/dev/null || true); then
                TERMINAL_CMD=""
        fi

        if ! jq -e '(.args == null) or (.args | type=="array")' <<<"${args_json}" >/dev/null 2>&1; then
                log "ERROR" "terminal args must supply an array for args" "${args_json}" || true
                return 1
        fi

        if [[ -z "${TERMINAL_CMD}" ]]; then
                TERMINAL_CMD="status"
        fi

        mapfile -t TERMINAL_CMD_ARGS < <(jq -r '(.args // []) | map(tostring) | .[]' <<<"${args_json}" 2>/dev/null || true)
        return 0
}

terminal_init_session() {
	if [[ -z "${TERMINAL_SESSION_ID}" ]]; then
		TERMINAL_SESSION_ID="terminal-${EPOCHSECONDS}"
	fi

	if [[ -z "${TERMINAL_WORKDIR}" ]]; then
		TERMINAL_WORKDIR="$(pwd)"
	fi
}

terminal_run_in_workdir() {
	# Arguments:
	#   $1 - command (string)
	#   $@ - remaining args passed to the command (array)
	local command
	command="$1"
	shift
	(
		cd "${TERMINAL_WORKDIR}" &&
			"${command}" "$@"
	)
}

terminal_allowed() {
	# Arguments:
	#   $1 - candidate command (string)
	local candidate allowed
	candidate="$1"
	for allowed in "${TERMINAL_ALLOWED_COMMANDS[@]}"; do
		if [[ "${candidate}" == "${allowed}" ]]; then
			return 0
		fi
	done
	return 1
}

terminal_change_dir() {
	# Arguments:
	#   $@ - path components to join (array)
	local target resolved
	if [[ $# -eq 0 ]]; then
		log "ERROR" "cd requires a target" ""
		return 1
	fi

	target="$*"

	if ! resolved=$(cd "${TERMINAL_WORKDIR}" && cd "${target}" && pwd); then
		log "ERROR" "Unable to change directory" "${target}"
		return 1
	fi

	TERMINAL_WORKDIR="${resolved}"
	printf '%s\n' "${TERMINAL_WORKDIR}"
}

terminal_print_status() {
	printf 'Session: %s\n' "${TERMINAL_SESSION_ID}"
	printf 'Working directory: %s\n' "${TERMINAL_WORKDIR}"
	printf 'Allowed commands: %s\n' "${TERMINAL_ALLOWED_COMMANDS[*]}"
	terminal_run_in_workdir pwd
	terminal_run_in_workdir ls -la
}

tool_terminal() {
        local command args mode shifted_args has_interactive rm_args
        terminal_init_session

        if ! terminal_args_from_json; then
                return 1
        fi
        command="${TERMINAL_CMD}"
        args=("${TERMINAL_CMD_ARGS[@]}")

	if ! terminal_allowed "${command}"; then
		log "WARN" "Unknown terminal command; showing status" "${command}"
		command="status"
	fi

	case "${command}" in
	status)
		terminal_print_status
		;;
	pwd)
		terminal_run_in_workdir pwd
		;;
	ls)
		if [[ ${#args[@]} -eq 0 ]]; then
			terminal_run_in_workdir ls -la
		else
			terminal_run_in_workdir ls "${args[@]}"
		fi
		;;
	cd)
		terminal_change_dir "${args[@]}"
		;;
	cat)
		terminal_run_in_workdir cat "${args[@]}"
		;;
	head)
		terminal_run_in_workdir head "${args[@]}"
		;;
	tail)
		terminal_run_in_workdir tail "${args[@]}"
		;;
	find)
		if [[ ${#args[@]} -eq 0 ]]; then
			terminal_run_in_workdir find .
		else
			terminal_run_in_workdir find "${args[@]}"
		fi
		;;
	grep)
		terminal_run_in_workdir grep "${args[@]}"
		;;
	open)
		if [[ "${IS_MACOS}" != true ]]; then
			log "WARN" "'open' is macOS-only; skipping" "${args[*]:-""}"
			return 0
		fi
		terminal_run_in_workdir open "${args[@]}"
		;;
	mkdir)
		if [[ ${#args[@]} -eq 0 ]]; then
			log "ERROR" "mkdir requires a target directory" ""
			return 1
		fi
		terminal_run_in_workdir mkdir -p "${args[@]}"
		;;
	rmdir)
		if [[ ${#args[@]} -eq 0 ]]; then
			log "ERROR" "rmdir requires a target directory" ""
			return 1
		fi
		terminal_run_in_workdir rmdir "${args[@]}"
		;;
	mv)
		if [[ ${#args[@]} -lt 2 ]]; then
			log "ERROR" "mv requires a source and destination" "${args[*]:-""}"
			return 1
		fi
		terminal_run_in_workdir mv "${args[@]}"
		;;
	cp)
		if [[ ${#args[@]} -lt 2 ]]; then
			log "ERROR" "cp requires a source and destination" "${args[*]:-""}"
			return 1
		fi
		terminal_run_in_workdir cp "${args[@]}"
		;;
	touch)
		if [[ ${#args[@]} -eq 0 ]]; then
			log "ERROR" "touch requires at least one target" ""
			return 1
		fi
		terminal_run_in_workdir touch "${args[@]}"
		;;
	rm)
		if [[ ${#args[@]} -eq 0 ]]; then
			log "ERROR" "rm requires a target" ""
			return 1
		fi
		has_interactive=false
		for arg in "${args[@]}"; do
			if [[ "${arg}" == -*i* || "${arg}" == "--interactive"* ]]; then
				has_interactive=true
				break
			fi
		done
		rm_args=()
		if [[ "${has_interactive}" != true ]]; then
			rm_args+=("-i")
		fi
		rm_args+=("${args[@]}")
		terminal_run_in_workdir rm "${rm_args[@]}"
		;;
	stat)
		if [[ ${#args[@]} -eq 0 ]]; then
			log "ERROR" "stat requires a target" ""
			return 1
		fi
		terminal_run_in_workdir stat "${args[@]}"
		;;
	wc)
		if [[ ${#args[@]} -eq 0 ]]; then
			log "ERROR" "wc requires at least one target" ""
			return 1
		fi
		terminal_run_in_workdir wc "${args[@]}"
		;;
	du)
		if [[ ${#args[@]} -eq 0 ]]; then
			terminal_run_in_workdir du -sh .
		else
			terminal_run_in_workdir du "${args[@]}"
		fi
		;;
	base64)
		if [[ ${#args[@]} -lt 2 ]]; then
			log "ERROR" "base64 requires a mode (encode|decode) and a target" "${args[*]:-""}"
			return 1
		fi
		mode="${args[0]}"
		shifted_args=("${args[@]:1}")
		case "${mode}" in
		encode)
			terminal_run_in_workdir base64 "${shifted_args[@]}"
			;;
		decode)
			terminal_run_in_workdir base64 -d "${shifted_args[@]}"
			;;
		*)
			log "ERROR" "base64 mode must be encode or decode" "${mode}"
			return 1
			;;
		esac
		;;
	*)
		log "ERROR" "Unsupported terminal command after validation" "${command}"
		return 1
		;;
	esac
}

register_terminal() {
	local args_schema

	args_schema=$(
		cat <<'JSON'
{"type":"object","required":["command"],"properties":{"command":{"type":"string","minLength":1}},"additionalProperties":false}
JSON
	)
	register_tool \
		"terminal" \
		"Persistent terminal session for navigation, inspection, and safe mutations (pwd, ls, du, cd, cat, head, tail, find, grep, stat, wc, base64 encode/decode, mkdir, rmdir, mv, cp, touch, rm -i default; open on macOS)." \
		"terminal <status|pwd|ls|cd|cat|head|tail|find|grep|open|mkdir|rmdir|mv|cp|touch|rm|stat|wc|du|base64>" \
		"Restricted command set with a per-query working directory; destructive operations default to interactive rm." \
		tool_terminal \
		"${args_schema}"
}
