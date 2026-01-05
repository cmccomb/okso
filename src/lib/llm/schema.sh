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
	final_answer_verification)
		schema_file="final_answer_verification.schema.json"
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
