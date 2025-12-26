#!/usr/bin/env bash
# shellcheck shell=bash
#
# Schema helpers for executor-style tool calls.
#
# Usage:
#   source "${BASH_SOURCE[0]%/schema.sh}/schema.sh"
#
# Environment variables:
#   CANONICAL_TEXT_ARG_KEY (string): default key for single-string tool args.
#   MISSING_VALUE_TOKEN (string): sentinel used when the model lacks required details; defaults to "__MISSING__".
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on validation or schema construction failures.

REACT_LIB_DIR=${REACT_LIB_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
MISSING_VALUE_TOKEN=${MISSING_VALUE_TOKEN:-"__MISSING__"}

# shellcheck source=../schema/schema.sh disable=SC1091
source "${REACT_LIB_DIR}/../schema/schema.sh"
# shellcheck source=../core/logging.sh disable=SC1091
source "${REACT_LIB_DIR}/../core/logging.sh"
# shellcheck source=../tools.sh disable=SC1091
source "${REACT_LIB_DIR}/../tools.sh"
# shellcheck source=../dependency_guards/dependency_guards.sh disable=SC1091
source "${REACT_LIB_DIR}/../dependency_guards/dependency_guards.sh"

build_react_action_schema() {
	# Constructs a JSON schema for allowed executor tools with optional missing-value sentinels.
	# Arguments:
	#   $1 - newline-delimited allowed tools (optional)
	local allowed_tools registry_json
	allowed_tools="$1"

	if [[ -z "$(tool_names)" ]] && declare -F initialize_tools >/dev/null 2>&1; then
		initialize_tools >/dev/null 2>&1 || true
	fi
	registry_json="$(tool_registry_json)"

	if ! require_python3_available "Executor schema generation"; then
		log "ERROR" "Unable to build executor action schema; python3 missing" "${allowed_tools}" >&2
		return 1
	fi

	python3 - "${allowed_tools}" "${registry_json}" "${CANONICAL_TEXT_ARG_KEY:-input}" "${MISSING_VALUE_TOKEN}" <<'PY'
import json
import os
import sys
import tempfile

allowed_raw = sys.argv[1]
registry = json.loads(sys.argv[2] or "{}")
text_key = sys.argv[3] if len(sys.argv) > 3 else "input"
missing_token = sys.argv[4] if len(sys.argv) > 4 else "__MISSING__"

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

if not allowed:
    sys.stderr.write("No tools available for executor schema\n")
    sys.exit(1)

def _inject_missing_for_required(schema_fragment):
    """Allow missing sentinels only for required properties."""

    if not isinstance(schema_fragment, dict):
        return schema_fragment

    updated = dict(schema_fragment)
    properties = updated.get("properties", {})
    required = updated.get("required", [])

    if isinstance(properties, dict):
        next_properties = {}
        for key, value in properties.items():
            normalized_value = _inject_missing_for_required(value)
            if isinstance(required, list) and key in required:
                next_properties[key] = {
                    "anyOf": [normalized_value, {"const": missing_token}]
                }
            else:
                next_properties[key] = normalized_value
        updated["properties"] = next_properties

    if "items" in updated:
        updated["items"] = _inject_missing_for_required(updated["items"])
    if "additionalProperties" in updated and updated["additionalProperties"] is not False:
        updated["additionalProperties"] = _inject_missing_for_required(
            updated["additionalProperties"]
        )

    return updated

def normalize_args_schema(name):
    info = registry_map.get(name, {}) if isinstance(registry_map, dict) else {}
    schema = info.get("args_schema") if isinstance(info, dict) else None
    has_defined_schema = isinstance(schema, dict)
    if not has_defined_schema:
        schema = fallback_schema

    normalized = {"type": "object"}
    normalized.update(schema)
    if has_defined_schema:
        normalized.setdefault("additionalProperties", False)
    else:
        normalized.setdefault(
            "additionalProperties",
            {"type": "string"},
        )

    return _inject_missing_for_required(normalized)

variants = []

for name in allowed:
    args_schema = normalize_args_schema(name)
    variants.append(
        {
            "type": "object",
            "additionalProperties": False,
            "required": ["action"],
            "properties": {
                "action": {
                    "type": "object",
                    "additionalProperties": False,
                        "required": ["tool", "args"],
                        "properties": {
                        "tool": {"anyOf": [{"const": name}, {"const": missing_token}]},
                        "args": {"anyOf": [args_schema, {"const": missing_token}]},
                    },
                }
            },
        }
    )

variants.append(
    {
        "type": "object",
        "additionalProperties": False,
        "required": ["action"],
        "properties": {"action": {"const": missing_token}},
        "description": "Fallback when no tool can be selected.",
    }
)

schema_doc = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "title": "ExecutorAction",
    "description": "Executor tool call constrained to the provided allowed tools. Missing fields may be explicitly marked with the configured sentinel.",
    "oneOf": variants,
}

with tempfile.NamedTemporaryFile(
    mode="w", delete=False, suffix=".schema.json", encoding="utf-8"
) as tmp_file:
    json.dump(schema_doc, tmp_file)
    tmp_file.flush()
    print(tmp_file.name)
PY
}

validate_react_action() {
	# Validates a llama-produced action against the generated schema.
	# Arguments:
	#   $1 - raw action JSON string
	#   $2 - schema path
	local raw_action schema_path action_json schema_json allowed_tools tool tool_schema properties_json additional_properties
	local required_args err_log missing_token args_json
	raw_action="$1"
	schema_path="$2"
	missing_token="${MISSING_VALUE_TOKEN}"

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

	if ! jq -e 'keys_unsorted == ["action"]' <<<"${action_json}" >/dev/null 2>&1; then
		printf 'Unexpected or missing top-level fields\n' >&2
		return 1
	fi

	if jq -e --arg missing "${missing_token}" '.action == $missing' <<<"${action_json}" >/dev/null 2>&1; then
		jq -c --arg missing "${missing_token}" '{action:$missing}' <<<"${action_json}"
		return 0
	fi

	if ! jq -e '.action | type == "object"' <<<"${action_json}" >/dev/null; then
		printf 'action must be an object or missing sentinel\n' >&2
		return 1
	fi

	local unexpected_action_field
	unexpected_action_field=$(jq -er '(.action | keys_unsorted) - ["tool","args"] | first? // empty' <<<"${action_json}" 2>/dev/null || true)
	if [[ -n "${unexpected_action_field}" ]]; then
		printf 'Unexpected field on action: %s\n' "${unexpected_action_field}" >&2
		return 1
	fi

	for key in tool args; do
		if ! jq -e --arg key "${key}" '.action | has($key)' <<<"${action_json}" >/dev/null; then
			printf 'Missing field: %s\n' "${key}" >&2
			return 1
		fi
	done

	tool="$(jq -r '.action.tool' <<<"${action_json}" 2>/dev/null || printf '')"
	args_json="$(jq -c '.action.args' <<<"${action_json}" 2>/dev/null || printf '{}')"

	allowed_tools=$(jq -cr --arg missing "${missing_token}" '[.oneOf[]?.properties.action.properties.tool.anyOf[]?.const // empty] | map(select(. != $missing))' <<<"${schema_json}" 2>/dev/null || printf '[]')

	if [[ "${tool}" != "${missing_token}" ]]; then
		if ! jq -e --arg tool "${tool}" --argjson allowed "${allowed_tools}" '$allowed | index($tool)' <<<"null" >/dev/null; then
			printf 'Unsupported tool: %s\n' "${tool}" >&2
			return 1
		fi
	fi

	if [[ "${args_json}" == "\"${missing_token}\"" ]]; then
		printf '%s' "${action_json}"
		return 0
	fi

	if ! jq -e '.action.args | type == "object"' <<<"${action_json}" >/dev/null; then
		printf 'args must be an object or missing sentinel\n' >&2
		return 1
	fi

	tool_schema=$(jq -c --arg tool "${tool}" '
                [.oneOf[]? | select(.properties.action.properties.tool.const == $tool or (.properties.action.properties.tool.anyOf[]?.const == $tool)) | .properties.action.properties.args] | first // null
        ' <<<"${schema_json}")
	if [[ -z "${tool_schema}" || "${tool_schema}" == "null" ]]; then
		printf 'No schema for tool: %s\n' "${tool}" >&2
		return 1
	fi

	local effective_schema
	effective_schema=$(jq -c '
                if (.anyOf | type == "array") then
                        (.anyOf | map(select(type == "object" and (.properties | type == "object"))) | first)
                else
                        .
                end
        ' <<<"${tool_schema}")

	properties_json=$(jq -c 'if (.properties | type == "object") then .properties else {} end' <<<"${effective_schema}")
	required_args=$(jq -c '.required // []' <<<"${effective_schema}")
	additional_properties=$(jq -c 'if .additionalProperties == null then false else .additionalProperties end' <<<"${effective_schema}")

	_react_enforce_arg_type() {
		# Validates an argument value against a schema fragment using jq types.
		# Arguments:
		#   $1 - argument value
		#   $2 - schema fragment JSON
		local value schema type field format
		value="$1"
		schema="$2"

		if [[ "${value}" == "\"${missing_token}\"" ]]; then
			return 0
		fi

		if jq -e '.anyOf? | type == "array"' <<<"${schema}" >/dev/null 2>&1; then
			while IFS= read -r variant; do
				if _react_enforce_arg_type "${value}" "${variant}"; then
					return 0
				fi
			done < <(jq -c '.anyOf[]' <<<"${schema}")
			return 1
		fi

		local const_value
		const_value="$(jq -r '.const // empty' <<<"${schema}" 2>/dev/null || true)"
		if [[ -n "${const_value}" ]]; then
			if [[ "${value}" == "${const_value}" || "${value}" == "\"${const_value}\"" ]]; then
				return 0
			fi
			return 1
		fi

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
			jq -e 'type == "number"' <<<"${value}" >/dev/null || return 1
			;;
		integer)
			jq -e 'type == "number" and (. == (.|floor))' <<<"${value}" >/dev/null || return 1
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
		local arg_schema arg_value has_arg is_required
		arg_schema=$(jq -c --arg key "${arg_key}" '.[$key]' <<<"${properties_json}")
		if jq -e --arg key "${arg_key}" '.action.args | has($key)' <<<"${action_json}" >/dev/null; then
			has_arg=true
		else
			has_arg=false
		fi

		if jq -e --arg key "${arg_key}" --argjson required "${required_args}" '$required | index($key)' <<<"null" >/dev/null; then
			is_required=true
		else
			is_required=false
		fi

		if [[ "${has_arg}" == false ]]; then
			if [[ "${is_required}" == true ]]; then
				printf 'Missing arg: %s\n' "${arg_key}" >&2
				return 1
			fi
			continue
		fi

		arg_value=$(jq -c --arg key "${arg_key}" '.action.args[$key]' <<<"${action_json}")
		if [[ "${arg_value}" == "null" && "${is_required}" == false ]]; then
			continue
		fi

		if ! _react_enforce_arg_type "${arg_value}" "${arg_schema}"; then
			local expected_type enum_values
			expected_type="$(jq -r '.type // empty' <<<"${arg_schema}" 2>/dev/null || true)"
			enum_values="$(jq -cr '.enum // empty' <<<"${arg_schema}" 2>/dev/null || true)"
			if [[ -n "${enum_values}" && "${enum_values}" != "null" ]]; then
				printf 'Arg %s must be one of: %s\n' "${arg_key}" "$(jq -r '.enum | join(", ")' <<<"${arg_schema}" 2>/dev/null || printf '')" >&2
			elif [[ -n "${expected_type}" ]]; then
				printf 'Arg %s must be a %s\n' "${arg_key}" "${expected_type}" >&2
			else
				printf 'Invalid type for arg: %s\n' "${arg_key}" >&2
			fi
			return 1
		fi

		if jq -e '(.enum // null) != null' <<<"${arg_schema}" >/dev/null 2>&1; then
			if ! jq -e --argjson value "${arg_value}" --argjson enums "$(jq -c '.enum' <<<"${arg_schema}" 2>/dev/null || printf '[]')" '$enums | index($value)' <<<"null" >/dev/null; then
				printf 'Arg %s must be one of: %s\n' "${arg_key}" "$(jq -r '.enum | join(", ")' <<<"${arg_schema}" 2>/dev/null || printf '')" >&2
				return 1
			fi
		fi
	done

	if [[ "${additional_properties}" == "false" ]]; then
		local unknown_arg
		unknown_arg=$(jq -er --argjson known "${properties_json}" '(.action.args | keys_unsorted) - ([$known | keys_unsorted] | add) | first? // empty' <<<"${action_json}" 2>/dev/null || true)
		if [[ -n "${unknown_arg}" ]]; then
			printf 'Unexpected arg: %s\n' "${unknown_arg}" >&2
			return 1
		fi
	fi

	printf '%s' "${action_json}"
	return 0
}
