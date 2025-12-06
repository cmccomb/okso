# do Assistant Entrypoint

A lightweight MCP-inspired planner that wraps a local `llama.cpp` binary, ranks
registered tools via ToolRAG, and executes them in either supervised (human
confirmation) or unsupervised mode.

## Features

- Configurable model path, supervised flag, and verbosity via CLI flags or
  environment variables.
- Structured JSON logging for predictable parsing.
- Tool registry covering OS navigation, project search (`fd`/`rg`), reminders,
  a mail draft stub, and macOS-only AppleScript execution with defensive checks.
- ToolRAG ranking that prefers llama.cpp scoring when available and falls back
  to heuristics otherwise.
- Planner/executor loop that collects a plan, confirms tool usage in supervised
  mode, executes handlers, and summarizes results.

## Usage

```bash
./src/main.sh -- "inspect project layout and search notes"
./src/main.sh --unsupervised --model ./models/llama.gguf -- "save reminder"
```

Use `--help` to view all options. Pass `--verbose` for debug-level logs or
`--quiet` to silence informational messages.

## Testing

Run the Bats suite after formatting and linting:

```bash
shfmt -w src/main.sh tests/test_main.bats
shellcheck src/main.sh tests/test_main.bats
bats tests/test_main.bats
```

`llama.cpp` is optional for tests; heuristic fallbacks keep runs fast when the
binary is absent.
