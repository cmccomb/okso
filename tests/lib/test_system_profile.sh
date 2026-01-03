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
                source ./src/lib/system_profile.sh
                printf "%s" "$(map_resources_to_base_tier 8589934592 1)"
        '
	[ "$status" -eq 0 ]
	[ "$output" = "ci" ]
}

@test "cap_tier_for_pressure applies tier caps" {
	run bash -lc '
                set -euo pipefail
                source ./src/lib/system_profile.sh
                printf "%s %s %s" \
                        "$(cap_tier_for_pressure default critical comfortable)" \
                        "$(cap_tier_for_pressure large warning comfortable)" \
                        "$(cap_tier_for_pressure large normal tight)"
        '
	[ "$status" -eq 0 ]
	[ "$output" = "tiny small small" ]
}

@test "map_tier_to_models returns expected sizes" {
	run bash -lc '
		set -euo pipefail
		source ./src/lib/system_profile.sh

		out="$(map_tier_to_models default | paste -sd "|" -)"
		printf "%s" "$out"
	'
	[ "$status" -eq 0 ]
	[ "$output" = "1.7B|4B|8B" ]
}


@test "estimate_headroom_class classifies vm_stat output" {
	run bash -lc '
                set -euo pipefail
                tmp_dir="$(mktemp -d)"
                cat >"${tmp_dir}/vm_stat" <<"SCRIPT"
#!/usr/bin/env bash
cat "$(git rev-parse --show-toplevel)/tests/fixtures/vm_stat_comfortable.txt"
SCRIPT
                chmod +x "${tmp_dir}/vm_stat"
                PATH="${tmp_dir}:${PATH}"
                export DETECTED_PHYS_MEM_BYTES=8589934592
                source ./src/lib/system_profile.sh
                estimate_headroom_class
        '
	[ "$status" -eq 0 ]
	[ "$output" = "comfortable" ]
}

@test "estimate_headroom_class detects starved vm_stat output" {
	run bash -lc '
                set -euo pipefail
                tmp_dir="$(mktemp -d)"
                cat >"${tmp_dir}/vm_stat" <<"SCRIPT"
#!/usr/bin/env bash
cat "$(git rev-parse --show-toplevel)/tests/fixtures/vm_stat_starved.txt"
SCRIPT
                chmod +x "${tmp_dir}/vm_stat"
                PATH="${tmp_dir}:${PATH}"
                export DETECTED_PHYS_MEM_BYTES=8589934592
                source ./src/lib/system_profile.sh
                estimate_headroom_class
        '
	[ "$status" -eq 0 ]
	[ "$output" = "starved" ]
}
