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
  block must include `name`, `provider`, `description`, `usage`, `safety`, and
  `transport`. HTTP endpoints also require `endpoint` and `token_env`; UNIX
  sockets use `socket`.

Environment variables prefixed with `OKSO_` mirror the config keys and take precedence over file values.

## Defining MCP endpoints

Populate the `MCP_ENDPOINTS_TOML` block in your config file to register custom
MCP endpoints without touching code. The loader converts this structure into
`MCP_ENDPOINTS_JSON` so the runtime and planner see the new tools automatically.

```toml
MCP_ENDPOINTS_TOML=$(cat <<'EOF_MCP'
[[mcp.endpoints]]
name = "mcp_huggingface"
provider = "huggingface"
description = "Connect to the configured Hugging Face MCP endpoint with the provided query."
usage = "mcp_huggingface <query>"
safety = "Requires a valid Hugging Face token; do not print secrets in tool calls."
transport = "http"
endpoint = "https://example.test/mcp"
token_env = "MCP_TOKEN"

[[mcp.endpoints]]
name = "mcp_local_server"
provider = "local_demo"
description = "Connect to the bundled local MCP server over a unix socket."
usage = "mcp_local_server <query>"
safety = "Uses a local socket; ensure the path is trusted before writing."
transport = "unix"
socket = "/tmp/okso-mcp.sock"
EOF_MCP
)
```

If the block is omitted, okso synthesizes defaults using
`MCP_HUGGINGFACE_URL`, `MCP_HUGGINGFACE_TOKEN_ENV`, and `MCP_LOCAL_SOCKET`.
