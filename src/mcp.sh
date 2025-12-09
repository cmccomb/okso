#!/usr/bin/env bash
# shellcheck shell=bash
#
# MCP adapter and client utilities for mapping the local tool registry to
# machine-checkable descriptors and for invoking remote MCP-compatible tools.
#
# Usage:
#   source "${BASH_SOURCE[0]%/mcp.sh}/mcp.sh"
#
# Responsibilities:
#   - Generate MCP tool descriptors from the local registry entries.
#   - Normalize invocation and result envelopes for local handlers.
#   - Provide a minimal MCP client for list/describe/call lifecycle steps.
#
# Expected types:
#   All arguments are strings unless otherwise noted. JSON payload strings must
#   already be validated upstream to reduce repeated parsing work.
#
# Dependencies:
#   - bash 5+
#   - jq
#   - registry helpers from tools.sh

# shellcheck source=./errors.sh disable=SC1091
source "${BASH_SOURCE[0]%/mcp.sh}/errors.sh"
# shellcheck source=./logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/mcp.sh}/logging.sh"
# shellcheck source=./tools.sh disable=SC1091
source "${BASH_SOURCE[0]%/mcp.sh}/tools.sh"

mcp_error_payload() {
        # Builds an MCP-style error envelope.
        # Arguments:
        #   $1 - context emitting the error (string)
        #   $2 - category (string)
        #   $3 - message (string)
        local context category message
        context="$1"
        category="$2"
        message="$3"

        jq -cn \
                --arg name "${context}" \
                --arg category "${category}" \
                --arg message "${message}" \
                '{type:"error", error:{name:$name, category:$category, message:$message}}'
}

mcp_require_json_object() {
        # Validates that provided JSON is an object.
        # Arguments:
        #   $1 - context for error reporting (string)
        #   $2 - JSON payload to validate (string)
        local context payload
        context="$1"
        payload="$2"

        if ! jq -e 'type == "object"' <<<"${payload}" >/dev/null 2>&1; then
                mcp_error_payload "${context}" "usage" "Payload must be a JSON object" >&2
                return 1
        fi
}

mcp_descriptor_from_registry() {
        # Converts a registry entry into an MCP tool descriptor.
        # Arguments:
        #   $1 - tool name (string)
        local tool_name description command safety
        tool_name="$1"
        description="${TOOL_DESCRIPTION[${tool_name}]:-}"
        command="${TOOL_COMMAND[${tool_name}]:-}"
        safety="${TOOL_SAFETY[${tool_name}]:-}"

        jq -cn \
                --arg name "${tool_name}" \
                --arg description "${description}" \
                --arg safety "${safety}" \
                --arg command "${command}" \
                --arg query_description "Value assigned to TOOL_QUERY for the handler" \
                '{
                        name:$name,
                        description:$description,
                        command:$command,
                        origin:"local",
                        safety:$safety,
                        input_schema:{type:"object", required:["query"], properties:{query:{type:"string", description:$query_description}}},
                        result_schema:{type:"object", properties:{stdout:{type:"string"}, exit_code:{type:"integer"}}}
                }'
}

mcp_local_tool_descriptors() {
        # Emits a JSON array of MCP tool descriptors for all registered tools.
        # Arguments: none; uses global TOOLS array.
        local name

        if [[ "${#TOOLS[@]}" -eq 0 ]]; then
                jq -n '[]'
                return
        fi

        jq -s '.' <(
                for name in "${TOOLS[@]}"; do
                        mcp_descriptor_from_registry "${name}"
                done
        )
}

mcp_result_envelope() {
        # Formats a successful MCP tool call result.
        # Arguments:
        #   $1 - tool name (string)
        #   $2 - stdout content (string)
        #   $3 - exit code (integer string)
        local tool_name stdout_content exit_code
        tool_name="$1"
        stdout_content="$2"
        exit_code="$3"

        jq -cn \
                --arg tool "${tool_name}" \
                --arg stdout "${stdout_content}" \
                --argjson exit_code "${exit_code}" \
                '{type:"result", tool:$tool, result:{stdout:$stdout, exit_code:$exit_code}}'
}

mcp_invoke_local_tool() {
        # Invokes a registered local tool using MCP request semantics.
        # Arguments:
        #   $1 - request JSON containing "tool" and "arguments.query" fields
        local request tool_name query handler output status
        request="$1"

        if ! tool_name=$(jq -cer '.tool' <<<"${request}" 2>/dev/null); then
                mcp_error_payload "runtime" "usage" "Request must include tool name" >&2
                return 1
        fi

        if ! query=$(jq -cer '.arguments.query' <<<"${request}" 2>/dev/null); then
                mcp_error_payload "${tool_name}" "usage" "Request must include arguments.query" >&2
                return 1
        fi

        handler="${TOOL_HANDLER[${tool_name}]:-}"
        if [[ -z "${handler}" ]]; then
                mcp_error_payload "${tool_name}" "usage" "No handler registered for tool" >&2
                return 1
        fi

        output="$(TOOL_QUERY="${query}" ${handler} 2>&1)"
        status=$?

        mcp_result_envelope "${tool_name}" "${output}" "${status}"
        return "${status}"
}

mcp_client_send_request() {
        # Sends a JSON request to an MCP-compatible endpoint.
        # Arguments:
        #   $1 - endpoint command (string)
        #   $2 - JSON payload to send (string)
        local endpoint payload response status
        endpoint="$1"
        payload="$2"

        if [[ -z "${endpoint}" ]]; then
                mcp_error_payload "runtime" "usage" "MCP endpoint is required" >&2
                return 1
        fi

        if ! mcp_require_json_object "runtime" "${payload}"; then
                return 1
        fi

        response="$(printf '%s' "${payload}" | "${endpoint}" 2>&1)"
        status=$?
        if ((status != 0)); then
                mcp_error_payload "runtime" "pipeline" "Endpoint returned non-zero status" >&2
                printf '%s' "${response}" >&2
                return 1
        fi

        if ! jq -e 'type == "object"' <<<"${response}" >/dev/null 2>&1; then
                mcp_error_payload "runtime" "usage" "Endpoint response was not valid JSON" >&2
                return 1
        fi

        printf '%s' "${response}"
}

mcp_client_list_tools() {
        # Requests the available MCP tool descriptors from an endpoint.
        # Arguments:
        #   $1 - endpoint command (string)
        local endpoint payload response
        endpoint="$1"
        payload='{"action":"list_tools"}'

        response="$(mcp_client_send_request "${endpoint}" "${payload}")" || return 1
        if [[ "$(jq -r '.type' <<<"${response}")" == "error" ]]; then
            printf '%s' "${response}" >&2
            return 1
        fi

        jq -cer '.tools' <<<"${response}"
}

mcp_client_describe_tool() {
        # Requests a single tool descriptor from an endpoint.
        # Arguments:
        #   $1 - endpoint command (string)
        #   $2 - tool name (string)
        local endpoint tool_name payload response
        endpoint="$1"
        tool_name="$2"

        payload=$(jq -cn --arg tool "${tool_name}" '{action:"describe_tool", tool:$tool}')
        response="$(mcp_client_send_request "${endpoint}" "${payload}")" || return 1

        if [[ "$(jq -r '.type' <<<"${response}")" == "error" ]]; then
                printf '%s' "${response}" >&2
                return 1
        fi

        jq -cer '.tool' <<<"${response}"
}

mcp_client_call_tool() {
        # Invokes a remote MCP tool and returns its result envelope.
        # Arguments:
        #   $1 - endpoint command (string)
        #   $2 - tool name (string)
        #   $3 - arguments JSON fragment (string)
        local endpoint tool_name arguments payload response
        endpoint="$1"
        tool_name="$2"
        arguments="$3"

        if ! mcp_require_json_object "${tool_name}" "${arguments}"; then
                return 1
        fi

        payload=$(jq -cn --arg tool "${tool_name}" --argjson arguments "${arguments}" '{action:"call_tool", tool:$tool, arguments:$arguments}')
        response="$(mcp_client_send_request "${endpoint}" "${payload}")" || return 1

        if [[ "$(jq -r '.type' <<<"${response}")" == "error" ]]; then
                printf '%s' "${response}" >&2
                return 1
        fi

        printf '%s' "${response}"
}
