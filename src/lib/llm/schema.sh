#!/usr/bin/env bash
# shellcheck shell=bash
#
# Schema utilities for locating shared llama.cpp schemas.
#
# Usage:
#   source "${BASH_SOURCE[0]%/schema.sh}/schema.sh"
#
# Environment variables:
#   None.
#
# Dependencies:
#   - bash 3.2+
#
# Exit codes:
#   Functions return non-zero when an unknown schema name is requested.

SCHEMA_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${SCHEMA_LIB_DIR}/../core/logging.sh"

schema_root_dir() {
	# Changes to the schema directory and prints its absolute path.
	# Returns:
	#   Absolute path to the schema directory (string).
	cd "${SCHEMA_LIB_DIR}/../../schemas" && pwd
}

schema_path() {
	# Resolves a schema name to its file path.
	# Arguments:
	#   $1 - schema key (string)
	# Returns:
	#   Absolute path to the schema file (string).
	local schema_name schema_file
	schema_name="$1"

	# Map schema names to filenames
	case "${schema_name}" in
	executor_action)
		schema_file="executor_action.schema.json"
		;;
	planner_plan)
		schema_file="planner_plan.schema.json"
		;;
	pre_planner_search_terms)
		schema_file="pre_planner_search_terms.schema.json"
		;;
	intent)
		schema_file="intent.schema.json"
		;;
	final_answer_evaluation)
		schema_file="final_answer_evaluation.schema.json"
		;;
	*)
		log "ERROR" "Unknown schema requested" "${schema_name}" || true
		return 1
		;;
	esac

	# Construct full path
	printf '%s/%s' "$(schema_root_dir)" "${schema_file}"
}

load_schema_text() {
	# Reads a schema file and writes it to stdout as a single line (no newlines).
	# Arguments:
	#   $1 - schema key (string)
	# Returns:
	#   Schema content on stdout; non-zero on failure.
	local schema_name schema_file_path
	schema_name="$1"
	schema_file_path="$(schema_path "${schema_name}")" || return 1

	# Remove LF/CR so --json-schema sees valid JSON (whitespace is fine; literal newlines can break some parsers).
	# Also trim leading/trailing spaces.
	tr -d '\r\n' <"${schema_file_path}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

canonicalize_schema_for_llama() {
	# Rewrites JSON Schema constructs that llama.cpp rejects while preserving
	# equivalent validation semantics.
	# Arguments:
	#   $1 - raw schema JSON (string)
	# Returns:
	#   Canonicalized schema JSON (single-line string).
	local schema_json
	schema_json="$1"

	if [[ -z "${schema_json}" ]]; then
		printf '{}'
		return 0
	fi

	jq -c '
    def expand_required_only_branches:
      if type == "object" then
        . as $obj
        | (
            if has("anyOf") and (.anyOf | type == "array") then
              .anyOf |= map(
                if (type == "object") and (keys == ["required"]) then
                  {
                    type: "object",
                    required: .required,
                    properties: ($obj.properties // {}),
                    additionalProperties: ($obj.additionalProperties // true)
                  }
                else
                  .
                end
              )
            else
              .
            end
          )
        | (
            if has("oneOf") and (.oneOf | type == "array") then
              .oneOf |= map(
                if (type == "object") and (keys == ["required"]) then
                  {
                    type: "object",
                    required: .required,
                    properties: ($obj.properties // {}),
                    additionalProperties: ($obj.additionalProperties // true)
                  }
                else
                  .
                end
              )
            else
              .
            end
          )
        | with_entries(.value |= expand_required_only_branches)
      elif type == "array" then
        map(expand_required_only_branches)
      else
        .
      end;

    def rewrite_const:
      if type == "object" then
        (
          if has("const") and (has("enum") | not) then
            .enum = [.const] | del(.const)
          else
            .
          end
        )
        | with_entries(.value |= rewrite_const)
      elif type == "array" then
        map(rewrite_const)
      else
        .
      end;

    def rewrite_prefix_items:
      if type == "object" then
        . as $obj
        | (
            if has("prefixItems") and (.prefixItems | type == "array") then
              .items = .prefixItems
              | .additionalItems = (
                  if ($obj | has("items")) then
                    if $obj.items == false then
                      false
                    elif $obj.items == true then
                      true
                    elif ($obj.items | type) == "object" then
                      $obj.items
                    else
                      true
                    end
                  else
                    true
                  end
                )
              | del(.prefixItems)
            else
              .
            end
          )
        | with_entries(.value |= rewrite_prefix_items)
      elif type == "array" then
        map(rewrite_prefix_items)
      else
        .
      end;

    expand_required_only_branches
    | rewrite_const
    | rewrite_prefix_items
  ' <<<"${schema_json}" 2>/dev/null || printf '{}'
}
