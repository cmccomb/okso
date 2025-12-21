#!/usr/bin/env bash
# shellcheck shell=bash
#
# Prompt template loading and rendering helpers.
#
# Usage:
#   source "${BASH_SOURCE[0]%/templates.sh}/templates.sh"
#
# Dependencies:
#   - bash 3.2+
#   - envsubst (typically via gettext)
#
# Exit codes:
#   Functions print rendered templates and return 0 on success.

PROMPT_TEMPLATES_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROMPTS_DIR="${PROMPT_TEMPLATES_DIR%/lib/prompt}/prompts"

# shellcheck source=../core/logging.sh disable=SC1091
source "${PROMPT_TEMPLATES_DIR}/../core/logging.sh"

load_prompt_template() {
	# Loads a prompt template from the prompts directory.
	# Arguments:
	#   $1 - prompt name (string)
	# Returns:
	#   The content of the prompt template (string).
	local prompt_name prompt_path
	prompt_name="$1"
	prompt_path="${PROMPTS_DIR}/${prompt_name}.txt"

	if [[ ! -f "${prompt_path}" ]]; then
		log "ERROR" "prompt template missing" "${prompt_path}" || true
		return 1
	fi

	cat "${prompt_path}"
}

render_prompt_template() {
	# Renders a prompt template by substituting key/value pairs.
	# Arguments:
	#   $1 - prompt name (string)
	#   $@ - alternating keys and values for substitution (string)
	# Returns:
	#   The rendered prompt text (string).
	local prompt_name prompt_text
	local -a substitutions=()

	prompt_name="$1"
	shift
	prompt_text="$(load_prompt_template "${prompt_name}")" || return 1

	if (($# % 2 != 0)); then
		log "ERROR" "render_prompt_template expects substitution pairs" "args_count=$#" || true
		return 1
	fi

	while (($# > 0)); do
		local key value
		key="$1"
		value="$2"
		substitutions+=("${key}=${value}")
		shift 2
	done

	if ((${#substitutions[@]} == 0)); then
		printf '%s' "${prompt_text}"
		return 0
	fi

	env "${substitutions[@]}" envsubst <<<"${prompt_text}"
}

export -f load_prompt_template
export -f render_prompt_template
