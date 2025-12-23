#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	unset -f __zsh_like_cd cd 2>/dev/null || true
	# shellcheck disable=SC2034
	chpwd_functions=()
}

@test "planner_generate_search_queries returns multiple sanitized queries" {
	run env -i HOME="$HOME" PATH="$PATH" bash <<'SCRIPT'
set -euo pipefail
PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD
source ./src/lib/planning/planner.sh
LLAMA_AVAILABLE=true
SEARCH_REPHRASER_MODEL_REPO=fake
SEARCH_REPHRASER_MODEL_FILE=fake
llama_infer() { printf '["first query", " second query  "]'; }
result=$(planner_generate_search_queries "original" 2>/dev/null)
jq -e 'length == 2 and .[0] == "first query" and .[1] == "second query"' <<<"${result}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}

@test "planner_generate_search_queries forwards JSON schema to llama" {
	run env -i HOME="$HOME" PATH="$PATH" bash <<'SCRIPT'
set -euo pipefail
PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD
source ./src/lib/planning/planner.sh
LLAMA_AVAILABLE=true
SEARCH_REPHRASER_MODEL_REPO=fake
SEARCH_REPHRASER_MODEL_FILE=fake
load_schema_text() { printf 'SCHEMA_JSON'; }
llama_infer() {
  if [[ "$4" != "SCHEMA_JSON" ]]; then
    echo "schema missing" >&2
    exit 1
  fi
  printf '["clean"]'
}
planner_generate_search_queries "whatever" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}

@test "render_rephrase_prompt embeds the planner search schema" {
	run env -i HOME="$HOME" PATH="$PATH" bash <<'SCRIPT'
set -euo pipefail
PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD
source ./src/lib/planning/planner.sh
load_schema_text() { printf '{"type":"array"}'; }
rendered=$(render_rephrase_prompt "example query")
grep -F '"type":"array"' <<<"${rendered}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}

@test "planner_generate_search_queries falls back when too many outputs are returned" {
	run env -i HOME="$HOME" PATH="$PATH" bash <<'SCRIPT'
set -euo pipefail
PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD
source ./src/lib/planning/planner.sh
LLAMA_AVAILABLE=true
SEARCH_REPHRASER_MODEL_REPO=fake
SEARCH_REPHRASER_MODEL_FILE=fake
llama_infer() { printf '["a","b","c","d"]'; }
result=$(planner_generate_search_queries "keep me" 2>/dev/null)
jq -e 'length == 1 and .[0] == "keep me"' <<<"${result}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}

@test "planner_generate_search_queries falls back when model returns empty list" {
	run env -i HOME="$HOME" PATH="$PATH" bash <<'SCRIPT'
set -euo pipefail
PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD
source ./src/lib/planning/planner.sh
LLAMA_AVAILABLE=true
SEARCH_REPHRASER_MODEL_REPO=fake
SEARCH_REPHRASER_MODEL_FILE=fake
llama_infer() { printf '[]'; }
result=$(planner_generate_search_queries "stick with original" 2>/dev/null)
jq -e 'length == 1 and .[0] == "stick with original"' <<<"${result}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}

@test "planner_fetch_search_context aggregates multiple rephrased searches" {
	run env -i HOME="$HOME" PATH="$PATH" bash <<'SCRIPT'
set -euo pipefail
PLANNER_SKIP_TOOL_LOAD=true
export PLANNER_SKIP_TOOL_LOAD
source ./src/lib/planning/planner.sh
LLAMA_AVAILABLE=true
SEARCH_REPHRASER_MODEL_REPO=fake
SEARCH_REPHRASER_MODEL_FILE=fake
llama_infer() { printf '["first topic","second topic"]'; }
tool_web_search() {
  query=$(jq -r '.query' <<<"${TOOL_ARGS}")
  jq -nc --arg query "${query}" '{query:$query, items:[{title:"t", snippet:"s", url:"u"}]}'
}
planner_fetch_search_context "original" || true
SCRIPT

	[ "$status" -eq 0 ]
	first_section=$(printf '%s\n' "${output}" | grep -n "first topic" | wc -l)
	second_section=$(printf '%s\n' "${output}" | grep -n "second topic" | wc -l)
	[ "${first_section}" -ge 1 ]
	[ "${second_section}" -ge 1 ]
}
