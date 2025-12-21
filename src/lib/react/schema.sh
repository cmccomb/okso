#!/usr/bin/env bash
# shellcheck shell=bash
#
# Schema helpers for the ReAct execution loop.
#
# Usage:
#   source "${BASH_SOURCE[0]%/schema.sh}/schema.sh"
#
# Environment variables:
#   CANONICAL_TEXT_ARG_KEY (string): default key for single-string tool args.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on validation or schema construction failures.

REACT_LIB_DIR=${REACT_LIB_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)}

# shellcheck source=../schema/schema.sh disable=SC1091
source "${REACT_LIB_DIR}/../schema/schema.sh"
# shellcheck source=../core/logging.sh disable=SC1091
source "${REACT_LIB_DIR}/../core/logging.sh"
# shellcheck source=../tools.sh disable=SC1091
source "${REACT_LIB_DIR}/../tools.sh"

build_react_action_schema() {
	# Constructs a JSON schema for allowed ReAct tools.
	# Arguments:
	#   $1 - newline-delimited allowed tools (optional)
	local allowed_tools registry_json
	allowed_tools="$1"

	if [[ -z "$(tool_names)" ]] && declare -F initialize_tools >/dev/null 2>&1; then
		initialize_tools >/dev/null 2>&1 || true
	fi
	registry_json="$(tool_registry_json)"

	python3 - "${allowed_tools}" "${registry_json}" "${CANONICAL_TEXT_ARG_KEY:-input}" <<'PY'
import json
import sys
import tempfile

allowed_raw = sys.argv[1]
registry = json.loads(sys.argv[2] or "{}")
text_key = sys.argv[3] if len(sys.argv) > 3 else "input"

fallback_schema = {
    "type": "object",
    "properties": {text_key: {"type": "string"}},
    "additionalProperties": {"type": "string"},
}

all_names = registry.get("names", [])
registry_map = registry.get("registry", {})

if allowed_raw.strip():
    allowed = [line.strip() for line in allowed_raw.splitlines() if line.strip()]
else:
    allowed = all_names

args_by_tool = {}
tool_enum = []

for name in allowed:
    info = registry_map.get(name, {})
    schema = info.get("args_schema") if isinstance(info, dict) else None
    has_defined_schema = isinstance(schema, dict)
    if not has_defined_schema:
        schema = fallback_schema

    normalized = {"type": "object"}
    normalized.update(schema)
    if has_defined_schema:
        normalized.setdefault("additionalProperties", False)
    else:
        normalized.setdefault("additionalProperties", {"type": "string"})

    args_by_tool[name] = normalized
    tool_enum.append(name)

if not tool_enum:
    sys.stderr.write("No tools available for react schema\n")
    sys.exit(1)

schema_doc = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "title": "ReactAction",
    "description": "ReAct tool call constrained to the provided allowed tools.",
    "type": "object",
    "additionalProperties": False,
    "required": ["thought", "tool", "args"],
    "properties": {
        "thought": {"type": "string", "minLength": 1},
        "tool": {"type": "string", "enum": tool_enum},
        "args": {"type": "object"},
    },
    "$defs": {"args_by_tool": args_by_tool},
    "allOf": [
        {
            "if": {"properties": {"tool": {"const": name}}},
            "then": {
                "properties": {"tool": {"const": name}, "args": args_by_tool[name]},
                "required": ["tool", "args"],
            },
        }
        for name in tool_enum
    ],
}

tmp_file = tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".schema.json", encoding="utf-8")
json.dump(schema_doc, tmp_file)
tmp_file.close()
print(tmp_file.name)
PY
}

validate_react_action() {
	# Validates a llama-produced action against the generated schema.
	# Arguments:
	#   $1 - raw action JSON string
	#   $2 - schema path
	local raw_action schema_path action_json schema_json allowed_tools tool tool_schema properties_json additional_properties
	local err_log required_args thought_trimmed
	raw_action="$1"
	schema_path="$2"

	err_log=$(mktemp)

	if ! action_json=$(jq -ce '.' <<<"${raw_action}" 2>"${err_log}"); then
		printf 'Invalid JSON: %s\n' "$(<"${err_log}")" >&2
		rm -f "${err_log}"
		return 1
	fi

	if ! schema_json=$(jq -ce '.' "${schema_path}" 2>"${err_log}"); then
		printf 'Schema load failed: %s\n' "$(<"${err_log}")" >&2
		rm -f "${err_log}"
		return 1
	fi

	rm -f "${err_log}"

	for key in thought tool args; do
		if ! jq -e --arg key "${key}" 'has($key)' <<<"${action_json}" >/dev/null; then
			printf 'Missing field: %s\n' "${key}" >&2
			return 1
		fi
	done

	local unexpected
	unexpected=$(jq -er 'keys_unsorted | map(select(. != "thought" and . != "tool" and . != "args")) | first? // empty' <<<"${action_json}" 2>/dev/null || true)
	if [[ -n "${unexpected}" ]]; then
		printf 'Unexpected field: %s\n' "${unexpected}" >&2
		return 1
	fi

	if ! jq -e '.thought | type == "string" and (gsub("^\\s+|\\s+$"; "") | length > 0)' <<<"${action_json}" >/dev/null; then
		printf 'thought must be a non-empty string\n' >&2
		return 1
	fi

	if ! jq -e '.tool | type == "string"' <<<"${action_json}" >/dev/null; then
		printf 'tool must be a string\n' >&2
		return 1
	fi

	tool=$(jq -r '.tool' <<<"${action_json}")
	allowed_tools=$(jq -cr '.properties.tool.enum // []' <<<"${schema_json}")
	if ! jq -e --arg tool "${tool}" --argjson allowed "${allowed_tools}" '$allowed | index($tool)' <<<"null" >/dev/null; then
		printf 'Unsupported tool: %s\n' "${tool}" >&2
		return 1
	fi

	if ! jq -e '.args | type == "object"' <<<"${action_json}" >/dev/null; then
		printf 'args must be an object\n' >&2
		return 1
	fi

	tool_schema=$(jq -c --arg tool "${tool}" '."$defs".args_by_tool[$tool]' <<<"${schema_json}")
	if [[ -z "${tool_schema}" || "${tool_schema}" == "null" ]]; then
		printf 'No schema for tool: %s\n' "${tool}" >&2
		return 1
	fi

	properties_json=$(jq -c 'if (.properties | type == "object") then .properties else {} end' <<<"${tool_schema}")
	required_args=$(jq -r '(.required // [])[]?' <<<"${tool_schema}")
	additional_properties=$(jq -c 'if .additionalProperties == null then false else .additionalProperties end' <<<"${tool_schema}")

	local required
	for required in ${required_args}; do
		if ! jq -e --arg key "${required}" '.args | has($key)' <<<"${action_json}" >/dev/null; then
			printf 'Missing arg: %s\n' "${required}" >&2
			return 1
		fi
	done

	_react_enforce_arg_type() {
		# Validates an argument value against a schema fragment using jq types.
		# Arguments:
		#   $1 - argument value
		#   $2 - schema fragment JSON
		local value schema type field format
		value="$1"
		schema="$2"
		type="$(jq -r '.type // empty' <<<"${schema}" 2>/dev/null || true)"
		field="$(jq -r '.const // empty' <<<"${schema}" 2>/dev/null || true)"
		format="$(jq -r '.format // empty' <<<"${schema}" 2>/dev/null || true)"
		if [[ -z "${type}" ]]; then
			return 0
		fi

		case "${type}" in
		object)
			jq -e 'type == "object"' <<<"${value}" >/dev/null || return 1
			;;
		array)
			jq -e 'type == "array"' <<<"${value}" >/dev/null || return 1
			;;
		string)
			jq -e 'type == "string"' <<<"${value}" >/dev/null || return 1
			if [[ -n "${field}" ]] && [[ "${value}" != "${field}" ]]; then
				return 1
			fi
			if [[ "${format}" == "date-time" ]]; then
				if ! jq -e 'test("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")' <<<"${value}" >/dev/null; then
					return 1
				fi
			fi
			;;
		number)
			jq -e 'type == "number" or type == "integer"' <<<"${value}" >/dev/null || return 1
			;;
		integer)
			jq -e 'type == "integer"' <<<"${value}" >/dev/null || return 1
			;;
		boolean)
			jq -e 'type == "boolean"' <<<"${value}" >/dev/null || return 1
			;;
		null)
			jq -e 'type == "null"' <<<"${value}" >/dev/null || return 1
			;;
		esac

		return 0
	}

	local arg_key
	for arg_key in $(jq -r 'keys_unsorted[]?' <<<"${properties_json}" 2>/dev/null || true); do
		local arg_schema arg_value
		arg_schema=$(jq -c --arg key "${arg_key}" '.[$key]' <<<"${properties_json}")
		arg_value=$(jq -c --arg key "${arg_key}" '.args[$key]' <<<"${action_json}")
		if ! _react_enforce_arg_type "${arg_value}" "${arg_schema}"; then
			printf 'Invalid type for arg: %s\n' "${arg_key}" >&2
			return 1
		fi
	done

	if [[ "${additional_properties}" == "false" ]]; then
		local unknown_arg
		unknown_arg=$(jq -er --argjson known "${properties_json}" '(.args | keys_unsorted) - ([$known | keys_unsorted] | add) | first? // empty' <<<"${action_json}" 2>/dev/null || true)
		if [[ -n "${unknown_arg}" ]]; then
			printf 'Unexpected arg: %s\n' "${unknown_arg}" >&2
			return 1
		fi
	fi

	if jq -e '.args == {}' <<<"${action_json}" >/dev/null; then
		thought_trimmed="$(jq -r '.thought | gsub("^\\s+|\\s+$"; "")' <<<"${action_json}" 2>/dev/null || true)"
		if [[ -z "${thought_trimmed}" ]]; then
			printf 'Args empty but thought missing.\n' >&2
			return 1
		fi
	fi

	return 0
}
