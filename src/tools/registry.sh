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
#   - bash 3.2+
#   - jq
#   - logging helpers from logging.sh
#
# Exit codes:
#   Functions emit errors via log and return non-zero when misused.

# shellcheck source=src/lib/core/logging.sh
source "${BASH_SOURCE[0]%/tools/registry.sh}/lib/core/logging.sh"

: "${CANONICAL_TEXT_ARG_KEY:=input}"

canonical_text_arg_key() {
	printf '%s' "${CANONICAL_TEXT_ARG_KEY}"
}

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

tool_args_schema() {
	local name
	name="$1"
	jq -c --arg name "${name}" '.registry[$name].args_schema // {}' <<<"$(tool_registry_json)"
}

init_tool_registry() {
	TOOL_REGISTRY_JSON='{"names":[],"registry":{}}'
}

register_tool() {
	# Arguments:
	#   $1 - name
	#   $2 - description
	#   $3 - safety notes
	#   $4 - handler function name
	#   $5 - optional JSON schema describing args
	if [[ $# -lt 4 ]]; then
		log "ERROR" "register_tool requires four arguments" "$*"
		return 1
	fi

	local name args_schema default_args_schema text_key
	name="$1"
	text_key="$(canonical_text_arg_key)"
	default_args_schema=$(jq -nc --arg key "${text_key}" '{"type":"object","properties":{($key):{"type":"string"}},"additionalProperties":{"type":"string"}}')
	args_schema="${5:-${default_args_schema}}"

	if ! jq -e --arg key "${text_key}" '
                def is_single_string_schema:
                        (.type == "object")
                        and (.properties | type == "object")
                        and ([.properties|keys[]] | length == 1)
                        and ((.properties|values[]|.type) as $types | ($types == "string"));

                if is_single_string_schema then
                        (.properties|keys[] | .) as $prop
                        | ($prop == $key)
                else
                        true
                end
        ' <<<"${args_schema}" >/dev/null 2>&1; then
		log "ERROR" "Single-string schemas must use ${text_key}" "${args_schema}" || true
		return 1
	fi

	if [[ ! "${name}" =~ ^[a-z0-9_]+$ ]]; then
		log "ERROR" "tool names must be alphanumeric with underscores" "${name}" || true
		return 1
	fi

	TOOL_REGISTRY_JSON=$(jq -c \
		--arg name "${name}" \
		--arg description "$2" \
		--arg safety "$3" \
		--arg handler "$4" \
		--argjson args_schema "${args_schema}" \
		'(.names //= [])
                | (.registry //= {})
                | (if (.names | index($name)) == null then .names += [$name] else . end)
                | .registry[$name] = {description:$description, safety:$safety, handler:$handler, args_schema:$args_schema}' <<<"$(tool_registry_json)")
}
