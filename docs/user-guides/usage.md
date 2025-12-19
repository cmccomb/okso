# Usage

Use `./src/bin/okso --help` to see all flags. The CLI walks through planning and tool execution with approvals by default.

## Task-based walkthroughs

### Run with approvals

1. Start with a prompted run so each tool call requires confirmation (default):

   ```bash
   ./src/bin/okso -- "inspect project layout and search notes"
   ```

2. To auto-approve tool calls, pass `--yes` (or `--no-confirm`) for a fully automated pass:

   ```bash
   ./src/bin/okso --yes -- "save reminder"
   ```

3. If your config sets `APPROVE_ALL=true` but you need to restore prompts for a sensitive query, add `--confirm` to override the config.

4. Preview the plan without running anything using `--dry-run`, or emit machine-readable JSON only via `--plan-only`:

   ```bash
   ./src/bin/okso --dry-run -- "draft meeting notes"
   ./src/bin/okso --plan-only -- "catalog data sources"
   ```

5. Increase logging with `--verbose` or silence informational logs with `--quiet` when running unattended scripts.

### Initialize config for a custom model

1. Generate a config file without executing any plan using the `init` subcommand. Supply your preferred models and optional branch. The defaults split responsibilities so the planner uses Qwen3-8B while the ReAct loop uses Qwen3-1.7B:

   ```bash
   ./src/bin/okso init --config "${XDG_CONFIG_HOME:-$HOME/.config}/okso/config.env" \
     --planner-model bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf \
     --react-model bartowski/Qwen_Qwen3-1.7B-GGUF:Qwen_Qwen3-1.7B-Q4_K_M.gguf \
     --model-branch main
   ```

2. At runtime, override config values with environment variables prefixed by `OKSO_` or by exporting the config keys directly:

   ```bash
   PLANNER_MODEL_SPEC=bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf \
   REACT_MODEL_SPEC=bartowski/Qwen_Qwen3-1.7B-GGUF:Qwen_Qwen3-1.7B-Q4_K_M.gguf \
   PLANNER_MODEL_BRANCH=main \
   REACT_MODEL_BRANCH=main \
   OKSO_LLAMA_BIN=llama-cli \
   ./src/bin/okso --yes -- "classify support tickets"
   ```

3. To keep the run noninteractive while still respecting a new model, pair the overrides with `--yes` or `--confirm` depending on whether you want automatic approvals.

### macOS clipboard helpers

Call built-in helpers when you need quick transfers without opening other tools:

```bash
./src/bin/okso -- tool clipboard_copy "temporary text"
./src/bin/okso -- tool clipboard_paste
```

Refer to [configuration](../reference/configuration.md) for available settings and [tools](../reference/tools.md) for handler details.
