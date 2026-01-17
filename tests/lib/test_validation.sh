#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for final answer validation helpers.
#
# Usage:
#   bats tests/lib/test_validation.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert helper outcomes.

@test "evaluate_final_answer_against_query handles invalid JSON responses" {
	run env BASH_ENV= ENV= bash --noprofile --norc -c '
                set -euo pipefail
                cd "$(git rev-parse --show-toplevel)" || exit 1
                mock_dir="$(mktemp -d)"
                mock_llama="${mock_dir}/mock_llama.sh"
                cat >"${mock_llama}" <<"SCRIPT"
#!/usr/bin/env bash
printf "%s" "not-json output"
SCRIPT
                chmod +x "${mock_llama}"
                export LLAMA_AVAILABLE=true
                export LLAMA_BIN="${mock_llama}"
                export EXECUTOR_MODEL_REPO=demo/repo
                export EXECUTOR_MODEL_FILE=model.gguf
                export VERBOSITY=0
                stderr_file="${mock_dir}/stderr.log"
                exec 2>"${stderr_file}"
                source ./src/lib/validation/validation.sh
                result="$(evaluate_final_answer_against_query "question" "answer")"
                printf "%s\n" "${result}"
                if grep -q "jq: parse error" "${stderr_file}"; then
                        printf "jq error emitted\n" >&2
                        exit 1
                fi
        '
	[ "$status" -eq 0 ]
	eval_json="$output"
	[ -n "$eval_json" ]
	run jq -e '.evaluation_type == "PASS" and .output == "answer"' <<<"$eval_json"
	[ "$status" -eq 0 ]
}
