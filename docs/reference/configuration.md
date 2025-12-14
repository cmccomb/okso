# Configuration

Defaults live in `${XDG_CONFIG_HOME:-~/.config}/okso/config.env`. Create or update that file without running a query:

```bash
./src/bin/okso init --model your-org/your-model:custom.gguf --model-branch main
```

The config file is `KEY="value"` style. Supported keys:

- `MODEL_SPEC`: Hugging Face `repo[:file]` identifier for the llama.cpp model (default: `bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf`).
- `MODEL_BRANCH`: Optional branch or tag for the model download (default: `main`).
- `LLAMA_BIN`: Path to the llama.cpp binary used for scoring (default: `llama-cli`).
- `TESTING_PASSTHROUGH`: `true` to bypass llama.cpp for offline or deterministic runs.
- `APPROVE_ALL`: `true` to skip prompts by default.
- `FORCE_CONFIRM`: `true` to always prompt, even when approvals are automatic.
- `VERBOSITY`: `0` (quiet), `1` (info), `2` (debug).
- `MCP_ENDPOINTS_TOML`: TOML array describing MCP endpoints. Each `[[mcp.endpoints]]`
  block must include `name`, `provider`, `description`, `safety`, and
  `transport`. HTTP endpoints also require `endpoint` and `token_env`; UNIX
  sockets use `socket`. No MCP endpoints are registered by default.

Environment variables prefixed with `OKSO_` mirror the config keys and take precedence over file values.

## Defining MCP endpoints

Populate the `MCP_ENDPOINTS_TOML` block in your config file to register custom
MCP endpoints without touching code. The loader converts this structure into
`MCP_ENDPOINTS_JSON` so the runtime and planner see the new tools automatically.

```toml
MCP_ENDPOINTS_TOML=$(cat <<'EOF_MCP'
[[mcp.endpoints]]
name = "mcp_remote_demo"
provider = "remote_vendor"
description = "Connect to a remote MCP endpoint for tool execution."
safety = "Requires a token; avoid logging sensitive inputs."
transport = "http"
endpoint = "https://example.test/mcp"
token_env = "MCP_TOKEN"

[[mcp.endpoints]]
name = "mcp_local_server"
provider = "local_demo"
description = "Connect to a local MCP server over a unix socket."
safety = "Uses a local socket; ensure the path is trusted before writing."
transport = "unix"
socket = "/tmp/okso-mcp.sock"
EOF_MCP
)
```

If the block is omitted, no MCP endpoints are registered. TOML parsing favors
the standard library `tomllib` module (Python 3.11+), and falls back to the
`pip` vendored `tomli` when needed, so deployments do not need to install a
separate TOML library.

When `usage` is omitted from an HTTP endpoint definition, okso calls the MCP
server's `/tools` route to build a planner-friendly summary of the available
tools. This keeps configuration terse while still giving the model concrete
capabilities to select. Set `MCP_SKIP_USAGE_DISCOVERY=true` to fall back to
`<tool> <query>` usage strings without hitting remote endpoints.
