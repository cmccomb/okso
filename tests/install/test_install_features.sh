#!/usr/bin/env bats
# shellcheck shell=bash

setup() {
	TEST_ROOT="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/okso-installer-XXXXXX")"
	INSTALLER_ROOT="${TEST_ROOT}/installer"
	PREFIX="${TEST_ROOT}/prefix"
	LINK_DIR="${TEST_ROOT}/links"
	MOCK_BIN="${TEST_ROOT}/mock-bin"

	mkdir -p "${INSTALLER_ROOT}/scripts" "${INSTALLER_ROOT}/src/bin" \
		"${INSTALLER_ROOT}/src/lib" "${INSTALLER_ROOT}/src/schemas" \
		"${MOCK_BIN}" "${LINK_DIR}"

	cp scripts/install.sh "${INSTALLER_ROOT}/scripts/install.sh"
	chmod +x "${INSTALLER_ROOT}/scripts/install.sh"
	: >"${INSTALLER_ROOT}/scripts/okso.rb"
	printf 'stub readme for installer tests' >"${INSTALLER_ROOT}/README.md"

	cat >"${INSTALLER_ROOT}/src/lib/schema.sh" <<'EOS'
#!/usr/bin/env bash
# shellcheck shell=bash
schema_path() {
        if [ "$1" = "planner_plan" ]; then
                printf "%s/schemas/planner_plan.schema.json\n" \
                        "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
        fi
}
EOS

	cat >"${INSTALLER_ROOT}/src/bin/okso" <<'EOS'
#!/usr/bin/env bash
# shellcheck shell=bash
printf 'Plan outline\n'
EOS
	chmod +x "${INSTALLER_ROOT}/src/bin/okso"
	printf '{"title": "planner schema"}' >"${INSTALLER_ROOT}/src/schemas/planner_plan.schema.json"

	cat >"${MOCK_BIN}/uname" <<'EOS'
#!/usr/bin/env bash
printf 'Darwin\n'
EOS
	chmod +x "${MOCK_BIN}/uname"

	cat >"${MOCK_BIN}/brew" <<'EOS'
#!/usr/bin/env bash
if [ "$1" = "--prefix" ]; then
        printf '/usr/local\n'
        exit 0
fi
if [ "$1" = "help" ]; then
        exit 0
fi
exit 0
EOS
	chmod +x "${MOCK_BIN}/brew"

	export PATH="${MOCK_BIN}:${PATH}"
}

teardown() {
	rm -rf "${TEST_ROOT}"
}

@test "uninstall removes symlink and prefix" {
	run env OKSO_LINK_DIR="${LINK_DIR}" OKSO_INSTALLER_SKIP_SELF_TEST=true \
		bash "${INSTALLER_ROOT}/scripts/install.sh" --prefix "${PREFIX}"

	[ "$status" -eq 0 ]
	[[ "$output" == *"installer completed (install)."* ]]
	[ -L "${LINK_DIR}/okso" ]
	[ "$(readlink "${LINK_DIR}/okso")" = "${PREFIX}/bin/okso" ]

	run env OKSO_LINK_DIR="${LINK_DIR}" bash "${INSTALLER_ROOT}/scripts/install.sh" \
		--prefix "${PREFIX}" --uninstall

	[ "$status" -eq 0 ]
	[[ "$output" == *"installer completed (uninstall)."* ]]
	[ ! -e "${LINK_DIR}/okso" ]
	[ ! -d "${PREFIX}" ]
}

@test "upgrade refreshes existing installation" {
	run env OKSO_LINK_DIR="${LINK_DIR}" OKSO_INSTALLER_SKIP_SELF_TEST=true \
		bash "${INSTALLER_ROOT}/scripts/install.sh" --prefix "${PREFIX}"

	[ "$status" -eq 0 ]
	[[ "$output" == *"installer completed (install)."* ]]
	initial_checksum="$(cksum "${PREFIX}/src/bin/okso" | awk '{print $1}')"

	run env OKSO_LINK_DIR="${LINK_DIR}" OKSO_INSTALLER_SKIP_SELF_TEST=true \
		bash "${INSTALLER_ROOT}/scripts/install.sh" --prefix "${PREFIX}" --upgrade

	[ "$status" -eq 0 ]
	[[ "$output" == *"installer completed (upgrade)."* ]]
	[ -L "${LINK_DIR}/okso" ]
	[ "$(readlink "${LINK_DIR}/okso")" = "${PREFIX}/bin/okso" ]
	upgraded_checksum="$(cksum "${PREFIX}/src/bin/okso" | awk '{print $1}')"
	[ "${initial_checksum}" = "${upgraded_checksum}" ]
}

@test "self-test runs when not skipped" {
	run env OKSO_LINK_DIR="${LINK_DIR}" OKSO_INSTALLER_SKIP_SELF_TEST=false \
		bash "${INSTALLER_ROOT}/scripts/install.sh" --prefix "${PREFIX}"

	[ "$status" -eq 0 ]
	[[ "$output" == *"Running installer self-test"* ]]
	[[ "$output" == *"Installer self-test passed"* ]]
	[ -L "${LINK_DIR}/okso" ]
	[ "$(readlink "${LINK_DIR}/okso")" = "${PREFIX}/bin/okso" ]
}
