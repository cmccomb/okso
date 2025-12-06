#!/usr/bin/env bats
#
# Usage: bats tests/test_install.bats
#
# Environment variables:
#   DO_INSTALLER_ASSUME_OFFLINE (bool): force offline mode to skip network calls.
#   DO_MODEL_PATH (string): destination for model download; tests override with a
#       temporary file to avoid network access.
#   DO_LINK_DIR (string): directory for the generated CLI symlink.
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes.

setup() {
	TEST_ROOT="${BATS_TMPDIR}/do-install"
	mkdir -p "${TEST_ROOT}"
	export DO_INSTALLER_ASSUME_OFFLINE=true
	export DO_MODEL_PATH="${TEST_ROOT}/models/qwen3-1.5b-instruct-q4_k_m.gguf"
	export DO_LINK_DIR="${TEST_ROOT}/bin"
	mkdir -p "${DO_LINK_DIR}" "$(dirname "${DO_MODEL_PATH}")"
	printf "stub" >"${DO_MODEL_PATH}"
}

teardown() {
	rm -rf "${TEST_ROOT}"
}

@test "shows installer help" {
	run ./scripts/install --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage: scripts/install"* ]]
}

@test "fails fast on non-macOS" {
	run ./scripts/install --prefix "${TEST_ROOT}/prefix"
	[ "$status" -eq 3 ]
	[[ "$output" == *"supports macOS"* ]]
}

@test "installs with mocked brew on macOS" {
	local mock_path="${TEST_ROOT}/mock-bin"
	mkdir -p "${mock_path}" "${TEST_ROOT}/prefix"

	cat >"${mock_path}/uname" <<'EOF'
#!/usr/bin/env bash
echo "Darwin"
EOF
	chmod +x "${mock_path}/uname"

	cat >"${mock_path}/brew" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "list" ]; then
        exit 0
fi
if [ "$1" = "install" ]; then
        exit 0
fi
command -v "$1" >/dev/null 2>&1
EOF
	chmod +x "${mock_path}/brew"

	run env PATH="${mock_path}:${PATH}" ./scripts/install --prefix "${TEST_ROOT}/prefix"
	[ "$status" -eq 0 ]
	[ -f "${TEST_ROOT}/prefix/main.sh" ]
	[ -L "${DO_LINK_DIR}/do" ]
	[ "$(readlink "${DO_LINK_DIR}/do")" = "${TEST_ROOT}/prefix/main.sh" ]
	[[ "$output" == *"installer completed (install)"* ]]
}

@test "uninstall removes prefix and symlink" {
	local mock_path="${TEST_ROOT}/mock-bin"
	mkdir -p "${mock_path}" "${TEST_ROOT}/prefix" "${DO_LINK_DIR}"
	cat >"${mock_path}/uname" <<'EOF'
#!/usr/bin/env bash
echo "Darwin"
EOF
	chmod +x "${mock_path}/uname"
	cat >"${mock_path}/brew" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "${mock_path}/brew"

	cp -R src/. "${TEST_ROOT}/prefix/"
	ln -s "${TEST_ROOT}/prefix/main.sh" "${DO_LINK_DIR}/do"

	run env PATH="${mock_path}:${PATH}" ./scripts/install --prefix "${TEST_ROOT}/prefix" --uninstall
	[ "$status" -eq 0 ]
	[ ! -e "${TEST_ROOT}/prefix/main.sh" ]
	[ ! -e "${DO_LINK_DIR}/do" ]
}
