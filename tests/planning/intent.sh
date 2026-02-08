#!/usr/bin/env bats
# shellcheck shell=bash
# Test coverage for intent.sh.

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	unset -f __zsh_like_cd cd 2>/dev/null || true
	# shellcheck disable=SC2034 # TD-001: dynamic globals are intentionally consumed across sourced modules and tests.
	chpwd_functions=()
}

@test "recognize_intent defaults to planner model when intent model unset" {
	run env -i HOME="$HOME" PATH="$PATH" bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/intent/intent.sh
PLANNER_MODEL_REPO="planner/repo"
PLANNER_MODEL_FILE="planner.gguf"
load_schema_text() { printf '{"type":"object"}'; }
render_prompt_template() { printf 'prompt'; }
llama_infer() {
  if [[ "$5" != "planner/repo" || "$6" != "planner.gguf" ]]; then
    printf 'unexpected model: %s/%s' "$5" "$6" >&2
    exit 1
  fi
  printf '{"intents":["general"],"rationale":"ok"}'
}
recognize_intent "hello" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}
