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
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on validation or schema construction failures.

EXECUTOR_LIB_DIR=${EXECUTOR_LIB_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)}

# shellcheck source=../schema/schema.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../schema/schema.sh"
# shellcheck source=../core/logging.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../core/logging.sh"
# shellcheck source=../tools.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../tools.sh"
# shellcheck source=../dependency_guards/dependency_guards.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../dependency_guards/dependency_guards.sh"

json_pointer_to_path() {
	# Converts a JSON Pointer to a slash-delimited path string.
	# Arguments:
	#   $1 - JSON Pointer (string)
	#   $2 - omit last segment flag (bool; optional)
	local pointer omit_last segments=() part path_parts=()
	pointer=${1:-""}
	omit_last=${2:-false}

	IFS='/' read -r -a segments <<<"${pointer#/}"

	for part in "${segments[@]}"; do
		part=${part//~1//}
		part=${part//~0/~}
		if [[ -n "${part}" ]]; then
			path_parts+=("${part}")
		fi
	done

	if [[ "${omit_last}" == true ]] && ((${#path_parts[@]} > 0)); then
		unset 'path_parts[-1]'
	fi

	if ((${#path_parts[@]} == 0)); then
		printf 'root'
		return
	fi

	printf '%s' "${path_parts[*]}" | tr ' ' '/'
}

json_pointer_to_jq() {
	# Converts a JSON Pointer to a jq field accessor expression.
	# Arguments:
	#   $1 - JSON Pointer (string)
	local pointer segments=() expr part
	pointer=${1:-""}
	expr="."

	IFS='/' read -r -a segments <<<"${pointer#/}"

	for part in "${segments[@]}"; do
		part=${part//~1//}
		part=${part//~0/~}
		if [[ "${part}" =~ ^[0-9]+$ ]]; then
			expr+="[${part}]"
		else
			expr+="[\"${part}\"]"
		fi
	done

	printf '%s' "${expr}"
}

format_jsonschema_error() {
	# Shapes the JSON Schema CLI JSON error output into a concise error message.
	# Arguments:
	#   $1 - validation output JSON (string)
	#   $2 - instance JSON path (string)
	#   $3 - schema JSON path (string)
	local validation_json instance_path schema_path error_json keyword_location instance_location location_path message value expected_type value_expr type_expr extra_key
	validation_json=$1
	instance_path=$2
	schema_path=$3

	error_json=$(jq -c '
                (.errors // [])
                | sort_by(
                        if (.keywordLocation|tostring|contains("additionalProperties")) then 0
                        elif (.keywordLocation|tostring|endswith("/type")) then 1
                        elif (.keywordLocation|tostring|contains("/required")) then 2
                        else 3
                        end,
                        -((.instanceLocation // "" | split("/") | length))
                )
                | .[0] // {}
        ' <<<"${validation_json}" 2>/dev/null)

	if [[ -z "${error_json}" || "${error_json}" == "{}" ]]; then
		printf 'Schema validation failed' >&2
		return 1
	fi

	keyword_location=$(jq -r '.keywordLocation // ""' <<<"${error_json}")
	instance_location=$(jq -r '.instanceLocation // ""' <<<"${error_json}")

	if [[ "${keyword_location}" == */additionalProperties ]]; then
		location_path=$(json_pointer_to_path "${instance_location}" true)
		extra_key=$(json_pointer_to_path "${instance_location}" false)
		extra_key=${extra_key##*/}
		printf '%s: Additional properties are not allowed (' "${location_path}"
		printf "'%s' was unexpected)" "${extra_key}"
		return 0
	fi

	if [[ "${keyword_location}" == */type ]]; then
		location_path=$(json_pointer_to_path "${instance_location}" false)
		value_expr=$(json_pointer_to_jq "${instance_location}")
		type_expr=$(json_pointer_to_jq "${keyword_location}")
		value=$(jq -r "${value_expr}" "${instance_path}" 2>/dev/null || printf 'unknown')
		expected_type=$(jq -r "${type_expr}" "${schema_path}" 2>/dev/null || printf 'unknown')
		printf "%s: '%s' is not of type '%s'" "${location_path}" "${value}" "${expected_type}"
		return 0
	fi

	location_path=$(json_pointer_to_path "${instance_location}" false)
	message=$(jq -r '.error // "Schema validation error"' <<<"${error_json}")
	printf '%s: %s' "${location_path}" "${message}"
}

build_executor_action_schema() {
	# Constructs a JSON schema for allowed executor tools.
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

if not allowed:
    sys.stderr.write("No tools available for executor schema\n")
    sys.exit(1)

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

    return normalized

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
                        "tool": {"const": name},
                        "args": args_schema,
                    },
                }
            },
        }
    )

schema_doc = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "title": "ExecutorAction",
    "description": "Executor tool call constrained to the provided allowed tools. All required arguments must be present in planner output; context-controlled fields may be enriched by the executor.",
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

validate_executor_action() {
	# Validates a llama-produced action against the generated schema.
	# Arguments:
	#   $1 - raw action JSON string
	#   $2 - schema path
	local raw_action schema_path action_json schema_json err_log tool allowed_tools action_extras args_schema
	local -a allowed_arg_keys=()
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

	action_json=$(jq -c '
                if (.action.args // empty | type) == "object" then
                        .action.args |= with_entries(select(.value != null))
                else
                        .
                end
        ' <<<"${action_json}")

	if ! jq -e 'keys_unsorted == ["action"]' <<<"${action_json}" >/dev/null 2>&1; then
		printf 'Unexpected or missing top-level fields\n' >&2
		return 1
	fi

	tool="$(jq -r '.action.tool // empty' <<<"${action_json}" 2>/dev/null || printf '')"
	allowed_tools=$(jq -cr '[.oneOf[]?.properties.action.properties.tool.const // empty]' <<<"${schema_json}" 2>/dev/null || printf '[]')

	if [[ -z "${tool}" ]]; then
		printf 'Missing tool name\n' >&2
		return 1
	fi

	if [[ -n "${tool}" ]]; then
		if ! jq -e --arg tool "${tool}" --argjson allowed "${allowed_tools}" '$allowed | index($tool)' <<<"null" >/dev/null; then
			printf 'Unsupported tool: %s\n' "${tool}" >&2
			return 1
		fi
	fi

	if [[ -n "${tool}" ]] && jq -e '.action.args | type == "object"' <<<"${action_json}" >/dev/null 2>&1; then
		args_schema=$(jq -c --arg tool "${tool}" '.oneOf[]? | select(.properties.action.properties.tool.const == $tool) | .properties.action.properties.args' <<<"${schema_json}" 2>/dev/null || printf '{}')
		mapfile -t allowed_arg_keys < <(jq -r '(.properties // {}) | keys[]?' <<<"${args_schema}" 2>/dev/null)
		if [[ ${#allowed_arg_keys[@]} -gt 0 ]]; then
			while IFS= read -r arg_key; do
				if [[ -z "${arg_key}" ]]; then
					continue
				fi

				if ! printf '%s\n' "${allowed_arg_keys[@]}" | grep -Fxq "${arg_key}"; then
					printf "action/args: Additional properties are not allowed ('%s' was unexpected)\n" "${arg_key}" >&2
					return 1
				fi
			done < <(jq -r '.action.args | keys[]?' <<<"${action_json}" 2>/dev/null)
		fi
	fi

	action_extras=$(jq -cr '.action | objects | [keys[]? | select(. != "tool" and . != "args")]' <<<"${action_json}" 2>/dev/null || printf '[]')
	if [[ "${action_extras}" != "[]" ]]; then
		printf "action: Additional properties are not allowed ('%s' was unexpected)\n" "$(jq -r '.[0]' <<<"${action_extras}")" >&2
		return 1
	fi

	if ! require_jsonschema_cli_available "Executor action validation"; then
		return 1
	fi

	action_tmp=$(mktemp)
	printf '%s\n' "${action_json}" >"${action_tmp}"

	validation_output=$(jsonschema_cli validate --json --default-dialect https://json-schema.org/draft/2020-12/schema "${schema_path}" "${action_tmp}" 2>"${err_log}")
	status=$?

	if ((status != 0)); then
		if [[ -n "${validation_output}" ]]; then
			printf '%s\n' "$(format_jsonschema_error "${validation_output}" "${action_tmp}" "${schema_path}")" >&2
		elif [[ -s "${err_log}" ]]; then
			cat "${err_log}" >&2
		fi
		rm -f "${action_tmp}" "${err_log}"
		return 1
	fi

	jq -c '.' "${action_tmp}"
	rm -f "${action_tmp}" "${err_log}"

	return 0
}
