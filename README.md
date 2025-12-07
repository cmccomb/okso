[![Run Tests](https://github.com/cmccomb/do/actions/workflows/run_tests.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/run_tests.yml)
[![Installation](https://github.com/cmccomb/do/actions/workflows/installation.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/installation.yml)
[![Deploy Installer](https://github.com/cmccomb/do/actions/workflows/deploy_installer.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/deploy_installer.yml)


# There is no try, just `okso`

A lightweight MCP-inspired planner that wraps a local `llama.cpp` binary, ranks
registered tools via ToolRAG, and executes them with explicit approval controls
and preview modes.

## Installation

The project ships with an idempotent macOS-only installer that bootstraps
dependencies and installs the CLI binary without running global Homebrew
upgrades:

```bash
./scripts/install.sh [--prefix /custom/path] [--upgrade | --uninstall]
```

For unattended installs, the CI pipeline publishes the installer and a
project tarball to GitHub Pages. The hosted script re-execs itself under
`bash`, so use:

```bash
curl -fsSL https://cmccomb.github.io/okso/install.sh | bash
```

What the installer does:

1. Verifies Homebrew is present (installing it if missing) without running
   `brew upgrade`.
2. Ensures pinned CLI dependencies: `llama.cpp` binaries, `llama-tokenize`,
   `tesseract`, `pandoc`, `poppler` (`pdftotext`), `yq`, `bash`, `coreutils`,
   and `jq`.
3. Copies the `src/` contents into `/usr/local/okso` (override with `--prefix`),
   and symlinks `okso` into your `PATH` (default: `/usr/local/bin`).
4. Relies on llama.cpp's built-in Hugging Face caching; models download on
   demand using `--hf-repo`/`--hf-file` flags instead of manual cache paths.
5. Offers `--upgrade` (refresh files) and `--uninstall` flows, refusing
   to run on non-macOS hosts.

For manual setups, ensure `bash` 5+, `llama.cpp` (the `llama-cli` binary, optional
for heuristic mode), `fd`, and `rg` are on your `PATH`, then run the script directly
with `./src/main.sh`.

Invoke the installed symlink directly (for example, `/usr/local/bin/okso --help`).

## Configuration

The CLI defaults are stored in `${XDG_CONFIG_HOME:-~/.config}/okso/config.env`.
Initialize or update that file without running a query via:

```bash
./src/main.sh init --model your-org/your-model:custom.gguf --model-branch main
```

The config file is a simple `key="value"` env-style document. Supported keys:

- `MODEL_SPEC`: HF repo[:file] identifier for the llama.cpp model (default:
  `Qwen/Qwen3-1.5B-Instruct-GGUF:qwen3-1.5b-instruct-q4_k_m.gguf`).
- `MODEL_BRANCH`: Optional branch or tag for the model download (default:
  `main`).
- `LLAMA_BIN`: Path to the llama.cpp binary used for scoring (default: `llama-cli`).
- `APPROVE_ALL`: `true` to skip prompts by default; `false` prompts before each
  tool.
- `FORCE_CONFIRM`: `true` to always prompt, even when `--yes` is set in the
  config.
- `VERBOSITY`: `0` (quiet), `1` (info), `2` (debug).

Legacy environment variables such as `DO_MODEL` and `DO_MODEL_BRANCH` are still
honored when set for backward compatibility, but the CLI and config file are
the primary configuration surfaces.

## Approval and preview modes

- **Default**: prompts before executing each tool. Declining a tool logs a skip
  and continues through the ranked list.
- `--yes` / `--no-confirm`: executes ranked tools without prompts.
- `--confirm`: forces prompts even if the config opts into auto-approval.
- `--dry-run`: prints the planned calls without running any tool handlers.
- `--plan-only`: emits the machine-readable plan JSON and exits.

## Tooling registry

The planner registers the following tools (each defined in `src/tools/<name>.sh`):

- `terminal`: persistent terminal session with a curated command set (pwd, ls,
  du, cd, cat, head, tail, find, grep, stat, wc, base64 encode/decode, mkdir,
  rmdir, mv, cp, touch, rm -i by default, plus `open` on macOS).
- `file_search`: search for files and contents using `fd`/`rg` fallbacks.
- `clipboard_copy`: copy provided text into the macOS clipboard.
- `clipboard_paste`: read the current macOS clipboard contents.
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
directory and a listing), `pwd`, `ls`, `cd`, `cat`, `head`, `tail`, `find`,
`grep`, `stat`, `wc`, `du` (defaults to `-sh .` when no arguments are provided),
`base64` (requires an explicit `encode` or `decode` mode), and `open` on macOS
hosts. Mutation commands are guarded to reduce risk: `rm` always includes
`-i` unless an interactive flag is already present, while `mkdir`, `rmdir`,
`mv`, `cp`, and `touch` validate required arguments before executing.

Clipboard helpers are macOS-only and rely on `pbcopy`/`pbpaste`. Avoid copying
credentials or other sensitive information because clipboard contents may be
visible to other applications and logs. Examples:

```bash
./src/main.sh -- tool clipboard_copy "temporary text"
./src/main.sh -- tool clipboard_paste
```

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
./src/main.sh --yes --model your-org/your-model:custom.gguf -- "save reminder"
```

Use `--help` to view all options. Pass `--verbose` for debug-level logs or
`--quiet` to silence informational messages.

## Testing and linting

Run the formatting and lint targets before executing the Bats suite:

```bash
shfmt -w src/*.sh src/tools/*.sh src/tools/notes/*.sh tests/*.bats tests/test_all.sh tests/test_install.bats tests/test_main.bats tests/test_modules.bats tests/test_notes.bats scripts/install.sh
shellcheck src/*.sh src/tools/*.sh src/tools/notes/*.sh tests/*.bats tests/test_all.sh tests/test_install.bats tests/test_main.bats tests/test_modules.bats tests/test_notes.bats scripts/install.sh
bats tests/test_all.sh tests/test_install.bats tests/test_main.bats tests/test_modules.bats tests/test_notes.bats
```

The Bats suite covers CLI help/version output, confirmation prompts, deterministic
mock scoring via `tests/fixtures/mock_llama.sh`, and graceful handling when
`LLAMA_BIN` is missing.
