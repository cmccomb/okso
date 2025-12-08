#!/usr/bin/env bats
#
# Security regression tests for sanitization and allowlists.
#
# Usage: bats tests/test_security.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

@test "osascript helpers reject shell substitution attempts" {
	run bash -lc '
                VERBOSITY=1
                source ./src/tools/osascript_helpers.sh
                malicious=$'"'"'display dialog `whoami`'"'"'
                sanitize_osascript_arguments "${malicious}"
        '

	[ "$status" -eq 1 ]
	[ "$(echo "${output}" | jq -r '.message')" = "osascript arguments may not include shell substitution" ]
}

@test "initialize_tools fails when writable directory leaves allowlist" {
	run bash -lc '
                VERBOSITY=1
                NOTES_DIR="/tmp/okso/../../etc"
                source ./src/tools.sh
                initialize_tools
        '

	[ "$status" -eq 1 ]
	[ "$(echo "${output}" | jq -r '.message')" = "Writable directory not allowed" ]
}
