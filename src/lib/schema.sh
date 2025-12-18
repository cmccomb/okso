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
#   - bash 5+
#
# Exit codes:
#   Functions return non-zero when an unknown schema name is requested.

LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Returns the absolute path to the schema directory.
schema_root_dir() {
	cd "${LIB_DIR}/../schemas" && pwd
}

# Resolves a schema name to its file path.
# Arguments:
#   $1 - schema key (string)
schema_path() {
	local schema_name schema_file
	schema_name="$1"

	case "${schema_name}" in
	react_action)
		schema_file="react_action.schema.json"
		;;
	planner_plan)
		schema_file="planner_plan.schema.json"
		;;
	concise_response)
		schema_file="concise_response.schema.json"
		;;
	*)
		printf 'Unknown schema requested: %s\n' "${schema_name}" >&2
		return 1
		;;
	esac

	printf '%s/%s' "$(schema_root_dir)" "${schema_file}"
}

# Reads a schema file and writes it to stdout.
# Arguments:
#   $1 - schema key (string)
load_schema_text() {
	local schema_name schema_file_path
	schema_name="$1"
	schema_file_path="$(schema_path "${schema_name}")" || return 1

	cat "${schema_file_path}"
}
