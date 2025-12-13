#!/usr/bin/env bats
#
# Tests for configuration helpers.
#
# Usage:
#   bats tests/core/test_config.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert helper outcomes.

# shellcheck disable=SC1091,SC2030,SC2031,SC2034

setup() {
	REPO_ROOT="$(git rev-parse --show-toplevel)"
}

@test "parse_model_spec falls back to provided default file" {
	cd "${REPO_ROOT}" || exit 1
	source ./src/lib/config.sh
	mapfile -t parts < <(parse_model_spec "demo/model" "custom.gguf")
	[[ "${parts[0]}" == "demo/model" ]]
	[[ "${parts[1]}" == "custom.gguf" ]]
}

@test "normalize_approval_flags coerces invalid inputs" {
	cd "${REPO_ROOT}" || exit 1
	source ./src/lib/config.sh
	APPROVE_ALL="maybe"
	FORCE_CONFIRM="0"
	normalize_approval_flags
	[[ "${APPROVE_ALL}" == "false" ]]
	[[ "${FORCE_CONFIRM}" == "false" ]]
}

@test "init_environment disables llama when binary is missing" {
	cd "${REPO_ROOT}" || exit 1
	source ./src/lib/config.sh
	CONFIG_FILE="${BATS_TEST_TMPDIR}/config.env"
	MODEL_SPEC="demo/model"
	DEFAULT_MODEL_FILE="demo.gguf"
	NOTES_DIR="${BATS_TEST_TMPDIR}/notes"
	LLAMA_BIN="${BATS_TEST_TMPDIR}/missing"
	APPROVE_ALL=false
	FORCE_CONFIRM=false
	TESTING_PASSTHROUGH=false
	init_environment
	[[ "${LLAMA_AVAILABLE}" == "false" ]]
	[[ -d "${NOTES_DIR}" ]]
}

@test "load_config honors okso-branded overrides" {
	cd "${REPO_ROOT}" || exit 1
	source ./src/lib/config.sh
	CONFIG_FILE="${BATS_TEST_TMPDIR}/config.env"
	printf "MODEL_SPEC=base/model\nMODEL_BRANCH=dev\n" >"${CONFIG_FILE}"
	OKSO_MODEL="override/model" OKSO_MODEL_BRANCH="release" OKSO_VERBOSITY=2 load_config
	[[ "${MODEL_SPEC}" == "override/model" ]]
	[[ "${MODEL_BRANCH}" == "release" ]]
	[[ "${VERBOSITY}" == "2" ]]
}

@test "load_config ignores legacy DO_* variables" {
        cd "${REPO_ROOT}" || exit 1
        source ./src/lib/config.sh
        CONFIG_FILE="${BATS_TEST_TMPDIR}/config-legacy.env"
        printf "MODEL_SPEC=base/model\nMODEL_BRANCH=dev\n" >"${CONFIG_FILE}"
        DO_MODEL="legacy/model" DO_MODEL_BRANCH="legacy-branch" DO_VERBOSITY=0 DO_SUPERVISED=false load_config
        [[ "${MODEL_SPEC}" == "base/model" ]]
        [[ "${MODEL_BRANCH}" == "dev" ]]
        [[ "${VERBOSITY}" == "1" ]]
        [[ "${APPROVE_ALL}" == "false" ]]
}

@test "load_config wires default MCP settings" {
	cd "${REPO_ROOT}" || exit 1
	source ./src/lib/config.sh
	CONFIG_FILE="${BATS_TEST_TMPDIR}/config-mcp-defaults.env"
	: >"${CONFIG_FILE}"
	load_config
	[[ "${MCP_HUGGINGFACE_URL}" == "" ]]
	[[ "${MCP_HUGGINGFACE_TOKEN_ENV}" == "HUGGINGFACEHUB_API_TOKEN" ]]
	[[ "${MCP_LOCAL_SOCKET}" == "${TMPDIR:-/tmp}/okso-mcp.sock" ]]
}

@test "load_config honors MCP overrides" {
	cd "${REPO_ROOT}" || exit 1
	source ./src/lib/config.sh
	CONFIG_FILE="${BATS_TEST_TMPDIR}/config-mcp-overrides.env"
	cat >"${CONFIG_FILE}" <<'EOF'
MCP_HUGGINGFACE_URL="https://demo.example/mcp"
MCP_HUGGINGFACE_TOKEN_ENV="CUSTOM_TOKEN"
MCP_LOCAL_SOCKET="/var/run/okso.sock"
EOF
	load_config
	[[ "${MCP_HUGGINGFACE_URL}" == "https://demo.example/mcp" ]]
	[[ "${MCP_HUGGINGFACE_TOKEN_ENV}" == "CUSTOM_TOKEN" ]]
	[[ "${MCP_LOCAL_SOCKET}" == "/var/run/okso.sock" ]]
}
