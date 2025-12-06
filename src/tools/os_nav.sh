#!/usr/bin/env bash
# shellcheck shell=bash
#
# Operating-system navigation tool that exposes a persistent, command-limited
# shell session for the agent.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/os_nav.sh}/tools/os_nav.sh"
#
# Environment variables:
#   TOOL_QUERY (string): command to run within the session (defaults to "status").
#   IS_MACOS (bool): enables the macOS-specific `open` command when true.
#   OS_NAV_SESSION_ID (string, optional): reused session identifier for logging.
#   OS_NAV_WORKDIR (string, optional): starting working directory for the session.
#
# Dependencies:
#   - bash 5+
#   - coreutils (ls, pwd, cat, head, tail)
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero only when registration is misused.

# shellcheck source=../logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/os_nav.sh}/logging.sh"
# shellcheck source=./registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/os_nav.sh}/registry.sh"

OS_NAV_ALLOWED_COMMANDS=(
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
)

OS_NAV_SESSION_ID="${OS_NAV_SESSION_ID:-}" # string session identifier
OS_NAV_WORKDIR="${OS_NAV_WORKDIR:-}"       # string working directory for the persistent session

os_nav_init_session() {
	if [[ -z "${OS_NAV_SESSION_ID}" ]]; then
		OS_NAV_SESSION_ID="os-nav-${EPOCHSECONDS}"
	fi

	if [[ -z "${OS_NAV_WORKDIR}" ]]; then
		OS_NAV_WORKDIR="$(pwd)"
	fi
}

os_nav_run_in_workdir() {
	# Arguments:
	#   $1 - command (string)
	#   $@ - remaining args passed to the command (array)
	local command
	command="$1"
	shift
	(
		cd "${OS_NAV_WORKDIR}" &&
			"${command}" "$@"
	)
}

os_nav_allowed() {
	# Arguments:
	#   $1 - candidate command (string)
	local candidate allowed
	candidate="$1"
	for allowed in "${OS_NAV_ALLOWED_COMMANDS[@]}"; do
		if [[ "${candidate}" == "${allowed}" ]]; then
			return 0
		fi
	done
	return 1
}

os_nav_change_dir() {
	# Arguments:
	#   $@ - path components to join (array)
	local target resolved
	if [[ $# -eq 0 ]]; then
		log "ERROR" "cd requires a target" ""
		return 1
	fi

	target="$*"

	if ! resolved=$(cd "${OS_NAV_WORKDIR}" && cd "${target}" && pwd); then
		log "ERROR" "Unable to change directory" "${target}"
		return 1
	fi

	OS_NAV_WORKDIR="${resolved}"
	printf '%s\n' "${OS_NAV_WORKDIR}"
}

os_nav_print_status() {
	printf 'Session: %s\n' "${OS_NAV_SESSION_ID}"
	printf 'Working directory: %s\n' "${OS_NAV_WORKDIR}"
	printf 'Allowed commands: %s\n' "${OS_NAV_ALLOWED_COMMANDS[*]}"
	os_nav_run_in_workdir pwd
	os_nav_run_in_workdir ls -la
}

tool_os_nav() {
	local query raw_args command args
	os_nav_init_session

	query=${TOOL_QUERY:-""}
	read -r -a raw_args <<<"${query}"
	command=${raw_args[0]:-status}
	args=()
	if [[ ${#raw_args[@]} -gt 1 ]]; then
		args=("${raw_args[@]:1}")
	fi

	if ! os_nav_allowed "${command}"; then
		log "WARN" "Unknown os_nav command; showing status" "${command}"
		command="status"
	fi

	case "${command}" in
	status)
		os_nav_print_status
		;;
	pwd)
		os_nav_run_in_workdir pwd
		;;
	ls)
		if [[ ${#args[@]} -eq 0 ]]; then
			os_nav_run_in_workdir ls -la
		else
			os_nav_run_in_workdir ls "${args[@]}"
		fi
		;;
	cd)
		os_nav_change_dir "${args[@]}"
		;;
	cat)
		os_nav_run_in_workdir cat "${args[@]}"
		;;
	head)
		os_nav_run_in_workdir head "${args[@]}"
		;;
	tail)
		os_nav_run_in_workdir tail "${args[@]}"
		;;
	find)
		if [[ ${#args[@]} -eq 0 ]]; then
			os_nav_run_in_workdir find .
		else
			os_nav_run_in_workdir find "${args[@]}"
		fi
		;;
	grep)
		os_nav_run_in_workdir grep "${args[@]}"
		;;
	open)
		if [[ "${IS_MACOS}" != true ]]; then
			log "WARN" "'open' is macOS-only; skipping" "${args[*]:-""}"
			return 0
		fi
		os_nav_run_in_workdir open "${args[@]}"
		;;
	*)
		log "ERROR" "Unsupported os_nav command after validation" "${command}"
		return 1
		;;
	esac
}

register_os_nav() {
	register_tool \
		"os_nav" \
		"Persistent terminal session for navigation and basic commands (pwd, ls, cd, cat, head, tail, find, grep, open)." \
		"os_nav <status|pwd|ls|cd|cat|head|tail|find|grep|open>" \
		"Restricted command set with a per-query working directory." \
		tool_os_nav
}
