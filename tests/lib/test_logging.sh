#!/usr/bin/env bats
#
# Tests for logging and user output helpers.
#
# Usage:
#   bats tests/lib/test_logging.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Inherits Bats semantics.

setup() {
	cd "$(git rev-parse --show-toplevel)" || exit 1
}

@test "log suppresses info when quiet" {
	run bash -lc '
                source ./src/lib/core/logging.sh
                VERBOSITY=0 log INFO "hidden" "detail"
        '

	[ "$status" -eq 0 ]
	[[ -z "$output" ]]
}

@test "log emits compact JSON with message metadata" {
	run bash -lc '
                source ./src/lib/core/logging.sh
                VERBOSITY=1 log INFO "visible" "more-detail"
        '

	[ "$status" -eq 0 ]
	level=$(jq -r '.level' <<<"${output}")
	message=$(jq -r '.message' <<<"${output}")
	detail=$(jq -r '.detail' <<<"${output}")

	[[ "${level}" == "INFO" ]]
	[[ "${message}" == "visible" ]]
	[[ "${detail}" == "more-detail" ]]
}

@test "log handles large detail payloads without blowing argv" {
	run bash -lc '
                source ./src/lib/core/logging.sh

                detail=$(perl -e "print '"'"'a'"'"' x 200000")
                VERBOSITY=1 log INFO "large" "${detail}"
        '

	[ "$status" -eq 0 ]
	detail_length=$(jq -r '.detail | length' <<<"${output}")

	[[ "${detail_length}" -eq 200000 ]]
}

@test "log debug messages honor verbosity" {
	run bash -lc '
                source ./src/lib/core/logging.sh
                VERBOSITY=1 log DEBUG "silenced" "detail"
        '

	[ "$status" -eq 0 ]
	[[ -z "$output" ]]
}

@test "user output stays on stdout while logs remain on stderr" {
	run bash -lc '
                source ./src/lib/cli/output.sh
                source ./src/lib/core/logging.sh

                stdout_file=$(mktemp)
                stderr_file=$(mktemp)

                {
                        user_output_line "user-facing"
                        VERBOSITY=1 log WARN "diagnostic" "detail"
                } 1>"${stdout_file}" 2>"${stderr_file}"

                printf "STDOUT:%s\nSTDERR:%s\n" "$(cat "${stdout_file}")" "$(cat "${stderr_file}")"
        '

	[ "$status" -eq 0 ]
	stdout_line=$(printf '%s' "${output}" | awk -F':' '/^STDOUT:/ {print $2}')
	stderr_payload=$(printf '%s' "${output}" | awk -F':' '/^STDERR:/ {sub(/^STDERR:/, ""); print $0}' | tail -n1)

	[[ "${stdout_line}" == "user-facing" ]]
	[[ -n "${stderr_payload}" ]]
	[[ "${stderr_payload}" == *'"level":"WARN"'* ]]
}

@test "log_pretty returns original detail when JSON parsing fails" {
	run bash -lc '
                source ./src/lib/core/logging.sh

                VERBOSITY=1 log_pretty INFO "message" "{not-json" 2>&1
        '

	[ "$status" -eq 0 ]
	detail=$(jq -r '.detail' <<<"${output}")

	[[ "${detail}" == "{not-json" ]]
}

@test "log_pretty splits multiline string details" {
	run bash -lc '
                source ./src/lib/core/logging.sh

                detail=$'\''line1\nline2'\''
                VERBOSITY=1 log_pretty INFO "message" "${detail}" 2>&1
        '

	[ "$status" -eq 0 ]
	detail_type=$(jq -r '.detail | type' <<<"${output}")
	first_line=$(jq -r '.detail[0]' <<<"${output}")
	second_line=$(jq -r '.detail[1]' <<<"${output}")

	[[ "${detail_type}" == "array" ]]
	[[ "${first_line}" == "line1" ]]
	[[ "${second_line}" == "line2" ]]
}
