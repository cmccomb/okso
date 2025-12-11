#!/usr/bin/env bats
#
# Tests for render_box compatibility with older Bash versions.
#
# Usage:
#   bats tests/lib/test_render_box.sh
#
# Dependencies:
#   - bats
#   - bash 3+

@test "render_box works without mapfile builtin (Bash 3 compatibility)" {
	run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                enable -n mapfile 2>/dev/null || true
                source ./src/lib/formatting.sh
                render_box "Legacy compatibility"
        '
	[ "$status" -eq 0 ]
	[[ "${output}" == *"Legacy compatibility"* ]]
	[[ "${output}" == *"┌"* ]]
	[[ "${output}" == *"└"* ]]
}
