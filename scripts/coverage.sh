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
COVERAGE_TARGETS="${COVERAGE_TARGETS:-tests/test_main.bats tests/test_all.sh tests/test_install.bats tests/test_config.bats tests/test_planner.bats tests/test_tools_registry.bats}"

export COVERAGE_DIR
export SIMPLECOV_ROOT="${ROOT_DIR}"
export TESTING_PASSTHROUGH="${TESTING_PASSTHROUGH:-false}"
export LLAMA_BIN="${LLAMA_BIN:-${ROOT_DIR}/tests/fixtures/mock_llama_relevance.sh}"
export BATS_TMPDIR="${ROOT_DIR}/.bats-tmp"

rm -rf "${COVERAGE_DIR}" "${BATS_TMPDIR}"
mkdir -p "${COVERAGE_DIR}" "${BATS_TMPDIR}"

read -r -a coverage_files <<<"${COVERAGE_TARGETS}"
bashcov --root "${ROOT_DIR}" --command-name "bats" -- bats "${coverage_files[@]}"

coverage_summary=$(
	python - <<PY
import json
from pathlib import Path

result_path = Path("${COVERAGE_DIR}") / "coverage.json"
fallback_path = Path("${COVERAGE_DIR}") / ".resultset.json"
coverage_percent = 0.0

if result_path.exists():
    data = json.loads(result_path.read_text())
    coverage_data = data.get("coverage", {})
    covered = 0
    total = 0
    for file_cov in coverage_data.values():
        for hit in file_cov.get("lines", []):
            if hit is None:
                continue
            total += 1
            if hit > 0:
                covered += 1
    if total:
        coverage_percent = (covered / total) * 100
elif fallback_path.exists():
    raw = json.loads(fallback_path.read_text())
    first_result = next(iter(raw.values()))
    covered = 0
    total = 0
    for line_hits in first_result.get("coverage", {}).values():
        for hit in line_hits:
            if hit is None:
                continue
            total += 1
            if hit > 0:
                covered += 1
    if total:
        coverage_percent = (covered / total) * 100

print(f"{coverage_percent:.2f}")
PY
)

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
