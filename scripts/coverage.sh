#!/usr/bin/env bash
# shellcheck shell=bash
#
# Run the Bats suite with bashcov to collect coverage artifacts.
#
# Usage:
#   ./scripts/coverage.sh
#
# Environment variables:
#   COVERAGE_DIR (string): output directory for coverage reports. Default: coverage
#   COVERAGE_THRESHOLD (float): warn when total coverage is below this percent. Default: 0 (no check)
#   COVERAGE_STRICT (bool): fail when coverage is below the threshold when set to "true".
#   TESTING_PASSTHROUGH (bool): disable llama.cpp calls during coverage runs. Default: false
#
# Dependencies:
#   - bash 5+
#   - bats
#   - bashcov (Ruby gem)
#   - jq
#   - bc
#
# Exit codes:
#   0 on success, 1 when coverage enforcement fails or bats exits non-zero.

set -eo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
COVERAGE_DIR="${COVERAGE_DIR:-${ROOT_DIR}/coverage}"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-0}"
COVERAGE_STRICT="${COVERAGE_STRICT:-false}"
COVERAGE_TARGETS="${COVERAGE_TARGETS:-tests/cli/test_main.bats tests/cli/test_all.sh tests/cli/test_install.bats tests/core/test_config.bats tests/core/test_planner.bats tests/tools/test_tools_registry.bats}"

export COVERAGE_DIR
export SIMPLECOV_ROOT="${ROOT_DIR}"
export TESTING_PASSTHROUGH="${TESTING_PASSTHROUGH:-false}"
export LLAMA_BIN="${LLAMA_BIN:-${ROOT_DIR}/tests/fixtures/mock_llama_relevance.sh}"
export BATS_TMPDIR="${ROOT_DIR}/.bats-tmp"

rm -rf "${COVERAGE_DIR}" "${BATS_TMPDIR}"
mkdir -p "${COVERAGE_DIR}" "${BATS_TMPDIR}"

read -r -a coverage_files <<<"${COVERAGE_TARGETS}"
bashcov --root "${ROOT_DIR}" --command-name "bats" -- bats "${coverage_files[@]}"

coverage_source=""
if [[ -f "${COVERAGE_DIR}/coverage.json" ]]; then
	coverage_source="${COVERAGE_DIR}/coverage.json"
elif [[ -f "${COVERAGE_DIR}/.resultset.json" ]]; then
	coverage_source="${COVERAGE_DIR}/.resultset.json"
fi

coverage_summary=$(
	if [[ -n "${coverage_source}" ]]; then
		jq -er 'if has("metrics") then (.metrics.line.percent // .metrics.covered_percent // 0) else ([.[]? | select(.coverage?) | .coverage][0] // {}) as $coverage | reduce $coverage[]? as $file ({t: 0, c: 0}; ($file.lines // $file) as $lines | .t += ($lines|length) | .c += ($lines|map(select(. != null and . > 0))|length)) | if .t > 0 then (.c / .t * 100) else 0 end end' "${coverage_source}"
	else
		echo "0"
	fi
)
coverage_summary=$(printf '%.2f' "${coverage_summary}")

echo "Total coverage: ${coverage_summary}%"

threshold_numeric=$(printf '%.2f' "${COVERAGE_THRESHOLD}")
if (($(echo "${threshold_numeric} > 0" | bc -l))); then
	below_threshold=$(echo "${coverage_summary} < ${threshold_numeric}" | bc -l)
	if ((below_threshold)); then
		>&2 echo "Coverage ${coverage_summary}% is below threshold ${threshold_numeric}%"
		if [[ "${COVERAGE_STRICT}" == true ]]; then
			exit 1
		fi
	fi
fi
