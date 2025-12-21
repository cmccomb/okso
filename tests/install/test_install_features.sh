#!/usr/bin/env bats
# shellcheck shell=bash

setup() {
	TEST_ROOT="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/okso-installer-XXXXXX")"
	INSTALLER_ROOT="${TEST_ROOT}/installer"
	PREFIX="${TEST_ROOT}/prefix"
	LINK_DIR="${TEST_ROOT}/links"
	MOCK_BIN="${TEST_ROOT}/mock-bin"
	ORIGINAL_PATH="${PATH}"

	mkdir -p "${INSTALLER_ROOT}/scripts" "${INSTALLER_ROOT}/src/bin" \
		"${INSTALLER_ROOT}/src/lib/schema" "${INSTALLER_ROOT}/src/schemas" \
		"${MOCK_BIN}" "${LINK_DIR}"

	cp scripts/install.sh "${INSTALLER_ROOT}/scripts/install.sh"
	chmod +x "${INSTALLER_ROOT}/scripts/install.sh"
	: >"${INSTALLER_ROOT}/scripts/okso.rb"
	printf 'stub readme for installer tests' >"${INSTALLER_ROOT}/README.md"

	cat >"${INSTALLER_ROOT}/src/lib/schema/schema.sh" <<'EOS'
#!/usr/bin/env bash
# shellcheck shell=bash
schema_path() {
        if [ "$1" = "planner_plan" ]; then
                printf "%s/schemas/planner_plan.schema.json\n" \
                        "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
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
	hash -r
}

teardown() {
	PATH="${ORIGINAL_PATH}"
	hash -r
	rm -rf "${TEST_ROOT}"
}

@test "uninstall removes symlink and prefix" {
	run env PATH="${MOCK_BIN}:${PATH}" OKSO_LINK_DIR="${LINK_DIR}" \
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
	run env OKSO_LINK_DIR="${LINK_DIR}" \
		bash "${INSTALLER_ROOT}/scripts/install.sh" --prefix "${PREFIX}"

	[ "$status" -eq 0 ]
	[[ "$output" == *"installer completed (install)."* ]]
	initial_checksum="$(cksum "${PREFIX}/src/bin/okso" | awk '{print $1}')"

	run env OKSO_LINK_DIR="${LINK_DIR}" \
		bash "${INSTALLER_ROOT}/scripts/install.sh" --prefix "${PREFIX}" --upgrade

	[ "$status" -eq 0 ]
	[[ "$output" == *"installer completed (upgrade)."* ]]
	[ -L "${LINK_DIR}/okso" ]
	[ "$(readlink "${LINK_DIR}/okso")" = "${PREFIX}/bin/okso" ]
	upgraded_checksum="$(cksum "${PREFIX}/src/bin/okso" | awk '{print $1}')"
	[ "${initial_checksum}" = "${upgraded_checksum}" ]
}

@test "uninstall fails when Homebrew uninstall errors" {
	cat >"${MOCK_BIN}/brew" <<'EOS'
#!/usr/bin/env bash
if [ "$1" = "list" ]; then
        printf 'okso 1.0\n'
        exit 0
fi
if [ "$1" = "help" ]; then
        exit 0
fi
if [ "$1" = "uninstall" ]; then
        printf 'brew uninstall failed\n' >&2
        exit 3
fi
exit 0
EOS
	chmod +x "${MOCK_BIN}/brew"

	hash -r

	run env PATH="${MOCK_BIN}:${PATH}" OKSO_LINK_DIR="${LINK_DIR}" \
		bash "${INSTALLER_ROOT}/scripts/install.sh" --prefix "${PREFIX}" --uninstall

	[ "$status" -ne 0 ]
	[[ "$output" == *"Failed to uninstall okso with Homebrew."* ]]
}

@test "uninstall fails when install prefix cannot be removed" {
	run env PATH="${MOCK_BIN}:${PATH}" OKSO_LINK_DIR="${LINK_DIR}" \
		bash "${INSTALLER_ROOT}/scripts/install.sh" --prefix "${PREFIX}"

	cat >"${MOCK_BIN}/rm" <<EOS
#!/usr/bin/env bash
PREFIX_PATH="${PREFIX}"
if [ "\$#" -eq 0 ]; then
        exit 0
fi
printf 'rm args: %s\n' "\$*" >&2
case "\$*" in
*"\${PREFIX_PATH}"*)
        printf 'rm failed intentionally for %s\n' "\$*" >&2
        exit 1
        ;;
*)
        exec /bin/rm "\$@"
        ;;
esac
EOS
	chmod +x "${MOCK_BIN}/rm"

	cat >"${MOCK_BIN}/sudo" <<'EOS'
#!/usr/bin/env bash
        printf 'sudo unavailable for test\n' >&2
exit 1
EOS
	chmod +x "${MOCK_BIN}/sudo"

	hash -r

	run env PATH="${MOCK_BIN}:${PATH}" OKSO_LINK_DIR="${LINK_DIR}" RM_BIN="${MOCK_BIN}/rm" \
		bash "${INSTALLER_ROOT}/scripts/install.sh" --prefix "${PREFIX}" --uninstall

	[ "$status" -ne 0 ]
	[[ "$output" == *"Failed to remove ${PREFIX}"* ]]
	hash -r
}
