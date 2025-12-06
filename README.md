# do Assistant Entrypoint

A lightweight MCP-inspired planner that wraps a local `llama.cpp` binary, ranks
registered tools via ToolRAG, and executes them in either supervised (human
confirmation) or unsupervised mode.

## Installation

The project ships with a Homebrew-based installer that bootstraps dependencies
and installs the CLI binary:

```bash
./scripts/install
```

The installer will:

1. Ensure Homebrew is available (installing it if missing).
2. Install command-line dependencies (`llama.cpp`, `tesseract`, `pandoc`,
   `poppler`, `yq`).
3. Copy the `src/` contents into `/usr/local/do` and symlink the entrypoint to
   `/usr/local/bin/do`.

For manual setups, ensure `bash` 5+, `llama.cpp` (optional for heuristic mode),
`fd`, and `rg` are on your `PATH`, then run the script directly with `./src/main.sh`.

## Configuration

Environment variables control runtime behavior and can be stored in an env file
(such as `tests/fixtures/sample.env`):

- `DO_MODEL_PATH`: Path to the llama.cpp model (default: `./models/llama.gguf`).
- `DO_SUPERVISED`: `true`/`false` to toggle confirmation prompts (default:
  `true`).
- `DO_VERBOSITY`: `0` (quiet), `1` (info), `2` (debug). Overrides `-v`/`-q`.
- `LLAMA_BIN`: llama.cpp binary to use (default: `llama`; can point to the mock
  `tests/fixtures/mock_llama.sh` during testing).

The included `tests/fixtures/sample.env` demonstrates a debug-friendly,
unsupervised configuration that prefers the notes tool for reminder queries.
Running with that config and a reminder request will emit a tool prompt where
`notes` is scored highest, followed by a summary beginning with
`[notes executed]`.

## Modes

- **Supervised** (default): prompts before executing each tool. Declining a tool
  logs a skip and continues through the ranked list.
- **Unsupervised**: executes ranked tools without prompts; enable with
  `--unsupervised` or `DO_SUPERVISED=false`.

## Tooling registry

The planner registers the following tools:

- `os_nav`: inspect the working directory (read-only).
- `file_search`: search for files and contents using `fd`/`rg` fallbacks.
- `notes`: append reminders under `~/.do/notes.txt`.
- `mail_stub`: capture a mail draft without sending.
- `applescript`: execute AppleScript snippets on macOS (no-op elsewhere).

Ranking prefers llama.cpp scoring when `LLAMA_BIN` is available; otherwise a
heuristic keyword overlap is used.

## Usage examples

Supervised run (default):

```bash
./src/main.sh -- "inspect project layout and search notes"
```

Unsupervised run with a specific model:

```bash
DO_SUPERVISED=false ./src/main.sh --model ./models/llama.gguf -- "save reminder"
```

Using the sample configuration:

```bash
set -a
. tests/fixtures/sample.env
set +a
./src/main.sh -- "capture reminder for tomorrow"
```

Use `--help` to view all options. Pass `--verbose` for debug-level logs or
`--quiet` to silence informational messages.

## Testing and linting

Run the formatting and lint targets before executing the Bats suite:

```bash
shfmt -w src/main.sh tests/test_all.sh tests/test_main.bats
shellcheck src/main.sh tests/test_all.sh tests/test_main.bats
bats tests/test_all.sh
```

The Bats suite covers CLI help/version output, supervised prompts, deterministic
mock scoring via `tests/fixtures/mock_llama.sh`, and graceful handling when
`LLAMA_BIN` is missing.
