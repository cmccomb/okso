#!/usr/bin/env bats
# shellcheck disable=SC2154
#
# Usage: bats tests/cli/test_install.bats
#
# Environment variables:
#   OKSO_INSTALLER_ASSUME_OFFLINE (bool): force offline mode to skip network calls.
#   OKSO_LINK_DIR (string): directory for the generated CLI symlink.
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

setup() {
	TEST_ROOT="${BATS_TMPDIR}/okso-install"
	mkdir -p "${TEST_ROOT}"
	if [ "$(uname -s)" != "Darwin" ]; then
		skip "Installer tests require macOS"
	fi
	export OKSO_INSTALLER_ASSUME_OFFLINE=true
	export OKSO_INSTALLER_SKIP_SELF_TEST=true
	export OKSO_LINK_DIR="${TEST_ROOT}/bin"
	mkdir -p "${OKSO_LINK_DIR}"
}

teardown() {
	rm -rf "${TEST_ROOT}" 2>/dev/null || true
}

@test "shows installer help" {
	run ./scripts/install.sh --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage: scripts/install.sh"* ]]
}

@test "reinvokes with bash when executed via sh" {
	run sh -c "./scripts/install.sh --help"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage: scripts/install.sh"* ]]
}

@test "supports stdin execution under bash" {
	run bash -c "cat ./scripts/install.sh | OKSO_INSTALLER_ASSUME_OFFLINE=true bash -s -- --help"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage: scripts/install.sh"* ]]
}

@test "fails fast on non-macOS" {
	local mock_path="${TEST_ROOT}/mock-non-mac"
	mkdir -p "${mock_path}"

	cat >"${mock_path}/uname" <<'EOM_UNAME'
#!/usr/bin/env bash
echo "Linux"
EOM_UNAME
	chmod +x "${mock_path}/uname"

	run env PATH="${mock_path}:${PATH}" ./scripts/install.sh --prefix "${TEST_ROOT}/prefix"
	[ "$status" -eq 3 ]
	[[ "$output" == *"supports macOS"* ]]
}

@test "installs when Homebrew is available" {
	run ./scripts/install.sh --prefix "${TEST_ROOT}/prefix"
	[ "$status" -eq 0 ]
	[ -f "${TEST_ROOT}/prefix/bin/okso" ]
	[ -L "${OKSO_LINK_DIR}/okso" ]
	[ "$(readlink "${OKSO_LINK_DIR}/okso")" = "${TEST_ROOT}/prefix/bin/okso" ]
	[[ "$output" == *"installer completed (install)"* ]]
}

@test "downloads project archive when sources are missing" {
	local remote_root="${TEST_ROOT}/remote"
	local bundle_dir="${TEST_ROOT}/bundle"
	local tarball="${bundle_dir}/okso.tar.gz"

	mkdir -p "${remote_root}/scripts" "${bundle_dir}" "${TEST_ROOT}/prefix"

	tar -czf "${tarball}" -C . src scripts README.md LICENSE

	cp scripts/install.sh "${remote_root}/scripts/install.sh"

	run env OKSO_INSTALLER_BASE_URL="file://${bundle_dir}" bash "${remote_root}/scripts/install.sh" --prefix "${TEST_ROOT}/prefix"
	[ "$status" -eq 0 ]
	[ -f "${TEST_ROOT}/prefix/bin/okso" ]
	[ -L "${OKSO_LINK_DIR}/okso" ]
}

@test "ignores legacy DO_* environment variables" {
        export DO_LINK_DIR="${TEST_ROOT}/legacy-bin"
        mkdir -p "${DO_LINK_DIR}" "${OKSO_LINK_DIR}"

        run env DO_INSTALLER_ASSUME_OFFLINE=true DO_INSTALLER_SKIP_SELF_TEST=true ./scripts/install.sh --prefix "${TEST_ROOT}/prefix"

        [ "$status" -eq 0 ]
        [ -L "${OKSO_LINK_DIR}/okso" ]
        [ ! -e "${DO_LINK_DIR}/okso" ]
}
