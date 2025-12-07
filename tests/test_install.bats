#!/usr/bin/env bats
#
# Usage: bats tests/test_install.bats
#
# Environment variables:
#   DO_INSTALLER_ASSUME_OFFLINE (bool): force offline mode to skip network calls.
#   DO_MODEL (string): HF repo[:file] identifier for the model download.
#   DO_MODEL_CACHE (string): directory where models are cached.
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
	export DO_MODEL="example/repo:demo.gguf"
	export DO_MODEL_CACHE="${TEST_ROOT}/models"
	export DO_LINK_DIR="${TEST_ROOT}/bin"
	mkdir -p "${DO_LINK_DIR}" "${DO_MODEL_CACHE}"
	printf "existing-model" >"${DO_MODEL_CACHE}/demo.gguf"
}

teardown() {
	rm -rf "${TEST_ROOT}" "${LLAMA_CALL_LOG:-}" 2>/dev/null || true
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

	run env PATH="${mock_path}:${PATH}" ./scripts/install --prefix "${TEST_ROOT}/prefix"
	[ "$status" -eq 0 ]
	[ -f "${TEST_ROOT}/prefix/main.sh" ]
	[ -L "${DO_LINK_DIR}/do" ]
	[ "$(readlink "${DO_LINK_DIR}/do")" = "${TEST_ROOT}/prefix/main.sh" ]
	[[ "$output" == *"installer completed (install)"* ]]
}

@test "offline mode skips llama download when cache present" {
	local mock_path="${TEST_ROOT}/mock-bin"
	mkdir -p "${mock_path}" "${TEST_ROOT}/prefix"

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

	run env PATH="${mock_path}:${PATH}" ./scripts/install --prefix "${TEST_ROOT}/prefix" --model-cache "${DO_MODEL_CACHE}"
	[ "$status" -eq 0 ]
	grep -q "existing-model" "${DO_MODEL_CACHE}/demo.gguf"
}

@test "downloads model via llama cpp when online" {
	local mock_path="${TEST_ROOT}/mock-bin"
	local log_path="${TEST_ROOT}/llama.log"
	mkdir -p "${mock_path}" "${TEST_ROOT}/prefix"
	rm -f "${DO_MODEL_CACHE}/demo.gguf"
	export DO_INSTALLER_ASSUME_OFFLINE=false
	export LLAMA_CALL_LOG="${log_path}"

	cp tests/fixtures/mock_llama_download.sh "${mock_path}/llama"
	cp tests/fixtures/mock_curl.sh "${mock_path}/curl"

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
	chmod +x "${mock_path}/llama" "${mock_path}/curl"

	run env PATH="${mock_path}:${PATH}" ./scripts/install --prefix "${TEST_ROOT}/prefix" --model "example/repo:demo.gguf" --model-branch main
	[ "$status" -eq 0 ]
	[ -f "${DO_MODEL_CACHE}/demo.gguf" ]
	grep -q "stub-model-body" "${DO_MODEL_CACHE}/demo.gguf"
	grep -q "example/repo demo.gguf main ${DO_MODEL_CACHE}/demo.gguf" "${log_path}"
}

@test "downloads project archive when sources are missing" {
	local mock_path="${TEST_ROOT}/mock-bin"
	local remote_root="${TEST_ROOT}/remote"
	local bundle_dir="${TEST_ROOT}/bundle"
	local tarball="${bundle_dir}/do.tar.gz"

	mkdir -p "${mock_path}" "${remote_root}/scripts" "${bundle_dir}" "${TEST_ROOT}/prefix"

	tar -czf "${tarball}" -C . src scripts README.md LICENSE

	cp scripts/install "${remote_root}/scripts/install"

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

	run env PATH="${mock_path}:${PATH}" DO_INSTALLER_BASE_URL="file://${bundle_dir}" bash "${remote_root}/scripts/install" --prefix "${TEST_ROOT}/prefix"
	[ "$status" -eq 0 ]
	[ -f "${TEST_ROOT}/prefix/main.sh" ]
	[ -L "${DO_LINK_DIR}/do" ]
}

@test "uninstall removes prefix and symlink" {
	local mock_path="${TEST_ROOT}/mock-bin"
	mkdir -p "${mock_path}" "${TEST_ROOT}/prefix" "${DO_LINK_DIR}"
	cat >"${mock_path}/uname" <<'EOM_UNAME'
#!/usr/bin/env bash
echo "Darwin"
EOM_UNAME
	chmod +x "${mock_path}/uname"
	cat >"${mock_path}/brew" <<'EOM_BREW'
#!/usr/bin/env bash
exit 0
EOM_BREW
	chmod +x "${mock_path}/brew"

	cp -R src/. "${TEST_ROOT}/prefix/"
	ln -s "${TEST_ROOT}/prefix/main.sh" "${DO_LINK_DIR}/do"

	run env PATH="${mock_path}:${PATH}" ./scripts/install --prefix "${TEST_ROOT}/prefix" --uninstall
	[ "$status" -eq 0 ]
	[ ! -e "${TEST_ROOT}/prefix/main.sh" ]
	[ ! -e "${DO_LINK_DIR}/do" ]
}
