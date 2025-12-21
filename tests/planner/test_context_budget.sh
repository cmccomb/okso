#!/usr/bin/env bats
#
# Tests for prompt context budgeting and summarization.
#
# Usage:
#   bats tests/planner/test_context_budget.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+

@test "apply_prompt_context_budget leaves short context untouched" {
	run bash -s <<'SCRIPT'
set -e
cd "$(git rev-parse --show-toplevel)" || exit 1
export PROMPT_TOKEN_BUDGET=20
export SUMMARY_LINE_CHAR_LIMIT=50
source ./src/lib/llm/context_budget.sh
log() { :; }

prompt="User: hi"
context="Short context."
output="$(apply_prompt_context_budget "${prompt}" "${context}" 5 "direct_response")"
[[ "${output}" == "${context}" ]]
SCRIPT
	[ "$status" -eq 0 ]
}

@test "apply_prompt_context_budget summarizes oversized web_fetch content" {
	run bash -s <<'SCRIPT'
set -e
cd "$(git rev-parse --show-toplevel)" || exit 1
export PROMPT_TOKEN_BUDGET=200
export SUMMARY_LINE_CHAR_LIMIT=80
source ./src/lib/llm/context_budget.sh
log() { :; }

long_body=$(printf 'A%.0s' {1..1200})
context=$'URL: https://example.com\nContent: '"${long_body}"
prompt="History:\n${context}"
summarized="$(apply_prompt_context_budget "${prompt}" "${context}" 32 "react_history")"
[[ "${summarized}" == *"Content summary:"* ]]
[[ "${summarized}" != *"${long_body}"* ]]

final_tokens=$(estimate_total_tokens "History:\n${summarized}" 32)
(( final_tokens <= PROMPT_TOKEN_BUDGET ))
SCRIPT
	[ "$status" -eq 0 ]
}
