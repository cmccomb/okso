#!/usr/bin/env bash
# shellcheck shell=bash
# Comment and shell-style audit checks for repository consistency.
# Usage: bash ./scripts/ci/audit-comments.sh

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "${ROOT_DIR}"

REPORT_PATH="${ROOT_DIR}/output/audit-latest.json"
DEBT_REGISTER="${ROOT_DIR}/docs/contributor/tech-debt-register.md"

header_errors=0
suppression_errors=0
docblock_errors=0

declare -a header_failures=()
declare -a suppression_failures=()
declare -a docblock_failures=()

audit_add_header_failure() {
	header_failures+=("$1")
	header_errors=$((header_errors + 1))
}

audit_add_suppression_failure() {
	suppression_failures+=("$1")
	suppression_errors=$((suppression_errors + 1))
}

audit_add_docblock_failure() {
	docblock_failures+=("$1")
	docblock_errors=$((docblock_errors + 1))
}

audit_has_purpose_line() {
	local file
	file="$1"
	awk 'NR<=12 && /^# / && $0 !~ /^# shellcheck shell=bash$/ {found=1} END {exit found?0:1}' "${file}"
}

audit_check_headers() {
	local file shebang
	while IFS= read -r file; do
		shebang="$(head -n1 "${file}" || true)"
		if [[ "${file}" == tests/* ]]; then
			if [[ "${shebang}" != "#!/usr/bin/env bash" && "${shebang}" != "#!/usr/bin/env bats" ]]; then
				audit_add_header_failure "invalid test shebang: ${file}"
				continue
			fi
			if ! head -n6 "${file}" | rg -q '^# shellcheck shell=bash$'; then
				audit_add_header_failure "missing shellcheck header: ${file}"
			fi
			if ! audit_has_purpose_line "${file}"; then
				audit_add_header_failure "missing one-line purpose in first 12 lines: ${file}"
			fi
			continue
		fi

		if [[ "${shebang}" != "#!/usr/bin/env bash" ]]; then
			audit_add_header_failure "invalid shebang (expected bash): ${file}"
			continue
		fi
		if ! head -n6 "${file}" | rg -q '^# shellcheck shell=bash$'; then
			audit_add_header_failure "missing shellcheck header: ${file}"
		fi
		if ! audit_has_purpose_line "${file}"; then
			audit_add_header_failure "missing one-line purpose in first 12 lines: ${file}"
		fi

		if [[ "${file}" == src/* || "${file}" == scripts/* ]]; then
			if ! head -n24 "${file}" | rg -q '^# Usage:'; then
				audit_add_header_failure "missing usage line in header: ${file}"
			fi
		fi
	done < <(find src tests scripts workflows -type f \( -name '*.sh' -o -path 'src/bin/okso' \) | sort)
}

audit_check_suppressions() {
	local register_ids line file line_no text td_id
	if [[ ! -f "${DEBT_REGISTER}" ]]; then
		audit_add_suppression_failure "debt register missing: ${DEBT_REGISTER}"
		return
	fi

	register_ids="$(rg -o 'TD-[0-9]{3}' "${DEBT_REGISTER}" | sort -u || true)"

	while IFS= read -r line; do
		[[ -z "${line}" ]] && continue
		file="${line%%:*}"
		line_no="${line#*:}"
		line_no="${line_no%%:*}"
		text="${line#*:*:}"

		if [[ ! "${text}" =~ TD-[0-9]{3}:[[:space:]].+ ]]; then
			audit_add_suppression_failure "missing TD id and rationale: ${file}:${line_no}"
			continue
		fi

		td_id="$(printf '%s' "${text}" | rg -o 'TD-[0-9]{3}' | head -n1 || true)"
		if [[ -z "${td_id}" ]]; then
			audit_add_suppression_failure "unable to parse TD id: ${file}:${line_no}"
			continue
		fi
		if ! rg -q "^${td_id}$" <<<"${register_ids}"; then
			audit_add_suppression_failure "unknown TD id ${td_id}: ${file}:${line_no}"
		fi
	done < <(rg -n '^[[:space:]]*#[[:space:]]*shellcheck disable=' src tests scripts workflows || true)
}

audit_check_docblocks() {
	local file fn_count
	while IFS= read -r file; do
		fn_count="$(rg -n '^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{' "${file}" | wc -l | tr -d ' ')"
		if [[ "${fn_count}" == "0" ]]; then
			continue
		fi
		if ! rg -q '^[[:space:]]*# Arguments:' "${file}"; then
			audit_add_docblock_failure "missing Arguments docblock marker: ${file}"
		fi
		if ! rg -q '^[[:space:]]*# Returns:' "${file}"; then
			audit_add_docblock_failure "missing Returns docblock marker: ${file}"
		fi
	done < <(find src/lib -type f -name '*.sh' | sort)
}

audit_print_failures() {
	local title
	title="$1"
	shift
	if (($# == 0)); then
		return 0
	fi
	echo "${title}" >&2
	printf '  - %s\n' "$@" >&2
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

write_report() {
	local timestamp status total_errors
	local header_json suppression_json docblock_json comments_json
	timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
	total_errors=$((header_errors + suppression_errors + docblock_errors))
	status="pass"
	if ((total_errors > 0)); then
		status="fail"
	fi

	header_json="$(json_array_from_lines "${header_failures[@]-}")"
	suppression_json="$(json_array_from_lines "${suppression_failures[@]-}")"
	docblock_json="$(json_array_from_lines "${docblock_failures[@]-}")"

	comments_json="$(jq -n \
		--arg timestamp "${timestamp}" \
		--arg status "${status}" \
		--argjson total_errors "${total_errors}" \
		--argjson header_errors "${header_errors}" \
		--argjson suppression_errors "${suppression_errors}" \
		--argjson docblock_errors "${docblock_errors}" \
		--argjson header_failures "${header_json}" \
		--argjson suppression_failures "${suppression_json}" \
		--argjson docblock_failures "${docblock_json}" \
		'{
			generated_at: $timestamp,
			comments_audit: {
				status: $status,
				total_errors: $total_errors,
				header: {errors: $header_errors, failures: $header_failures},
				suppressions: {errors: $suppression_errors, failures: $suppression_failures},
				docblocks: {errors: $docblock_errors, failures: $docblock_failures}
			}
		}')"

	if [[ -f "${ROOT_DIR}/output" ]]; then
		mv "${ROOT_DIR}/output" "${ROOT_DIR}/output.legacy.$(date -u +%Y%m%dT%H%M%SZ)"
	fi
	mkdir -p "$(dirname "${REPORT_PATH}")"
	printf '%s\n' "${comments_json}" >"${REPORT_PATH}"
}

echo "Audit: comment and header consistency"
audit_check_headers
audit_check_suppressions
audit_check_docblocks

if ((header_errors > 0)); then
	audit_print_failures "Header policy failures:" "${header_failures[@]}"
fi
if ((suppression_errors > 0)); then
	audit_print_failures "Suppression policy failures:" "${suppression_failures[@]}"
fi
if ((docblock_errors > 0)); then
	audit_print_failures "Docblock policy failures:" "${docblock_failures[@]}"
fi

write_report

total_errors=$((header_errors + suppression_errors + docblock_errors))
if ((total_errors > 0)); then
	echo "Audit failed: ${total_errors} issue(s)." >&2
	exit 2
fi

echo "Audit passed."
