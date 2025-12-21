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

# shellcheck source=../core/logging.sh disable=SC1091
source "${SCHEMA_LIB_DIR}/../core/logging.sh"

# Returns the absolute path to the schema directory.
schema_root_dir() {
	cd "${SCHEMA_LIB_DIR}/../../schemas" && pwd
}

# Resolves a schema name to its file path.
# Arguments:
#   $1 - schema key (string)
# Returns:
#   Absolute path to the schema file (string).
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
		log "ERROR" "Unknown schema requested" "${schema_name}" || true
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
