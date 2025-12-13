#!/usr/bin/env bats
#
# Tests for centralized prompt builders.
#
# Usage:
#   bats tests/core/test_prompts.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

@test "concise response prompt embeds user request" {
	run bash -lc 'cd "$(git rev-parse --show-toplevel)" && source ./src/lib/prompts.sh; prompt=$(build_concise_response_prompt "Help me"); [[ "$prompt" == *"Help me"* ]]; [[ "$prompt" == *"CONCISE RESPONSE:"* ]]'
	[ "$status" -eq 0 ]
}

@test "planner prompt includes tool catalog and request" {
	run bash -lc 'cd "$(git rev-parse --show-toplevel)" && source ./src/lib/prompts.sh; tools=$"- alpha: does a thing\n- beta: does another"; prompt=$(build_planner_prompt "Map a plan" "$tools"); [[ "$prompt" == *"alpha: does a thing"* ]]; [[ "$prompt" == *$'"'"'User request:\nMap a plan'"'"'* ]]'
	[ "$status" -eq 0 ]
}

@test "react prompt lists schema and previous steps" {
        run bash -lc 'cd "$(git rev-parse --show-toplevel)" && source ./src/lib/prompts.sh; tools=$"Available tools:\n- gamma: sample (example query: try gamma)"; prompt=$(build_react_prompt "Assist" "$tools" "1. Start" "Observed"); [[ "$prompt" == *"Action schema:"* ]]; [[ "$prompt" == *"Available tools"* ]]; [[ "$prompt" == *"example query: try gamma"* ]]; [[ "$prompt" == *"Observed"* ]]'
        [ "$status" -eq 0 ]
}

@test "prompt templates are loaded from disk" {
        run bash -lc 'cd "$(git rev-parse --show-toplevel)" && source ./src/lib/prompts.sh; template=$(load_prompt_template planner); [[ "$template" == *"# General Rules"* ]]; [[ "$template" == *"# Plan:"* ]]'
        [ "$status" -eq 0 ]
}
