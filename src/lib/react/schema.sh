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
        local raw_action schema_path action_json schema_json err_log missing_token tool allowed_tools python_status
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

        tool="$(jq -r '.action.tool // empty' <<<"${action_json}" 2>/dev/null || printf '')"
        allowed_tools=$(jq -cr --arg missing "${missing_token}" '[.oneOf[]?.properties.action.properties.tool.anyOf[]?.const // empty] | map(select(. != $missing))' <<<"${schema_json}" 2>/dev/null || printf '[]')

        if [[ -n "${tool}" && "${tool}" != "${missing_token}" ]]; then
                if ! jq -e --arg tool "${tool}" --argjson allowed "${allowed_tools}" '$allowed | index($tool)' <<<"null" >/dev/null; then
                        printf 'Unsupported tool: %s\n' "${tool}" >&2
                        return 1
                fi
        fi

        python3 - "${schema_path}" "${action_json}" <<'PY'
import json
import sys

try:
    from jsonschema import Draft202012Validator
except ImportError:
    sys.stderr.write("jsonschema dependency missing; install with pip install jsonschema\n")
    sys.exit(2)


def _leaf_errors(error):
    if error.context:
        for child in error.context:
            yield from _leaf_errors(child)
    else:
        yield error


schema_path = sys.argv[1]
instance = json.loads(sys.argv[2])

with open(schema_path, "r", encoding="utf-8") as schema_file:
    schema = json.load(schema_file)

validator = Draft202012Validator(schema)
errors = sorted(validator.iter_errors(instance), key=lambda err: (len(list(err.path)), err.path))

if errors:
    leaves = [leaf for err in errors for leaf in _leaf_errors(err)]

    def _message_priority(message: str) -> int:
        if "Additional properties" in message:
            return 0
        if "not of type" in message:
            return 1
        if "expected" in message:
            return 2
        return 3

    leaves.sort(
        key=lambda err: (
            _message_priority(err.message),
            -len(list(err.absolute_path)),
            list(err.absolute_path),
            err.message,
        )
    )
    leaf_error = leaves[0]
    location = "/".join(str(part) for part in leaf_error.absolute_path) or "root"
    sys.stderr.write(f"{location}: {leaf_error.message}\n")
    sys.exit(1)

print(json.dumps(instance, separators=(",", ":")))
PY
        python_status=$?

        if ((python_status == 2)); then
                return 1
        fi

        return ${python_status}
}
