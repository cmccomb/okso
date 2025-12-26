#!/usr/bin/env bats
# shellcheck shell=bash
#
# Executor schema validation tests for tool argument handling.
#
# Usage:
#   bats tests/lib/test_executor_schema.sh
#
# Dependencies:
#   - bats
#   - jq

@test "validate_executor_action rejects non-integer web_search num" {
	run env BASH_ENV= ENV= bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
source ./src/lib/executor/schema.sh
schema_path=$(build_executor_action_schema "web_search")
trap 'rm -f "${schema_path}"' EXIT

action='{"action":{"tool":"web_search","args":{"query":"okso","num":2.5}}}'
set +e
validate_executor_action "${action}" "${schema_path}"
result=$?
set -e
if [ "${result}" -eq 0 ]; then
        echo "Expected validation failure" >&2
        exit 1
fi
SCRIPT
	[ "$status" -eq 0 ]
}
