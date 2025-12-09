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

# shellcheck source=./grammar.sh disable=SC1091
source "${BASH_SOURCE[0]%/prompts.sh}/grammar.sh"

build_concise_response_prompt() {
	# Arguments:
	#   $1 - user query (string)
	local user_query concise_grammar
	user_query="$1"
	concise_grammar="$(load_grammar_text concise_response)"

	cat <<PROMPT
Provide a short, concise answer (two to three sentences) to the user. Your response will be stopped after the first newline character. USER REQUEST: ${user_query}.
Follow this JSON schema and terminate with the <eot> marker:
${concise_grammar}
CONCISE RESPONSE:
PROMPT
}

build_planner_prompt() {
	# Arguments:
	#   $1 - user query (string)
	#   $2 - formatted tool descriptions (string)
	local user_query tool_lines planner_grammar
	user_query="$1"
	tool_lines="$2"
	planner_grammar="$(load_grammar_text planner_plan)"

	cat <<PROMPT
You are a planner for an autonomous agent. Given a user request and a list of available tools, draft a numbered list of high-level actions the agent should take. Each step must mention the tool name that will be used. Do NOT include fully executable shell commands; keep the guidance conceptual. Always end with a final step that uses the final_answer tool to deliver the response back to the user.

Constrain your response using this JSON schema:
${planner_grammar}

Available tools:
${tool_lines}
User request: ${user_query}
PROMPT
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

	cat <<PROMPT
You are an assistant planning a sequence of actions. Use the high-level plan as guidance but adapt after each observation.
Respond ONLY with a single JSON object per turn.

Action schema (JSON Schema enforced):
${react_grammar}
High-level plan:
${plan_outline}
User request: ${user_query}
${allowed_tools}
Previous steps:
${history}
PROMPT
}
