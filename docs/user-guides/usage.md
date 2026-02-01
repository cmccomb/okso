# Usage

Use `./src/bin/okso --help` to see all flags. The CLI walks through planning and tool execution with approvals by default.

## Task-based walkthroughs

### Run with approvals

1. Start with a prompted run so the plan requires confirmation before tools execute (default):

   ```bash
   ./src/bin/okso -- "inspect project layout and search notes"
   ```

2. To auto-approve tool calls, pass `--yes` (or `--no-confirm`) for a fully automated pass:

   ```bash
   ./src/bin/okso --yes -- "save reminder"
   ```

3. If your config sets `APPROVE_ALL=true` but you need prompts for a sensitive query, export `APPROVE_ALL=false` for that run:

   ```bash
   APPROVE_ALL=false ./src/bin/okso -- "draft meeting notes"
   ```

4. Increase logging with `--verbose` or silence informational logs with `--quiet` when running unattended scripts.

### Initialize config for a custom model

1. Generate a config file without executing any plan using the `init` subcommand. Set the model specs and branches you want via environment variables before running `init`:

   ```bash
   export PLANNER_MODEL_SPEC="bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf"
   export EXECUTOR_MODEL_SPEC="bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf"
   export SEARCH_REPHRASER_MODEL_SPEC="bartowski/Qwen_Qwen3-1.7B-GGUF:Qwen_Qwen3-1.7B-Q4_K_M.gguf"
   export PLANNER_MODEL_BRANCH=main
   export EXECUTOR_MODEL_BRANCH=main
   export SEARCH_REPHRASER_MODEL_BRANCH=main
   CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/okso/config.env" ./src/bin/okso init
   ```

2. At runtime, override config values by exporting the same variable names that appear in `config.env`:

   ```bash
   PLANNER_MODEL_SPEC=bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf \
   EXECUTOR_MODEL_SPEC=bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf \
   PLANNER_MODEL_BRANCH=main \
   EXECUTOR_MODEL_BRANCH=main \
   LLAMA_BIN=llama-completion \
   ./src/bin/okso --yes -- "classify support tickets"
   ```

3. To keep the run noninteractive while still respecting a new model, pair the overrides with `--yes`.

Refer to [configuration](../reference/configuration.md) for available settings and [tools](../reference/tools.md) for handler details.
