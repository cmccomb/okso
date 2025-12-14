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

@test "tool_mcp_remote fails when token missing" {
	cd "${REPO_ROOT}" || exit 1
	run bash -lc '
                MCP_SKIP_USAGE_DISCOVERY=true
                source ./src/tools/registry.sh
                source ./src/tools/mcp.sh
                TOOL_NAME_ALLOWLIST=(mcp_remote_demo)
                init_tool_registry
                MCP_ENDPOINTS_JSON='"'"'[{"name":"mcp_remote_demo","provider":"demo","description":"Demo","usage":"","safety":"Token required","transport":"http","endpoint":"https://example.test/mcp","token_env":"MCP_TOKEN"}]'"'"'
                register_mcp_endpoints
                TOOL_QUERY="ping"
                tool_mcp_remote_demo
        '
	[ "$status" -eq 1 ]
}

@test "tool_mcp_remote emits connection descriptor" {
	cd "${REPO_ROOT}" || exit 1
	run bash -lc '
                MCP_SKIP_USAGE_DISCOVERY=true
                source ./src/tools/registry.sh
                source ./src/tools/mcp.sh
                TOOL_NAME_ALLOWLIST=(mcp_remote_demo)
                init_tool_registry
                MCP_ENDPOINTS_JSON='"'"'[{"name":"mcp_remote_demo","provider":"demo","description":"Demo","usage":"","safety":"Token required","transport":"http","endpoint":"https://example.test/mcp","token_env":"MCP_TOKEN"}]'"'"'
                MCP_TOKEN="secret"
                register_mcp_endpoints
                TOOL_QUERY="list tools"
                tool_mcp_remote_demo
        '
	[ "$status" -eq 0 ]
	[[ "${output}" == *'"provider":"demo"'* ]]
	[[ "${output}" == *'"token_env":"MCP_TOKEN"'* ]]
}

@test "register_mcp_endpoints is a no-op when no endpoints configured" {
	cd "${REPO_ROOT}" || exit 1
	run bash -lc '
                MCP_SKIP_USAGE_DISCOVERY=true
                source ./src/tools/registry.sh
                source ./src/tools/mcp.sh
                TOOL_NAME_ALLOWLIST=()
                init_tool_registry
                register_mcp_endpoints
                [[ -z "$(compgen -A function | grep "^tool_mcp")" ]]
        '
	[ "$status" -eq 0 ]
}

@test "tool_mcp_local_server emits connection descriptor when configured" {
	cd "${REPO_ROOT}" || exit 1
	expected_socket="${TMPDIR:-/tmp}/okso-mcp.sock"
	run bash -lc '
                source ./src/tools/registry.sh
                source ./src/tools/mcp.sh
                TOOL_NAME_ALLOWLIST=(mcp_local_server)
                MCP_ENDPOINTS_JSON=$(printf '"'"'[{"name":"mcp_local_server","provider":"local_demo","description":"Connect over local socket","usage":"","safety":"Uses unix socket","transport":"unix","socket":"%s"}]'"'"' "${TMPDIR:-/tmp}/okso-mcp.sock")
                init_tool_registry
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
                MCP_SKIP_USAGE_DISCOVERY=true
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

@test "register_mcp_endpoints merges allowlist implicitly" {
        cd "${REPO_ROOT}" || exit 1
        run bash -lc '
                MCP_SKIP_USAGE_DISCOVERY=true
                source ./src/tools/registry.sh
                source ./src/tools/mcp.sh
                TOOL_NAME_ALLOWLIST=(terminal)
                MCP_ENDPOINTS_JSON='"'"'[
                        {
                                "name": "automerge_mcp",
                                "provider": "demo",
                                "description": "Auto-merged MCP endpoint",
                                "usage": "automerge_mcp <query>",
                                "safety": "Token required",
                                "transport": "http",
                                "endpoint": "https://example.test/mcp",
                                "token_env": "AUTOMERGE_TOKEN"
                        }
                ]'"'"'

                AUTOMERGE_TOKEN=token
                init_tool_registry
                register_mcp_endpoints
                TOOL_QUERY="health"
                tool_automerge_mcp
        '

        [ "$status" -eq 0 ]
        [[ "${output}" == *"\"provider\":\"demo\""* ]]
        [[ "${output}" != *"tool name not in allowlist"* ]]
}

@test "register_mcp_endpoints infers usage when missing" {
        cd "${REPO_ROOT}" || exit 1
        run bash -lc '
                set -e
                MCP_SKIP_USAGE_DISCOVERY=false
                source ./src/tools/registry.sh
                source ./src/tools/mcp.sh

                PORT_FILE="${BATS_TEST_TMPDIR}/mcp-tools-port"
                export PORT_FILE
                python3 - <<'PY' &
import http.server
import json
import os
import socketserver


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/tools"):
            body = json.dumps({"tools": [{"name": "echo", "description": "Echo input"}]})
            encoded = body.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, *_: object) -> None:  # pragma: no cover - silence test server
        return


with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    port = httpd.server_address[1]
    with open(os.environ["PORT_FILE"], "w", encoding="utf-8") as handle:
        handle.write(str(port))
    httpd.serve_forever()
PY
                server_pid=$!
                trap "kill ${server_pid}" EXIT

                attempts=0
                while [[ ! -f "${PORT_FILE}" && ${attempts} -lt 50 ]]; do
                        sleep 0.1
                        attempts=$((attempts + 1))
                done

                if [[ ! -f "${PORT_FILE}" ]]; then
                        echo "tool listing server failed to start" >&2
                        exit 1
                fi

                MCP_PORT=$(cat "${PORT_FILE}")

                TOOL_NAME_ALLOWLIST=(mcp_demo_http)
                MCP_ENDPOINTS_JSON="[{\"name\":\"mcp_demo_http\",\"provider\":\"demo\",\"description\":\"Demo MCP\",\"safety\":\"Token required\",\"transport\":\"http\",\"endpoint\":\"http://127.0.0.1:${MCP_PORT}\",\"token_env\":\"DEMO_TOKEN\"}]"
                DEMO_TOKEN=dummy

                init_tool_registry
                register_mcp_endpoints

                inferred_usage="$(tool_command mcp_demo_http)"
                [[ "${inferred_usage}" == *"Available tools"* ]]
        '
	[ "$status" -eq 0 ]
}

@test "register_mcp_endpoints fails for invalid configuration" {
	cd "${REPO_ROOT}" || exit 1
	run bash -lc '
                MCP_SKIP_USAGE_DISCOVERY=true
                source ./src/tools/registry.sh
                source ./src/tools/mcp.sh
                TOOL_NAME_ALLOWLIST=(broken_entry)
                MCP_ENDPOINTS_JSON='"'"'[{"name": "broken_entry", "provider": "bad", "description": "Bad", "usage": "bad <q>", "safety": "Check credentials", "transport": "http", "endpoint": "https://example.test/mcp"}]'"'"'
                init_tool_registry
                register_mcp_endpoints
        '
	[ "$status" -eq 1 ]
	[[ "${output}" == *"token_env missing"* ]]
}

@test "merge_tool_allowlist_with_mcp extends allowlist prior to registry setup" {
	cd "${REPO_ROOT}" || exit 1
	run bash -lc '
                MCP_SKIP_USAGE_DISCOVERY=true
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
