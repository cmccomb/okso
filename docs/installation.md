# Installation

This project ships with an idempotent macOS-only installer that bootstraps dependencies and installs the CLI without performing global Homebrew upgrades.

## Local installer

Run the installer from the repository root to install, upgrade, or remove the CLI:

```bash
./scripts/install.sh [--prefix /custom/path] [--upgrade | --uninstall]
```

## Hosted installer

CI publishes the installer and a project tarball to GitHub Pages. The hosted script re-execs itself under `bash`, so you can install directly with:

```bash
curl -fsSL https://cmccomb.github.io/okso/install.sh | bash
```

## What the installer does

1. Verifies Homebrew is available (installing it if missing) without running `brew upgrade`.
2. Ensures pinned CLI dependencies: `llama.cpp` binaries, `llama-tokenize`, `tesseract`, `pandoc`, `poppler` (`pdftotext`), `yq`, `bash`, `coreutils`, and `jq`.
3. Copies the `src/` contents into `/usr/local/okso` (override with `--prefix`), and symlinks `okso` into your `PATH` (default: `/usr/local/bin`).
4. Relies on llama.cpp's built-in Hugging Face caching; models download on demand using `--hf-repo`/`--hf-file` flags instead of manual cache paths.
5. Offers `--upgrade` (refresh files) and `--uninstall` flows, refusing to run on non-macOS hosts.

## Manual setup

For manual setups, ensure `bash` 5+, `llama.cpp` (the `llama-cli` binary, optional for heuristic mode), `fd`, and `rg` are on your `PATH`, then run the script directly with:

```bash
./src/main.sh
```

Invoke the installed symlink directly (for example, `/usr/local/bin/okso --help`).
