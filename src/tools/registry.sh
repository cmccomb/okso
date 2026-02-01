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

update_tool_args_schema() {
	# Arguments:
	#   $1 - tool name
	#   $2 - args schema JSON
	if [[ $# -lt 2 ]]; then
		log "ERROR" "update_tool_args_schema requires tool name and schema" "$*"
		return 1
	fi

	local name schema
	name="$1"
	schema="$2"

	if ! jq -e --arg name "${name}" '.registry[$name] != null' <<<"$(tool_registry_json)" >/dev/null 2>&1; then
		log "ERROR" "Unknown tool for schema update" "${name}" || true
		return 1
	fi

	TOOL_REGISTRY_JSON=$(jq -c \
		--arg name "${name}" \
		--argjson schema "${schema}" \
		'.registry[$name].args_schema = $schema' <<<"$(tool_registry_json)")
}

tool_schema_map() {
	# Returns a mapping of tool names to their argument JSON Schemas.
	# Returns:
	#   JSON object keyed by tool name with args_schema values (string)
	local schemas
	schemas='{}'

	while IFS= read -r tool_name; do
		[[ -z "${tool_name}" ]] && continue
		schemas=$(jq -c --arg name "${tool_name}" --argjson schema "$(tool_args_schema "${tool_name}")" '.[$name] = $schema' <<<"${schemas}")
	done < <(tool_names)

	printf '%s' "${schemas}"
}

init_tool_registry() {
	TOOL_REGISTRY_JSON='{"names":[],"registry":{}}'
}

register_tool() {
	# Arguments:
	#   $1 - name
	#   $2 - description
	#   $3 - handler function name
	#   $4 - optional JSON schema describing args
	if [[ $# -lt 3 ]]; then
		log "ERROR" "register_tool requires three arguments" "$*"
		return 1
	fi

	local name args_schema default_args_schema text_key
	name="$1"
	text_key="$(canonical_text_arg_key)"
	default_args_schema=$(jq -nc --arg key "${text_key}" '{"type":"object","properties":{($key):{"type":"string"}},"additionalProperties":{"type":"string"}}')
	args_schema="${4:-${default_args_schema}}"

	if ! jq -e --arg key "${text_key}" --arg name "${name}" '
                def is_single_string_schema:
                        (.type == "object")
                        and (.properties | type == "object")
                        and ([.properties|keys[]] | length == 1)
                        and ((.properties|values[]|.type) as $types | ($types == "string"));

                if is_single_string_schema then
                        (.properties|keys[] | .) as $prop
                        | if $prop == $key then
                                true
                          elif $prop == "url" and (.properties.url.format? == "uri") then
                                true
                          elif ($name | startswith("workflow_")) then
                                true
                          else
                                false
                          end
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
		--arg handler "$3" \
		--argjson args_schema "${args_schema}" \
		'(.names //= [])
                | (.registry //= {})
                | (if (.names | index($name)) == null then .names += [$name] else . end)
                | .registry[$name] = {description:$description, handler:$handler, args_schema:$args_schema}' <<<"$(tool_registry_json)")
}
