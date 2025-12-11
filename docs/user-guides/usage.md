# Usage

Use `./src/bin/okso --help` to see all flags. The CLI walks through planning and tool execution with approvals by default.

## Approval and preview modes

- **Prompted (default):** asks before executing each tool.
- `--yes` / `--no-confirm`: skip prompts and run the ranked tools automatically.
- `--confirm`: force prompts even when the config enables auto-approval.
- `--dry-run`: print the planned tool calls without executing them.
- `--plan-only`: emit the machine-readable plan JSON and exit.

## Model selection

Model defaults live in `${XDG_CONFIG_HOME:-~/.config}/okso/config.env`. Override them per run:

```bash
./src/bin/okso --model your-org/your-model:custom.gguf --model-branch main -- "draft meeting notes"
```

## Common flows

Prompted run:

```bash
./src/bin/okso -- "inspect project layout and search notes"
```

Auto-approval with a specific model:

```bash
./src/bin/okso --yes --model your-org/your-model:custom.gguf -- "save reminder"
```

Write a config file without executing a plan:

```bash
./src/bin/okso init --config ~/.config/okso/config.env --model your-org/your-model:custom.gguf --model-branch beta
```

macOS clipboard helpers:

```bash
./src/bin/okso -- tool clipboard_copy "temporary text"
./src/bin/okso -- tool clipboard_paste
```

Refer to [configuration](../reference/configuration.md) for available settings and [tools](../reference/tools.md) for handler details.
