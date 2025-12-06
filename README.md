# do Assistant Entrypoint

A lightweight MCP-inspired planner that wraps a local `llama.cpp` binary, ranks
registered tools via ToolRAG, and executes them in either supervised (human
confirmation) or unsupervised mode.

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

Key environment variables:

- `DO_MODEL`: HF repo[:file] identifier for the model download (default:
  `Qwen/Qwen3-1.5B-Instruct-GGUF:qwen3-1.5b-instruct-q4_k_m.gguf`).
- `DO_MODEL_BRANCH`: Branch or tag to download from (default: `main`).
- `DO_MODEL_CACHE`: Directory where downloaded GGUF files are stored (default:
  `~/.do/models`).
- `DO_LINK_DIR`: Directory for the CLI symlink (default: `/usr/local/bin`).
- `DO_INSTALLER_ASSUME_OFFLINE=true`: Skip network calls; installation fails if
  downloads are required while offline.
- `HF_TOKEN`: Optional Hugging Face token for gated model downloads.

For manual setups, ensure `bash` 5+, `llama.cpp` (optional for heuristic mode),
`fd`, and `rg` are on your `PATH`, then run the script directly with `./src/main.sh`.

## Configuration

Environment variables control runtime behavior and can be stored in an env file
(such as `tests/fixtures/sample.env`):

- `DO_MODEL`: HF repo[:file] identifier for the llama.cpp model (default:
  `Qwen/Qwen3-1.5B-Instruct-GGUF:qwen3-1.5b-instruct-q4_k_m.gguf`).
- `DO_MODEL_BRANCH`: Optional branch or tag for the model download (default:
  `main`).
- `DO_MODEL_CACHE`: Cache directory holding downloaded GGUF files (default:
  `~/.do/models`).
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

Unsupervised run with a specific model selection:

```bash
DO_SUPERVISED=false ./src/main.sh --model your-org/your-model:custom.gguf --model-cache ~/.do/models -- "save reminder"
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
shfmt -w scripts/install tests/test_install.bats
shellcheck scripts/install tests/test_install.bats
bats tests/test_all.sh tests/test_install.bats
```

The Bats suite covers CLI help/version output, supervised prompts, deterministic
mock scoring via `tests/fixtures/mock_llama.sh`, and graceful handling when
`LLAMA_BIN` is missing.
