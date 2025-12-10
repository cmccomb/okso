#!/usr/bin/env bats
#
# Usage: bats tests/install/test_install_features.bats
#
# Environment variables:
#   DO_INSTALLER_SKIP_SELF_TEST (bool): skip installer self-test to speed tests.
#   DO_LINK_DIR (string): directory for the generated CLI symlink.
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
	export DO_INSTALLER_SKIP_SELF_TEST=true
	export DO_LINK_DIR="${TEST_ROOT}/bin"
}

teardown() {
	rm -rf "${TEST_ROOT}" 2>/dev/null || true
}

create_mock_macos_tools() {
	local mock_path="$1"
	mkdir -p "${mock_path}"

	cat >"${mock_path}/uname" <<'EOM_UNAME'
#!/usr/bin/env bash
echo "Darwin"
EOM_UNAME
	chmod +x "${mock_path}/uname"
}

create_mock_brew() {
	local mock_path="$1"
	local install_dir="$2"
	mkdir -p "${mock_path}" "${install_dir}/src/bin" "${install_dir}/grammars" "${install_dir}/lib"

	cp src/bin/okso "${install_dir}/src/bin/okso"
	cp -R src/grammars/* "${install_dir}/grammars/"
	cp src/lib/grammar.sh "${install_dir}/lib/grammar.sh"

	cat >"${mock_path}/brew" <<'EOM_BREW'
#!/usr/bin/env bash
if [ "$1" = "install" ]; then
        exit 0
fi
if [ "$1" = "uninstall" ]; then
        rm -rf "$INSTALL_DIR"
        exit 0
fi
if [ "$1" = "--prefix" ] || [ "$1" = "prefix" ]; then
        if [ "$2" = "okso" ]; then
                printf '%s\n' "$INSTALL_DIR"
                exit 0
        fi
fi
exit 0
EOM_BREW
	sed -i "1iINSTALL_DIR=${install_dir}" "${mock_path}/brew"
	chmod +x "${mock_path}/brew"
}

@test "supports dry-run without modifying filesystem" {
	local mock_path="${TEST_ROOT}/mock-bin"
	create_mock_macos_tools "${mock_path}"
	PATH="${mock_path}:${PATH}" run ./scripts/install.sh --dry-run

	[ "$status" -eq 0 ]
	[[ "$output" == *"Dry run enabled"* ]]
	[ ! -L "${DO_LINK_DIR}/okso" ]
}

@test "fails when Homebrew is unavailable" {
	local mock_path="${TEST_ROOT}/mock-bin"
	create_mock_macos_tools "${mock_path}"
	PATH="${mock_path}:${PATH}" run ./scripts/install.sh

	[ "$status" -eq 2 ]
	[[ "$output" == *"Homebrew is required"* ]]
}

@test "installs via Homebrew formula and links binary" {
	local mock_path="${TEST_ROOT}/mock-bin"
	local install_dir="${TEST_ROOT}/brew-cellar"

	create_mock_macos_tools "${mock_path}"
	create_mock_brew "${mock_path}" "${install_dir}"

	PATH="${mock_path}:${PATH}" run ./scripts/install.sh

	[ "$status" -eq 0 ]
	[ -L "${DO_LINK_DIR}/okso" ]
	[ "$(readlink "${DO_LINK_DIR}/okso")" = "${install_dir}/src/bin/okso" ]
}
