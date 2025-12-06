# do Assistant Entrypoint

A lightweight MCP-inspired planner that wraps a local `llama.cpp` binary, ranks
registered tools via ToolRAG, and executes them with explicit approval controls
and preview modes.

## Installation

The project ships with an idempotent macOS-only installer that bootstraps
dependencies and installs the CLI binary without running global Homebrew
upgrades:

```bash
./scripts/install [--prefix /custom/path] [--upgrade | --uninstall]
```

What the installer does:

1. Verifies Homebrew is present (installing it if missing) without running
   `brew upgrade`.
2. Ensures pinned CLI dependencies: `llama.cpp` binaries, `llama-tokenize`,
   `tesseract`, `pandoc`, `poppler` (`pdftotext`), `yq`, `bash`, `coreutils`,
   and `jq`.
3. Copies the `src/` contents into `/usr/local/do` (override with `--prefix`),
   and symlinks `do` into your `PATH` (default: `/usr/local/bin`).
4. Downloads a configurable Qwen3 GGUF for `llama.cpp` into `~/.do/models`
   via llama.cpp's Hugging Face flags, reusing cached copies when present.
5. Offers `--upgrade` (refresh files/model) and `--uninstall` flows, refusing
   to run on non-macOS hosts.

For manual setups, ensure `bash` 5+, `llama.cpp` (optional for heuristic mode),
`fd`, and `rg` are on your `PATH`, then run the script directly with `./src/main.sh`.

## Configuration

The CLI defaults are stored in `${XDG_CONFIG_HOME:-~/.config}/do/config.env`.
Initialize or update that file without running a query via:

```bash
./src/main.sh init --model your-org/your-model:custom.gguf --model-branch main --model-cache ~/.do/models
```

The config file is a simple `key="value"` env-style document. Supported keys:

- `MODEL_SPEC`: HF repo[:file] identifier for the llama.cpp model (default:
  `Qwen/Qwen3-1.5B-Instruct-GGUF:qwen3-1.5b-instruct-q4_k_m.gguf`).
- `MODEL_BRANCH`: Optional branch or tag for the model download (default:
  `main`).
- `MODEL_CACHE`: Cache directory holding downloaded GGUF files (default:
  `~/.do/models`).
- `APPROVE_ALL`: `true` to skip prompts by default; `false` prompts before each
  tool.
- `FORCE_CONFIRM`: `true` to always prompt, even when `--yes` is set in the
  config.
- `VERBOSITY`: `0` (quiet), `1` (info), `2` (debug).

Legacy environment variables such as `DO_MODEL`, `DO_MODEL_BRANCH`, and
`DO_MODEL_CACHE` are still honored when set for backward compatibility, but the
CLI and config file are the primary configuration surfaces.

## Approval and preview modes

- **Default**: prompts before executing each tool. Declining a tool logs a skip
  and continues through the ranked list.
- `--yes` / `--no-confirm`: executes ranked tools without prompts.
- `--confirm`: forces prompts even if the config opts into auto-approval.
- `--dry-run`: prints the planned calls without running any tool handlers.
- `--plan-only`: emits the machine-readable plan JSON and exits.

## Tooling registry

The planner registers the following tools:

- `os_nav`: inspect the working directory (read-only).
- `file_search`: search for files and contents using `fd`/`rg` fallbacks.
- `notes`: append reminders under `~/.do/notes.txt`.
- `mail_stub`: capture a mail draft without sending.
- `applescript`: execute AppleScript snippets on macOS (no-op elsewhere).

Ranking now builds a single compact prompt that lists every tool's name,
description, safety note, and command. When `LLAMA_BIN` is available,
`llama.cpp` returns the subset of tools to run (with scores and short
justifications) in one call; otherwise a deterministic keyword heuristic is
used. The resulting ranking is reused for the user-facing suggestion prompt and
execution ordering.

## Usage examples

Prompted run (default):

```bash
./src/main.sh -- "inspect project layout and search notes"
```

Auto-approval with a specific model selection:

```bash
./src/main.sh --yes --model your-org/your-model:custom.gguf --model-cache ~/.do/models -- "save reminder"
```

Use `--help` to view all options. Pass `--verbose` for debug-level logs or
`--quiet` to silence informational messages.

## Testing and linting

Run the formatting and lint targets before executing the Bats suite:

```bash
shfmt -w src/main.sh tests/test_all.sh tests/test_main.bats
shellcheck src/main.sh tests/test_all.sh tests/test_main.bats
shfmt -w scripts/install tests/test_install.bats
shellcheck scripts/install tests/test_install.bats
bats tests/test_all.sh tests/test_install.bats
```

The Bats suite covers CLI help/version output, confirmation prompts, deterministic
mock scoring via `tests/fixtures/mock_llama.sh`, and graceful handling when
`LLAMA_BIN` is missing.
