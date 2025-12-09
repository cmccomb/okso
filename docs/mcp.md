# MCP tool specification

The okso runtime exposes its local tool registry using a machine-checkable MCP
shape and can query external MCP-compatible endpoints. The model-facing prompts
reuse these descriptors to surface available tools, argument schemas, and
expected result envelopes.

## Tool descriptors

Each tool is described with a JSON object:

- `name` (string): registry identifier.
- `description` (string): human-readable summary.
- `command` (string): indicative CLI syntax for the tool.
- `origin` (string): `local` for bundled handlers or `remote` for external MCP
  endpoints.
- `safety` (string): safety or guardrails summary.
- `input_schema` (object): JSON Schema object describing expected arguments.
- `result_schema` (object): JSON Schema object describing the result envelope.

Local tools map `input_schema.properties.query` to the `TOOL_QUERY` value passed
into the registered handler. Results are wrapped in `{type:"result", tool,
result:{stdout, exit_code}}` to capture handler output alongside exit codes.

## Requests and responses

Requests sent to MCP endpoints always include an `action` discriminator:

- `list_tools`: returns `{type:"result", tools:[<descriptor>, ...]}`.
- `describe_tool`: accepts `tool` (string) and responds with
  `{type:"result", tool:<descriptor>}`.
- `call_tool`: accepts `tool` (string) and `arguments` (object) and responds with
  `{type:"result", tool, result:<tool-defined object>}`.

Endpoints can surface errors using `{type:"error", error:{name, category,
message}}`. The `name` field should identify the emitting component, `category`
classifies the failure (`usage`, `pipeline`, `fatal`, etc.), and `message` is a
human-readable detail.

Clients validate that outbound payloads and arguments are JSON objects before
calling remote endpoints to avoid leaking parser errors through the transport.

## Runtime helpers

The runtime layers expose helper functions for working with MCP endpoints:

- `mcp_local_tool_descriptors`: convert the current registry into MCP
  descriptors.
- `mcp_build_runtime_catalog`: merge local descriptors with a configured remote
  endpoint (`MCP_ENDPOINT`) while logging and tolerating discovery failures.
- `describe_remote_mcp_tool TOOL`: fetch a descriptor from the configured
  endpoint.
- `invoke_remote_mcp_tool TOOL ARGS_JSON`: call a remote MCP tool using the
  provided argument JSON.

Set `MCP_ENDPOINT` to the command that implements the MCP contract to enable
remote discovery and execution.

## External reference tool

A reference MCP endpoint lives at `src/tools/external/mcp_echo.sh`. It exposes a
single `echo_external` tool with the schema `{message:string}` and returns
`{echo:string}` on success. Example interactions:

```bash
echo '{"action":"list_tools"}' | ./src/tools/external/mcp_echo.sh
echo '{"action":"describe_tool","tool":"echo_external"}' | ./src/tools/external/mcp_echo.sh
echo '{"action":"call_tool","tool":"echo_external","arguments":{"message":"hi"}}' | ./src/tools/external/mcp_echo.sh
```
