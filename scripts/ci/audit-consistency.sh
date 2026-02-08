#!/usr/bin/env bash
# shellcheck shell=bash
# Consistency audit checks for marker tokens and terminology drift.
# Usage: bash ./scripts/ci/audit-consistency.sh

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "${ROOT_DIR}"

REPORT_PATH="${ROOT_DIR}/output/audit-latest.json"

consistency_errors=0
declare -a consistency_failures=()

audit_add_consistency_failure() {
	consistency_failures+=("$1")
	consistency_errors=$((consistency_errors + 1))
}

json_array_from_lines() {
	if (($# == 0)); then
		printf '[]'
		return 0
	fi
	local filtered
	filtered="$(printf '%s\n' "$@" | awk 'NF')"
	if [[ -z "${filtered}" ]]; then
		printf '[]'
		return 0
	fi
	printf '%s\n' "${filtered}" | jq -R . | jq -s .
}

check_placeholders() {
	if rg -n "\{\{[^}]+\}\}" src docs \
		--glob '!src/prompts/executor.md' \
		--glob '!docs/reference/tools.md' \
		--glob '!docs/documentation-guidelines.md' \
		--glob '!docs/_layouts/**'; then
		audit_add_consistency_failure "unresolved placeholders found outside approved examples"
	fi
}

check_marker_tokens() {
	if rg -n "\b(TODO|TBD|__MISSING__)\b|\[insert\]|<todo>|lorem ipsum" src docs workflows tests scripts README.md \
		--glob '!src/prompts/executor.md' \
		--glob '!docs/documentation-guidelines.md' \
		--glob '!docs/contributor/code-quality-standards.md' \
		--glob '!tests/fixtures/mock_llama_relevance.sh' \
		--glob '!scripts/ci/check-docs.sh' \
		--glob '!scripts/ci/audit-consistency.sh'; then
		audit_add_consistency_failure "unfinished marker tokens found outside approved examples"
	fi
}

check_known_terminology_typos() {
	if rg -n "\bdplan\b" README.md docs src tests workflows; then
		audit_add_consistency_failure "terminology typo found: dplan"
	fi
}

write_report() {
	local timestamp status consistency_json payload
	timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
	status="pass"
	if ((consistency_errors > 0)); then
		status="fail"
	fi

	consistency_json="$(json_array_from_lines "${consistency_failures[@]-}")"
	payload="$(jq -n \
		--arg timestamp "${timestamp}" \
		--arg status "${status}" \
		--argjson errors "${consistency_errors}" \
		--argjson failures "${consistency_json}" \
		'{
			generated_at: $timestamp,
			consistency_audit: {
				status: $status,
				errors: $errors,
				failures: $failures
			}
		}')"

	if [[ -f "${ROOT_DIR}/output" ]]; then
		mv "${ROOT_DIR}/output" "${ROOT_DIR}/output.legacy.$(date -u +%Y%m%dT%H%M%SZ)"
	fi
	mkdir -p "$(dirname "${REPORT_PATH}")"
	if [[ -f "${REPORT_PATH}" ]]; then
		jq -s '.[0] * .[1]' "${REPORT_PATH}" <(printf '%s\n' "${payload}") >"${REPORT_PATH}.tmp"
		mv "${REPORT_PATH}.tmp" "${REPORT_PATH}"
	else
		printf '%s\n' "${payload}" >"${REPORT_PATH}"
	fi
}

echo "Audit: consistency and marker drift"
check_placeholders
check_marker_tokens
check_known_terminology_typos

if ((consistency_errors > 0)); then
	echo "Consistency audit failures:" >&2
	printf '  - %s\n' "${consistency_failures[@]}" >&2
fi

write_report

if ((consistency_errors > 0)); then
	echo "Consistency audit failed: ${consistency_errors} issue(s)." >&2
	exit 2
fi

echo "Consistency audit passed."
