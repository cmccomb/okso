#!/usr/bin/env bats

setup() {
        unset -f chpwd _mise_hook 2>/dev/null || true
        unset -f __zsh_like_cd cd 2>/dev/null || true
        # shellcheck disable=SC2034
        chpwd_functions=()
}

@test "render_plan_outputs logs planned tool calls for approval" {
        run env -i HOME="$HOME" PATH="$PATH" bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
source ./src/lib/runtime.sh

log_pretty() { echo "${1}|${2}|${3}"; }
log() { echo "${1}|${2}|${3}"; }
emit_plan_json() { printf '%s' "$1"; }

render_plan_outputs action settings_ns $'python_repl\nfinal_answer' '[{"tool":"python_repl","query":"print(1)"},{"tool":"final_answer","thought":"done"}]' $'1. calculate\n2. answer' ''
SCRIPT

        [ "$status" -eq 0 ]

        combined_output=$(printf '%s\n' "${lines[@]}")
        [[ "${combined_output}" == *"INFO|Planned tool calls"* ]]
        [[ "${combined_output}" == *"python_repl"* ]]
        [[ "${combined_output}" == *"final_answer"* ]]
}
