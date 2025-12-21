#!/usr/bin/env bats
#
# Regression tests for planner initialization.
#
# Usage:
#   bats tests/planner/test_planner_init.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+

@test "planner models remain unset until initialized" {
	run bash -lc '
                set -euo pipefail
                cd "$(git rev-parse --show-toplevel)" || exit 1

                source ./src/lib/planning/planner.sh

                [[ -z "${PLANNER_MODEL_REPO:-}" ]]
                [[ -z "${PLANNER_MODEL_FILE:-}" ]]
                [[ -z "${REACT_MODEL_REPO:-}" ]]
                [[ -z "${REACT_MODEL_FILE:-}" ]]

                initialize_planner_models

                [[ "${PLANNER_MODEL_REPO}" == "${DEFAULT_PLANNER_MODEL_REPO_BASE}" ]]
                [[ "${PLANNER_MODEL_FILE}" == "${DEFAULT_PLANNER_MODEL_FILE_BASE}" ]]
                [[ "${REACT_MODEL_REPO}" == "${DEFAULT_MODEL_REPO_BASE}" ]]
                [[ "${REACT_MODEL_FILE}" == "${DEFAULT_MODEL_FILE_BASE}" ]]
        '
	[ "$status" -eq 0 ]
}
