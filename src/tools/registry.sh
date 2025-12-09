#!/usr/bin/env bash
# shellcheck shell=bash
#
# Tool registry utilities shared across individual tool modules.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/registry.sh}/tools/registry.sh"
#
# Environment variables:
#   None
#
# Dependencies:
#   - bash 3+
#   - jq
#   - logging helpers from logging.sh
#
# Exit codes:
#   Functions emit errors via log and return non-zero when misused.

# shellcheck source=../logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/registry.sh}/logging.sh"

if [[ -z "${TOOL_REGISTRY_JSON:-}" ]]; then
        TOOL_REGISTRY_JSON='{"names":[],"registry":{}}'
fi

tool_registry_json() {
        local default_json
        default_json='{"names":[],"registry":{}}'
        printf '%s' "${TOOL_REGISTRY_JSON:-${default_json}}"
}

tool_names() {
        jq -r '.names[]?' <<<"$(tool_registry_json)"
}

tool_description() {
        local name
        name="$1"
        jq -r --arg name "${name}" '.registry[$name].description // ""' <<<"$(tool_registry_json)"
}

tool_command() {
        local name
        name="$1"
        jq -r --arg name "${name}" '.registry[$name].command // ""' <<<"$(tool_registry_json)"
}

tool_safety() {
        local name
        name="$1"
        jq -r --arg name "${name}" '.registry[$name].safety // ""' <<<"$(tool_registry_json)"
}

tool_handler() {
        local name
        name="$1"
        jq -r --arg name "${name}" '.registry[$name].handler // ""' <<<"$(tool_registry_json)"
}

init_tool_registry() {
        TOOL_REGISTRY_JSON='{"names":[],"registry":{}}'
}

register_tool() {
        # Arguments:
        #   $1 - name
        #   $2 - description
        #   $3 - invocation command (string)
        #   $4 - safety notes
        #   $5 - handler function name
        if [[ $# -lt 5 ]]; then
                log "ERROR" "register_tool requires five arguments" "$*"
                return 1
        fi

        local name
        name="$1"

        if [[ ! "${name}" =~ ^[a-z0-9_]+$ ]]; then
                log "ERROR" "tool names must be alphanumeric with underscores" "${name}" || true
                return 1
        fi

        if [[ -n "${TOOL_NAME_ALLOWLIST[*]:-}" ]]; then
                local allowed
                allowed=false
                for allowed in "${TOOL_NAME_ALLOWLIST[@]}"; do
                        if [[ "${name}" == "${allowed}" ]]; then
                                allowed=true
                                break
                        fi
                done

                if [[ "${allowed}" != true ]]; then
                                log "ERROR" "tool name not in allowlist" "${name}" || true
                                return 1
                fi
        fi

        TOOL_REGISTRY_JSON=$(jq -c \
                --arg name "${name}" \
                --arg description "$2" \
                --arg command "$3" \
                --arg safety "$4" \
                --arg handler "$5" \
                '(.names //= [])
                | (.registry //= {})
                | (if (.names | index($name)) == null then .names += [$name] else . end)
                | .registry[$name] = {description:$description, command:$command, safety:$safety, handler:$handler}' <<<"$(tool_registry_json)")
}
