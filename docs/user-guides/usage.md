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
   OKSO_LLAMA_BIN=llama-completion \
   ./src/bin/okso --yes -- "classify support tickets"
   ```

3. To keep the run noninteractive while still respecting a new model, pair the overrides with `--yes` or `--confirm` depending on whether you want automatic approvals.

Refer to [configuration](../reference/configuration.md) for available settings and [tools](../reference/tools.md) for handler details.

## Define and invoke workflows

Workflows let you bundle a sequence of tool calls behind a pseudo-tool named `workflow_<name>`. Create a JSON or YAML file in `workflows/` and include the required metadata and steps.

```yaml
# workflows/triage_ticket.yaml
name: triage_ticket
description: Triage a support ticket and capture notes.
parameters:
  type: object
  properties:
    ticket_id:
      type: string
    summary:
      type: string
  required:
    - ticket_id
    - summary
  additionalProperties: false
steps:
  - tool: terminal
    args:
      command: "echo \"Ticket {{ticket_id}}\""
    thought: "Confirm ticket exists."
  - tool: notes_create
    args:
      title: "Triage: {{ticket_id}}"
    thought: "Start a triage note for {{ticket_id}}."
```

When planning, refer to the workflow pseudo-tool in your prompt:

```text
Use workflow_triage_ticket with ticket_id \"INC-123\" and summary \"Payment failures\".
```

The planner will emit a `workflow_triage_ticket` step, which is expanded into the concrete `terminal` and `notes_create` steps during normalization.
