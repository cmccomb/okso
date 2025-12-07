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

The planner registers the following tools (each defined in `src/tools/<name>.sh`):

- `terminal`: persistent terminal session with a limited command set (pwd, ls,
  cd, cat, head, tail, find, grep, open on macOS).
- `file_search`: search for files and contents using `fd`/`rg` fallbacks.
- `notes_create`: create a new Apple Note (first line = title).
- `notes_append`: append text to an existing Apple Note by title.
- `notes_list`: list note titles within the configured Apple Notes folder.
- `notes_search`: search Apple Notes titles and bodies for a phrase.
- `notes_read`: read an Apple Note's contents by title.
- `reminders_create`: create a new Apple Reminder (first line = title).
- `reminders_list`: list incomplete Apple Reminders in the configured list.
- `reminders_complete`: mark an Apple Reminder complete by title.
- `calendar_create`: create a new Apple Calendar event (line 1: title; line 2: start time; optional line 3: location).
- `calendar_list`: list upcoming Apple Calendar events for the configured calendar.
- `calendar_search`: search Apple Calendar events by title or location.
- `mail_draft`: create a new Apple Mail draft (line 1: recipients, line 2: subject).
- `mail_send`: compose and send an Apple Mail message immediately.
- `mail_search`: search Apple Mail inbox messages by subject, sender, or body.
- `mail_list_inbox`: list recent Apple Mail inbox messages.
- `mail_list_unread`: list unread Apple Mail inbox messages.
- `applescript`: execute AppleScript snippets on macOS (no-op elsewhere).

The `terminal` tool keeps a per-query working directory and reuses it across
invocations so agents can `cd` once and continue running commands from the same
location. Supported commands include `status` (default, shows the current
directory and a listing), `pwd`, `ls`, `cd`, `cat`, `head`, `tail`, `find`, and
`grep`, plus `open` on macOS hosts.

Apple Notes tools expect the first line of `TOOL_QUERY` to be the note title and
the remaining lines to form the body (where applicable). Set `NOTES_FOLDER` to
point at a specific folder (default: `Notes`). On non-macOS hosts or when
`osascript` is unavailable, the tools emit a warning and exit without changes.

Apple Calendar tools use `TOOL_QUERY` lines for event details: the first line is
the title, the second is a human-friendly start time (parsed by AppleScript's
`date`), and the third is an optional location. Set `CALENDAR_NAME` to direct
operations to a specific calendar (default: `Calendar`). These tools only run on
macOS with `osascript` available; otherwise, they log a warning and return
without executing.

Apple Mail tools expect `TOOL_QUERY` lines to be structured as comma-separated
recipients on the first line, a subject on the second, and the optional body on
subsequent lines. The inbox listing tools respect `MAIL_INBOX_LIMIT` to cap
results (default: 10).

Ranking now builds a single compact prompt that lists every tool's name,
description, safety note, and command. When `LLAMA_BIN` is available,
`llama.cpp` returns the subset of tools to run (with scores and short
justifications) in one call; otherwise a deterministic keyword heuristic is
used. The resulting ranking is reused for the user-facing suggestion prompt and
execution ordering.

## Code layout

The Bash entrypoint is decomposed into focused modules to simplify maintenance
and testing:

- `src/main.sh`: wiring and high-level orchestration.
- `src/cli.sh`: help/version output and argument parsing.
- `src/config.sh`: configuration loading, normalization, and environment setup.
- `src/tools.sh`: central registry that sources per-tool modules from `src/tools/`.
- `src/tools/*.sh`: individual tool handlers (e.g., `terminal`, `file_search`).
- `src/planner.sh`: ranking, planning, and execution flow.
- `src/logging.sh`: structured logging helpers shared across modules.

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
shfmt -w src/*.sh src/tools/*.sh src/tools/notes/*.sh tests/*.bats tests/test_all.sh tests/test_install.bats tests/test_main.bats tests/test_modules.bats tests/test_notes.bats scripts/install
shellcheck src/*.sh src/tools/*.sh src/tools/notes/*.sh tests/*.bats tests/test_all.sh tests/test_install.bats tests/test_main.bats tests/test_modules.bats tests/test_notes.bats scripts/install
bats tests/test_all.sh tests/test_install.bats tests/test_main.bats tests/test_modules.bats tests/test_notes.bats
```

The Bats suite covers CLI help/version output, confirmation prompts, deterministic
mock scoring via `tests/fixtures/mock_llama.sh`, and graceful handling when
`LLAMA_BIN` is missing.
