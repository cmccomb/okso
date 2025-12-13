#!/usr/bin/env bats
#
# Tests for MCP client registrations.
#
# Usage:
#   bats tests/tools/test_mcp.sh
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert MCP registration behavior.

setup() {
	REPO_ROOT="$(git rev-parse --show-toplevel)"
}

@test "register_mcp_endpoints registers both endpoints" {
	cd "${REPO_ROOT}" || exit 1
	run bash -lc '
                source ./src/tools/registry.sh
                source ./src/tools/mcp.sh
                TOOL_NAME_ALLOWLIST=(mcp_huggingface mcp_local_server)
                init_tool_registry
                register_mcp_endpoints
                [[ -n "$(tool_description mcp_huggingface)" ]] && [[ -n "$(tool_description mcp_local_server)" ]]
        '
	[ "$status" -eq 0 ]
}

@test "tool_mcp_huggingface fails when token missing" {
	cd "${REPO_ROOT}" || exit 1
	run bash -lc '
                source ./src/tools/mcp.sh
                MCP_HUGGINGFACE_URL="https://example.test/mcp"
                MCP_HUGGINGFACE_TOKEN_ENV="MCP_TOKEN"
                TOOL_QUERY="ping"
                tool_mcp_huggingface
        '
	[ "$status" -eq 1 ]
}

@test "tool_mcp_huggingface emits connection descriptor" {
	cd "${REPO_ROOT}" || exit 1
	run bash -lc '
                source ./src/tools/mcp.sh
                MCP_HUGGINGFACE_URL="https://example.test/mcp"
                MCP_HUGGINGFACE_TOKEN_ENV="MCP_TOKEN"
                MCP_TOKEN="secret"
                TOOL_QUERY="list tools"
                tool_mcp_huggingface
        '
	[ "$status" -eq 0 ]
	[[ "${output}" == *'"provider":"huggingface"'* ]]
	[[ "${output}" == *'"token_env":"MCP_TOKEN"'* ]]
}

@test "tool_mcp_local_server emits connection descriptor" {
	cd "${REPO_ROOT}" || exit 1
	expected_socket="${TMPDIR:-/tmp}/okso-mcp.sock"
	run bash -lc '
                source ./src/tools/mcp.sh
                MCP_LOCAL_SOCKET="${TMPDIR:-/tmp}/okso-mcp.sock"
                TOOL_QUERY="status"
                tool_mcp_local_server
        '
	[ "$status" -eq 0 ]
	[[ "${output}" == *"\"socket\":\"${expected_socket}\""* ]]
}
