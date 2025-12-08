#!/usr/bin/env bats
#
# Usage: bats tests/install/test_install_features.bats
#
# Environment variables:
#   DO_INSTALLER_ASSUME_OFFLINE (bool): force offline mode to skip network calls.
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
        mkdir -p "${TEST_ROOT}"
        export DO_INSTALLER_ASSUME_OFFLINE=true
        export DO_LINK_DIR="${TEST_ROOT}/bin"
        mkdir -p "${DO_LINK_DIR}"
}

teardown() {
        rm -rf "${TEST_ROOT}" 2>/dev/null || true
}

create_mock_macos_tools() {
        local mock_path="$1"
        mkdir -p "${mock_path}" "$2"

        cat >"${mock_path}/uname" <<'EOM_UNAME'
#!/usr/bin/env bash
echo "Darwin"
EOM_UNAME
        chmod +x "${mock_path}/uname"

        cat >"${mock_path}/brew" <<'EOM_BREW'
#!/usr/bin/env bash
if [ "$1" = "list" ]; then
        exit 0
fi
if [ "$1" = "install" ]; then
        exit 0
fi
command -v "$1" >/dev/null 2>&1
EOM_BREW
        chmod +x "${mock_path}/brew"
}

@test "supports dry-run without modifying filesystem" {
        local prefix="${TEST_ROOT}/prefix-dry"

        run ./scripts/install.sh --prefix "${prefix}" --dry-run

        [ "$status" -eq 0 ]
        [[ "$output" == *"Dry run enabled"* ]]
        [ ! -d "${prefix}" ]
        [ ! -L "${DO_LINK_DIR}/okso" ]
}

@test "fails when archive checksum mismatches" {
        local mock_path="${TEST_ROOT}/mock-bin"
        local remote_root="${TEST_ROOT}/remote"
        local bundle_dir="${TEST_ROOT}/bundle"
        local tarball="${bundle_dir}/okso.tar.gz"
        local checksum_file="${tarball}.sha256"

        mkdir -p "${mock_path}" "${remote_root}/scripts" "${bundle_dir}" "${TEST_ROOT}/prefix"

        tar -czf "${tarball}" -C . src scripts README.md LICENSE
        printf '%s\n' "deadbeef" >"${checksum_file}"

        cp scripts/install.sh "${remote_root}/scripts/install.sh"
        create_mock_macos_tools "${mock_path}" "${TEST_ROOT}/prefix"

        run env PATH="${mock_path}:${PATH}" DO_INSTALLER_BASE_URL="file://${bundle_dir}" bash "${remote_root}/scripts/install.sh" --prefix "${TEST_ROOT}/prefix"

        [ "$status" -eq 2 ]
        [[ "$output" == *"Checksum file invalid or malformed"* ]]
}

@test "runs installer self-test after install" {
        local mock_path="${TEST_ROOT}/mock-bin"

        mkdir -p "${TEST_ROOT}/prefix"
        create_mock_macos_tools "${mock_path}" "${TEST_ROOT}/prefix"

        run env PATH="${mock_path}:${PATH}" ./scripts/install.sh --prefix "${TEST_ROOT}/prefix"

        [ "$status" -eq 0 ]
        [[ "$output" == *"Installer self-test passed"* ]]
        [[ "$output" == *"Running installer self-test"* ]]
}
