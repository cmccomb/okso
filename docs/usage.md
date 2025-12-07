# Usage

The CLI guides you through planning and executing tool calls. Use `--help` to see all options, pass `--verbose` for debug-level logs, or `--quiet` to silence informational messages.

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

Tool helpers for macOS clipboard access:

```bash
./src/main.sh -- tool clipboard_copy "temporary text"
./src/main.sh -- tool clipboard_paste
```

Refer to [configuration](configuration.md) for tuning defaults and [tools](tools.md) for supported handlers.
