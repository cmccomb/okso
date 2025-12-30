#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for run-scoped executor cache lifecycle management.
#
# Usage:
#   bats tests/lib/test_runtime_react_cache.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert helper outcomes.

@test "coerce_executor_run_cache_path scopes cache to run directory" {
	run env BASH_ENV= ENV= bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
export CACHE_DIR="${TMPDIR:-/tmp}/okso_cache_scope"
export RUN_ID="run-cache-scope"
export EXECUTOR_CACHE_FILE="/custom/location/executor.prompt-cache"
source ./src/lib/runtime.sh
create_default_settings cache_scope
coerce_executor_run_cache_path cache_scope
printf "%s\n%s" \
        "${EXECUTOR_CACHE_FILE}" \
        "$(settings_get cache_scope executor_cache_file)"
SCRIPT
	[ "$status" -eq 0 ]
	expected_path="${TMPDIR:-/tmp}/okso_cache_scope/runs/run-cache-scope/executor.prompt-cache"
	[ "${lines[0]}" = "${expected_path}" ]
	[ "${lines[1]}" = "${expected_path}" ]
}

@test "ensure_executor_run_cache_dir cleans cache on success" {
	run env BASH_ENV= ENV= bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
cache_root="$(mktemp -d)"
export EXECUTOR_CACHE_FILE="${cache_root}/runs/success/executor.prompt-cache"
source ./src/lib/runtime.sh
ensure_executor_run_cache_dir
[[ -d "${cache_root}/runs/success" ]]
cleanup_executor_run_cache_dir 0
[[ ! -d "${cache_root}/runs/success" ]]
SCRIPT
	[ "$status" -eq 0 ]
}

@test "cleanup_executor_run_cache_dir retains cache on failure" {
	run env BASH_ENV= ENV= bash --noprofile --norc <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
cache_root="$(mktemp -d)"
export EXECUTOR_CACHE_FILE="${cache_root}/runs/failure/executor.prompt-cache"
source ./src/lib/runtime.sh
ensure_executor_run_cache_dir
[[ -d "${cache_root}/runs/failure" ]]
cleanup_executor_run_cache_dir 1
[[ -d "${cache_root}/runs/failure" ]]
rm -rf "${cache_root}"
SCRIPT
	[ "$status" -eq 0 ]
}
