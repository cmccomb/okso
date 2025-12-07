# Usage

The CLI guides you through planning and executing tool calls. Use `--help` to see all options, pass `--verbose` for debug-level logs, or `--quiet` to silence informational messages.

Model defaults live in `${XDG_CONFIG_HOME:-~/.config}/okso/config.env`. Override them per-run with `--model` and `--model-branch` (default: `Qwen/Qwen3-1.5B-Instruct-GGUF:qwen3-1.5b-instruct-q4_k_m.gguf` on `main`).

## Approval and preview modes

- **Default**: prompts before executing each tool. Declining a tool logs a skip and continues through the ranked list.
- `--yes` / `--no-confirm`: executes ranked tools without prompts.
- `--confirm`: forces prompts even if the config opts into auto-approval.
- `--dry-run`: prints the planned calls without running any tool handlers.
- `--plan-only`: emits the machine-readable plan JSON and exits.

## Examples

Prompted run (default):

```bash
./src/main.sh -- "inspect project layout and search notes"
```

Auto-approval with a specific model selection:

```bash
./src/main.sh --yes --model your-org/your-model:custom.gguf -- "save reminder"
```

Write a config file without running a plan to persist model overrides:

```bash
./src/main.sh init --config ~/.config/okso/config.env --model your-org/your-model:custom.gguf --model-branch beta
```

Tool helpers for macOS clipboard access:

```bash
./src/main.sh -- tool clipboard_copy "temporary text"
./src/main.sh -- tool clipboard_paste
```

Refer to [configuration](configuration.md) for tuning defaults and [tools](tools.md) for supported handlers.
