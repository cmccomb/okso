#!/usr/bin/env bash
# shellcheck shell=bash
#
# Model spec parsing and hydration helpers.
#
# Usage:
#   source "${BASH_SOURCE[0]%/model_specs.sh}/model_specs.sh"

parse_model_spec() {
	# Parse model spec into repo[:file] components.
	# Arguments:
	#   $1 - model spec repo[:file]
	#   $2 - default file fallback
	# Returns:
	#   repo and file on separate lines.
	local spec default_file repo file
	spec="$1"
	default_file="$2"

	if [[ "${spec}" == *:* ]]; then
		repo="${spec%%:*}"
		file="${spec#*:}"
	else
		repo="${spec}"
		file="${default_file}"
	fi

	printf '%s\n%s\n' "${repo}" "${file}"
}

hydrate_model_spec_to_vars() {
	# Normalize a model spec into repo and file variables.
	# Arguments:
	#   $1 - model spec string (repo[:file])
	#   $2 - default file name
	#   $3 - repo variable name to populate
	#   $4 - file variable name to populate
	# Returns:
	#   None; sets specified variables.
	local model_parts repo_var file_var
	model_parts=()
	repo_var="$3"
	file_var="$4"

	while IFS= read -r line; do
		model_parts+=("$line")
	done < <(parse_model_spec "$1" "$2")

	printf -v "${repo_var}" '%s' "${model_parts[0]}"
	printf -v "${file_var}" '%s' "${model_parts[1]}"
}

hydrate_model_specs() {
	# Normalize all model specs into repo and file components.
	hydrate_model_spec_to_vars "${PLANNER_MODEL_SPEC}" "${DEFAULT_PLANNER_MODEL_FILE}" PLANNER_MODEL_REPO PLANNER_MODEL_FILE
	hydrate_model_spec_to_vars "${EXECUTOR_MODEL_SPEC}" "${DEFAULT_EXECUTOR_MODEL_FILE}" EXECUTOR_MODEL_REPO EXECUTOR_MODEL_FILE
	hydrate_model_spec_to_vars "${VALIDATOR_MODEL_SPEC}" "${DEFAULT_VALIDATOR_MODEL_SPEC_BASE##*:}" VALIDATOR_MODEL_REPO VALIDATOR_MODEL_FILE
	hydrate_model_spec_to_vars "${SEARCH_REPHRASER_MODEL_SPEC}" "${DEFAULT_REPHRASER_MODEL_FILE}" SEARCH_REPHRASER_MODEL_REPO SEARCH_REPHRASER_MODEL_FILE
}
