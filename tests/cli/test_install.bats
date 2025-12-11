#!/usr/bin/env bats
#
# Usage: bats tests/cli/test_install.bats
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
#   Inherits Bats semantics; individual tests assert script exit codes.

setup() {
        TEST_ROOT="${BATS_TMPDIR}/okso-install"
        mkdir -p "${TEST_ROOT}"
        if [ "$(uname -s)" != "Darwin" ]; then
                skip "Installer tests require macOS"
        fi
        export DO_INSTALLER_ASSUME_OFFLINE=true
        export DO_INSTALLER_SKIP_SELF_TEST=true
        export DO_LINK_DIR="${TEST_ROOT}/bin"
        mkdir -p "${DO_LINK_DIR}"
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
	run bash -c "cat ./scripts/install.sh | DO_INSTALLER_ASSUME_OFFLINE=true bash -s -- --help"
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
        [ -L "${DO_LINK_DIR}/okso" ]
        [ "$(readlink "${DO_LINK_DIR}/okso")" = "${TEST_ROOT}/prefix/bin/okso" ]
        [[ "$output" == *"installer completed (install)"* ]]
}

@test "downloads project archive when sources are missing" {
        local remote_root="${TEST_ROOT}/remote"
        local bundle_dir="${TEST_ROOT}/bundle"
        local tarball="${bundle_dir}/okso.tar.gz"

        mkdir -p "${remote_root}/scripts" "${bundle_dir}" "${TEST_ROOT}/prefix"

        tar -czf "${tarball}" -C . src scripts README.md LICENSE

        cp scripts/install.sh "${remote_root}/scripts/install.sh"

        run env DO_INSTALLER_BASE_URL="file://${bundle_dir}" bash "${remote_root}/scripts/install.sh" --prefix "${TEST_ROOT}/prefix"
        [ "$status" -eq 0 ]
        [ -f "${TEST_ROOT}/prefix/bin/okso" ]
        [ -L "${DO_LINK_DIR}/okso" ]
}

@test "defaults to published installer base when downloading archive" {
        local remote_root="${TEST_ROOT}/remote"
        local bundle_dir="${TEST_ROOT}/bundle"
        local tarball="${bundle_dir}/okso.tar.gz"
        local log_path="${TEST_ROOT}/curl.log"

        mkdir -p "${remote_root}/scripts" "${bundle_dir}" "${TEST_ROOT}/prefix"

        tar -czf "${tarball}" -C . src scripts README.md LICENSE

        cp scripts/install.sh "${remote_root}/scripts/install.sh"

        cat >"${remote_root}/curl" <<EOM_CURL
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"${log_path}"
printf 'args:' >>"${log_path}"
for arg in "$@"; do
        printf ' %q' "$arg" >>"${log_path}"
done
printf '\n' >>"${log_path}"
dest=""
url=""
while [ $# -gt 0 ]; do
        case "$1" in
        -o)
                if [ $# -ge 2 ]; then
                        dest="$2"
                        shift 2
                        continue
                fi
                ;;
        http*|file*)
                url="$1"
                shift
                continue
                ;;
        esac
        shift
done

if [[ "${url}" == *".sha256" || "${url}" == *".asc" ]]; then
        exit 22
fi

if [ -n "${dest}" ]; then
        cp "${tarball}" "${dest}"
fi
EOM_CURL
        chmod +x "${remote_root}/curl"

        run env PATH="${remote_root}:${PATH}" DO_INSTALLER_ASSUME_OFFLINE=false bash "${remote_root}/scripts/install.sh" --prefix "${TEST_ROOT}/prefix"
        [ "$status" -eq 0 ]
        grep -q "okso.tar.gz" "${log_path}"
}
