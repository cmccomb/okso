#!/usr/bin/env bash
# shellcheck shell=bash
#
# Prompt builders for the okso assistant.
#
# Usage:
#   source "${BASH_SOURCE[0]%/prompts.sh}/prompts.sh"
#
# Environment variables:
#   None.
#
# Dependencies:
#   - bash 5+
#
# Exit codes:
#   Functions print prompts and return 0 on success.

LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROMPTS_DIR="${LIB_DIR%/lib}/prompts"

# shellcheck source=./grammar.sh disable=SC1091
source "${LIB_DIR}/grammar.sh"

load_prompt_template() {
        # Arguments:
        #   $1 - prompt name (string)
        local prompt_name prompt_path
        prompt_name="$1"
        prompt_path="${PROMPTS_DIR}/${prompt_name}.txt"

        if [[ ! -f "${prompt_path}" ]]; then
                printf 'prompt template missing: %s\n' "${prompt_path}" >&2
                return 1
        fi

        cat "${prompt_path}"
}

render_prompt_template() {
        # Arguments:
        #   $1 - prompt name (string)
        #   $@ - key/value pairs for substitution (string)
        # Types:
        #   prompt name: string
        #   key/value pairs: alternating strings representing variable names and values
        local prompt_name prompt_text
        local -a substitutions=()

        prompt_name="$1"
        shift
        prompt_text="$(load_prompt_template "${prompt_name}")" || return 1

        if (($# % 2 != 0)); then
                printf 'render_prompt_template expects an even number of substitution arguments\n' >&2
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

build_concise_response_prompt() {
        # Arguments:
        #   $1 - user query (string)
        local user_query concise_grammar
        user_query="$1"
        concise_grammar="$(load_grammar_text concise_response)"

        render_prompt_template "concise_response" \
                user_query "${user_query}" \
                concise_grammar "${concise_grammar}"
}

build_planner_prompt() {
        # Arguments:
        #   $1 - user query (string)
        #   $2 - formatted tool descriptions (string)
        local user_query tool_lines planner_grammar
        user_query="$1"
        tool_lines="$2"
        planner_grammar="$(load_grammar_text planner_plan)"

        render_prompt_template "planner" \
                user_query "${user_query}" \
                tool_lines "${tool_lines}" \
                planner_grammar "${planner_grammar}"
}

build_react_prompt() {
        # Arguments:
        #   $1 - user query (string)
        #   $2 - formatted allowed tool descriptions (string)
        #   $3 - high-level plan outline (string)
        #   $4 - prior interaction history (string)
        local user_query allowed_tools plan_outline history react_grammar
        user_query="$1"
        allowed_tools="$2"
        plan_outline="$3"
        history="$4"
        react_grammar="$(load_grammar_text react_action)"

        render_prompt_template "react" \
                user_query "${user_query}" \
                allowed_tools "${allowed_tools}" \
                plan_outline "${plan_outline}" \
                history "${history}" \
                react_grammar "${react_grammar}"
}
