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

@test "register_mcp_endpoints registers default endpoints" {
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
                source ./src/tools/registry.sh
                source ./src/tools/mcp.sh
                TOOL_NAME_ALLOWLIST=(mcp_huggingface mcp_local_server)
                init_tool_registry
                MCP_HUGGINGFACE_URL="https://example.test/mcp"
                MCP_HUGGINGFACE_TOKEN_ENV="MCP_TOKEN"
                register_mcp_endpoints
                TOOL_QUERY="ping"
                tool_mcp_huggingface
        '
	[ "$status" -eq 1 ]
}

@test "tool_mcp_huggingface emits connection descriptor" {
	cd "${REPO_ROOT}" || exit 1
	run bash -lc '
                source ./src/tools/registry.sh
                source ./src/tools/mcp.sh
                TOOL_NAME_ALLOWLIST=(mcp_huggingface mcp_local_server)
                init_tool_registry
                MCP_HUGGINGFACE_URL="https://example.test/mcp"
                MCP_HUGGINGFACE_TOKEN_ENV="MCP_TOKEN"
                MCP_TOKEN="secret"
                register_mcp_endpoints
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
                source ./src/tools/registry.sh
                source ./src/tools/mcp.sh
                TOOL_NAME_ALLOWLIST=(mcp_huggingface mcp_local_server)
                init_tool_registry
                MCP_LOCAL_SOCKET="${TMPDIR:-/tmp}/okso-mcp.sock"
                register_mcp_endpoints
                TOOL_QUERY="status"
                tool_mcp_local_server
        '
	[ "$status" -eq 0 ]
	[[ "${output}" == *"\"socket\":\"${expected_socket}\""* ]]
}

@test "register_mcp_endpoints honors MCP_ENDPOINTS_JSON" {
	cd "${REPO_ROOT}" || exit 1
        run bash -lc '
                source ./src/lib/tools.sh
                TOOL_NAME_ALLOWLIST=(terminal)
                MCP_ENDPOINTS_JSON='"'"'[
                        {
                                "name": "custom_http",
                                "provider": "alpha",
                                "description": "Custom HTTP endpoint",
                                "usage": "custom_http <query>",
                                "safety": "Do not log secrets",
                                "transport": "http",
                                "endpoint": "https://example.test/http",
                                "token_env": "CUSTOM_TOKEN"
                        },
                        {
                                "name": "custom_unix",
                                "provider": "beta",
                                "description": "Custom unix endpoint",
                                "usage": "custom_unix <query>",
                                "safety": "Local socket only",
                                "transport": "unix",
                                "socket": "/tmp/custom.sock"
                        }
                ]'"'"'

                merge_tool_allowlist_with_mcp
                init_tool_registry
                register_mcp_endpoints
                CUSTOM_TOKEN="token"
                TOOL_QUERY="hello"
                tool_custom_http
                tool_custom_unix
                [[ "$(tool_description custom_http)" == "Custom HTTP endpoint" ]]
                [[ "$(tool_description custom_unix)" == "Custom unix endpoint" ]]
        '
	[ "$status" -eq 0 ]
}

@test "register_mcp_endpoints fails for invalid configuration" {
	cd "${REPO_ROOT}" || exit 1
        run bash -lc '
                source ./src/tools/registry.sh
                source ./src/tools/mcp.sh
                TOOL_NAME_ALLOWLIST=(broken_entry)
                MCP_ENDPOINTS_JSON='"'"'[{"name": "broken_entry", "provider": "bad", "description": "Bad", "usage": "bad <q>", "safety": "", "transport": "http"}]'"'"'
                init_tool_registry
                register_mcp_endpoints
        '
        [ "$status" -eq 1 ]
        [[ "${output}" == *"missing fields"* ]]
}

@test "merge_tool_allowlist_with_mcp extends allowlist prior to registry setup" {
        cd "${REPO_ROOT}" || exit 1
        run bash -lc '
                source ./src/lib/tools.sh
                TOOL_NAME_ALLOWLIST=(terminal)
                MCP_ENDPOINTS_JSON='"'"'[
                        {
                                "name": "mcp_extension",
                                "provider": "demo",
                                "description": "Extension endpoint",
                                "usage": "mcp_extension <query>",
                                "safety": "Check credentials before use",
                                "transport": "http",
                                "endpoint": "https://example.test/mcp",
                                "token_env": "EXT_TOKEN"
                        }
                ]'"'"'

                merge_tool_allowlist_with_mcp
                [[ " ${TOOL_NAME_ALLOWLIST[*]} " == *" mcp_extension "* ]]
                init_tool_registry
                register_mcp_endpoints
                EXT_TOKEN="token"
                TOOL_QUERY="status"
                tool_mcp_extension
        '
        [ "$status" -eq 0 ]
}
