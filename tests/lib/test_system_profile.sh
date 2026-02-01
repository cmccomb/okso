#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for system profile detection and autotuning.
#
# Usage:
#   bats tests/lib/test_system_profile.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+
#
# Exit codes:
#   Inherits Bats semantics; assertions gate failures.

@test "map_resources_to_base_tier respects github actions flag" {
	run bash -lc '
                set -euo pipefail
                source ./src/lib/settings/system_profile.sh
                printf "%s" "$(map_resources_to_base_tier 8589934592 1)"
        '
	[ "$status" -eq 0 ]
	[ "$output" = "ci" ]
}

@test "map_resources_to_base_tier maps memory sizes" {
	run bash -lc '
                set -euo pipefail
                source ./src/lib/settings/system_profile.sh
                printf "%s %s %s" \
                        "$(map_resources_to_base_tier $((8 * 1024 * 1024 * 1024)) 0)" \
                        "$(map_resources_to_base_tier $((16 * 1024 * 1024 * 1024)) 0)" \
                        "$(map_resources_to_base_tier $((48 * 1024 * 1024 * 1024)) 0)"
        '
	[ "$status" -eq 0 ]
	[ "$output" = "small default xlarge" ]
}

@test "map_tier_to_models returns expected sizes" {
	run bash -lc '
		set -euo pipefail
		source ./src/lib/settings/system_profile.sh

		out="$(map_tier_to_models default | paste -sd "|" -)"
		printf "%s" "$out"
	'
	[ "$status" -eq 0 ]
	[ "$output" = "1.7B|4B|8B" ]
}
