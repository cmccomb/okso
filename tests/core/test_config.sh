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

@test "load_config applies okso-branded supervised toggle" {
	cd "${REPO_ROOT}" || exit 1
	source ./src/lib/config.sh
	CONFIG_FILE="${BATS_TEST_TMPDIR}/config-supervised.env"
	printf "MODEL_SPEC=base/model\nMODEL_BRANCH=dev\nAPPROVE_ALL=true\n" >"${CONFIG_FILE}"
	OKSO_SUPERVISED=false load_config
	[[ "${MODEL_SPEC}" == "base/model" ]]
	[[ "${MODEL_BRANCH}" == "dev" ]]
	[[ "${APPROVE_ALL}" == "true" ]]
	[[ "${FORCE_CONFIRM}" == "false" ]]
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
	[[ "${MCP_ENDPOINTS_ALLOW_PARTIAL_DEFAULT}" == "true" ]]
	[[ "${MCP_ENDPOINTS_TOML}" == *"mcp_local_server"* ]]
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

@test "load_config builds MCP endpoint JSON from TOML" {
	cd "${REPO_ROOT}" || exit 1
	source ./src/lib/config.sh
	CONFIG_FILE="${BATS_TEST_TMPDIR}/config-mcp-toml.env"
	cat >"${CONFIG_FILE}" <<'EOF'
MCP_ENDPOINTS_TOML=$(cat <<'EOF_MCP'
[[mcp.endpoints]]
name = "custom_http"
provider = "alpha"
description = "Custom HTTP endpoint"
usage = "custom_http <query>"
safety = "Use the provided token"
transport = "http"
endpoint = "https://example.test/http"
token_env = "CUSTOM_HTTP_TOKEN"
EOF_MCP
)
EOF

	load_config

	[[ "${MCP_ENDPOINTS_ALLOW_PARTIAL_DEFAULT}" == "false" ]]
	custom_endpoint=$(
		MCP_ENDPOINTS_JSON="${MCP_ENDPOINTS_JSON}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["MCP_ENDPOINTS_JSON"])
print(payload[0]["name"], payload[0]["token_env"])
PY
	)
	[[ "${custom_endpoint}" == "custom_http CUSTOM_HTTP_TOKEN" ]]
}

@test "write_config_file persists structured MCP configuration" {
	cd "${REPO_ROOT}" || exit 1
	source ./src/lib/config.sh
	CONFIG_FILE="${BATS_TEST_TMPDIR}/config-roundtrip.env"
	load_config
	write_config_file

	run env CONFIG_FILE="${CONFIG_FILE}" bash -lc '
                source ./src/lib/config.sh
                load_config
                [[ "${MCP_ENDPOINTS_TOML}" == *"mcp_huggingface_models"* ]]
                [[ "${MCP_ENDPOINTS_ALLOW_PARTIAL_DEFAULT}" == "true" ]]
        '

	[ "$status" -eq 0 ]
}
