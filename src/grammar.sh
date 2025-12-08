#!/usr/bin/env bash
# shellcheck shell=bash
#
# Grammar utilities for locating shared llama.cpp grammars.
#
# Usage:
#   source "${BASH_SOURCE[0]%/grammar.sh}/grammar.sh"
#
# Environment variables:
#   None.
#
# Dependencies:
#   - bash 5+
#
# Exit codes:
#   Functions return non-zero when an unknown grammar name is requested.

# Returns the absolute path to the grammar directory.
grammar_root_dir() {
	local script_dir
	script_dir="${BASH_SOURCE[0]%/grammar.sh}"
	cd "${script_dir}/grammars" && pwd
}

# Resolves a grammar name to its file path.
# Arguments:
#   $1 - grammar key (string)
grammar_path() {
	local grammar_name grammar_file
	grammar_name="$1"

	case "${grammar_name}" in
	react_action)
		grammar_file="react_action.gbnf"
		;;
	planner_plan)
		grammar_file="planner_plan.gbnf"
		;;
	concise_response)
		grammar_file="concise_response.gbnf"
		;;
	*)
		printf 'Unknown grammar requested: %s\n' "${grammar_name}" >&2
		return 1
		;;
	esac

	printf '%s/%s' "$(grammar_root_dir)" "${grammar_file}"
}

# Reads a grammar file and writes it to stdout.
# Arguments:
#   $1 - grammar key (string)
load_grammar_text() {
	local grammar_name grammar_file_path
	grammar_name="$1"
	grammar_file_path="$(grammar_path "${grammar_name}")" || return 1

	cat "${grammar_file_path}"
}
