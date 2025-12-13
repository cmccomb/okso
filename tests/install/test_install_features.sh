#!/usr/bin/env bats
#
# Usage: bats tests/install/test_install_features.bats
#
# Environment variables:
#   OKSO_INSTALLER_SKIP_SELF_TEST (bool): skip installer self-test to speed tests.
#   OKSO_LINK_DIR (string): directory for the generated CLI symlink.
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes explicitly.

setup() {
	TEST_ROOT="${BATS_TMPDIR}/okso-install-feature"
	mkdir -p "${TEST_ROOT}" "${TEST_ROOT}/bin"
	if [ "$(uname -s)" != "Darwin" ]; then
		skip "Installer tests require macOS"
	fi
	export OKSO_INSTALLER_SKIP_SELF_TEST=true
	export OKSO_LINK_DIR="${TEST_ROOT}/bin"
}

teardown() {
	rm -rf "${TEST_ROOT}" 2>/dev/null || true
}

@test "supports dry-run without modifying filesystem" {
	run ./scripts/install.sh --dry-run --prefix "${TEST_ROOT}/prefix"

	[ "$status" -eq 0 ]
	[[ "$output" == *"Dry run enabled"* ]]
	[ ! -L "${OKSO_LINK_DIR}/okso" ]
}

@test "fails when Homebrew is unavailable" {
	local limited_path="/usr/bin:/bin"
	PATH="${limited_path}" run ./scripts/install.sh --prefix "${TEST_ROOT}/prefix"

	[ "$status" -eq 2 ]
	[[ "$output" == *"Homebrew is required"* ]]
}

@test "installs via Homebrew formula and links binary" {
	local install_dir="${TEST_ROOT}/brew-cellar"

	run ./scripts/install.sh --prefix "${install_dir}"

	[ "$status" -eq 0 ]
	[ -L "${OKSO_LINK_DIR}/okso" ]
	[ "$(readlink "${OKSO_LINK_DIR}/okso")" = "${install_dir}/bin/okso" ]
}
