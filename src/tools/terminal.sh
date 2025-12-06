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
#   - coreutils (ls, pwd, cat, head, tail)
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero only when registration is misused.

# shellcheck source=../logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/terminal.sh}/logging.sh"
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
)

TERMINAL_SESSION_ID="${TERMINAL_SESSION_ID:-}" # string session identifier
TERMINAL_WORKDIR="${TERMINAL_WORKDIR:-}"       # string working directory for the persistent session

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
        local query raw_args command args
        terminal_init_session

        query=${TOOL_QUERY:-""}
        read -r -a raw_args <<<"${query}"
        command=${raw_args[0]:-status}
        args=()
        if [[ ${#raw_args[@]} -gt 1 ]]; then
                args=("${raw_args[@]:1}")
        fi

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
        *)
                log "ERROR" "Unsupported terminal command after validation" "${command}"
                return 1
                ;;
        esac
}

register_terminal() {
        register_tool \
                "terminal" \
                "Persistent terminal session for navigation and basic commands (pwd, ls, cd, cat, head, tail, find, grep, open)." \
                "terminal <status|pwd|ls|cd|cat|head|tail|find|grep|open>" \
                "Restricted command set with a per-query working directory." \
                tool_terminal
}
