#!/usr/bin/env bats
#
# MCP adapter and client tests.
#
# Usage: bats tests/test_mcp.bats
#
# Dependencies:
#   - bats
#   - jq

@test "local registry surfaces MCP descriptors" {
        run bash -lc '
                source ./src/mcp.sh
                VERBOSITY=0
                init_tool_registry
                initialize_tools
                descriptors=$(mcp_local_tool_descriptors)
                echo "${descriptors}" | jq -r ".[0].name"
                echo "${descriptors}" | jq -r ".[0].input_schema.properties.query.description"
        '

        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "terminal" ]
        [[ "${lines[1]}" == "Value assigned to TOOL_QUERY"* ]]
}

@test "mcp runtime catalog merges remote endpoint" {
        run bash -lc '
                source ./src/runtime.sh
                VERBOSITY=0
                MCP_ENDPOINT="./src/tools/external/mcp_echo.sh"
                init_tool_registry
                initialize_tools
                catalog=$(mcp_build_runtime_catalog)
                echo "${catalog}" | jq -r ".[-1].name"
                echo "${catalog}" | jq -r "length"
        '

        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "echo_external" ]
        [ "${lines[1]}" -ge 23 ]
}

@test "mcp client exercises external endpoint" {
        run bash -lc '
                source ./src/mcp.sh
                endpoint="./src/tools/external/mcp_echo.sh"
                tools=$(mcp_client_list_tools "${endpoint}")
                echo "${tools}" | jq -r ".[0].name"
                descriptor=$(mcp_client_describe_tool "${endpoint}" "echo_external")
                echo "${descriptor}" | jq -r ".name"
                result=$(mcp_client_call_tool "${endpoint}" "echo_external" "{\"message\":\"hi\"}")
                echo "${result}" | jq -r ".result.echo"
        '

        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "echo_external" ]
        [ "${lines[1]}" = "echo_external" ]
        [ "${lines[2]}" = "hi" ]
}

@test "mcp client propagates remote errors" {
        run bash -lc '
                source ./src/mcp.sh
                endpoint="./src/tools/external/mcp_echo.sh"
                mcp_client_call_tool "${endpoint}" "echo_external" "{\"message\":\"explode\"}"
        '

        [ "$status" -ne 0 ]
        [[ "$output" == *"fatal"* ]]
}

@test "mcp client rejects non-object arguments" {
        run bash -lc '
                source ./src/mcp.sh
                endpoint="./src/tools/external/mcp_echo.sh"
                mcp_client_call_tool "${endpoint}" "echo_external" "not-json"
        '

        [ "$status" -ne 0 ]
        [[ "$output" == *"Payload must be a JSON object"* ]]
}

@test "mcp local invocation forwards arguments" {
        run bash -lc "
                source ./src/mcp.sh
                init_tool_registry
                TOOL_NAME_ALLOWLIST=()
                demo_handler() { printf \"seen:%s\" \"\${TOOL_QUERY}\"; }
                register_tool \"demo_local\" \"Demo local tool\" \"demo_local <query>\" \"Example\" demo_handler
                request=\$(jq -cn '{\"tool\":\"demo_local\",\"arguments\":{\"query\":\"payload\"}}')
                response=\$(mcp_invoke_local_tool \"\${request}\")
                echo \"\${response}\" | jq -r '.result.stdout'
                echo \"\${response}\" | jq -r '.result.exit_code'
        "

        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "seen:payload" ]
        [ "${lines[1]}" -eq 0 ]
}
