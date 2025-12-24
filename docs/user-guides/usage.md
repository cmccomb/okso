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

### Recover with replanning

The runtime follows a loop of **Plan → Execute Step → Observe → Update Plan** so you can recover from unexpected errors without
starting over.

- Replanning kicks in after `REACT_REPLAN_FAILURE_THRESHOLD` consecutive failed tool runs (default: `2`). Set the variable to
  `1` to replan after every failure or increase it to delay replans when transient errors are expected.
- Plan divergence (when the model chooses a tool that does not match the pending plan step) schedules a single replan to
  realign the outline.
- The planner receives the live transcript—including stdout, stderr, exit codes, and skip reasons—so refreshed plans factor in
  what failed.

Use `OKSO_PLAN_OUTPUT` to capture the approved plan JSON and `OKSO_TRACE_DIR` to retain a full transcript. Both files include
the latest outline, so you can inspect how replanning changed the steps.

Example: trigger replanning after a failure and watch the updated plan replace the broken command.

```bash
REACT_REPLAN_FAILURE_THRESHOLD=1 \
OKSO_PLAN_OUTPUT=/tmp/okso.plan.json \
OKSO_TRACE_DIR=/tmp/okso-trace \
./src/bin/okso --yes -- "try to run a missing script, then find an alternative"
```

In this flow the first attempt to execute the missing script fails, the planner is re-invoked with the transcript, and the
replacement outline proposes a safer alternative (such as inspecting `scripts/` for available commands). The terminal log will
note `Replanned after execution issue`, and the trace directory will show both the failed call and the subsequent recovery
steps.

### Initialize config for a custom model

1. Generate a config file without executing any plan using the `init` subcommand. Supply your preferred models and optional branch. The defaults split responsibilities so the planner uses Qwen3-8B while the ReAct loop uses Qwen3-4B:

   ```bash
   ./src/bin/okso init --config "${XDG_CONFIG_HOME:-$HOME/.config}/okso/config.env" \
     --planner-model bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf \
     --react-model bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf \
     --model-branch main
   ```

2. At runtime, override config values with environment variables prefixed by `OKSO_` or by exporting the config keys directly:

   ```bash
   PLANNER_MODEL_SPEC=bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf \
   REACT_MODEL_SPEC=bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf \
   PLANNER_MODEL_BRANCH=main \
   REACT_MODEL_BRANCH=main \
   OKSO_LLAMA_BIN=llama-cli \
   ./src/bin/okso --yes -- "classify support tickets"
   ```

3. To keep the run noninteractive while still respecting a new model, pair the overrides with `--yes` or `--confirm` depending on whether you want automatic approvals.

Refer to [configuration](../reference/configuration.md) for available settings and [tools](../reference/tools.md) for handler details.
