# Installation

The project ships a macOS-focused installer that bundles dependencies and places the `okso` CLI on your `PATH` without forcing a global Homebrew upgrade.

## Install from the repository

Run the installer from the repository root to install, upgrade, or remove the CLI:

```bash
./scripts/install.sh [--prefix /custom/path] [--upgrade | --uninstall]
```

- Use `--prefix` to pick the installation directory (defaults to `/usr/local/okso`).
- Pass `--upgrade` to refresh an existing install with the latest files.
- Pass `--uninstall` to remove the installation and symlink.

## Install from the hosted script

CI publishes the installer and project tarball to GitHub Pages. To bootstrap without cloning the repo:

```bash
curl -fsSL https://cmccomb.github.io/okso/install.sh | bash
```

The hosted script re-executes under `bash` and mirrors the local installer behavior.

## What the installer configures

1. Checks for Homebrew and installs it if missing (without running `brew upgrade`).
2. Ensures pinned dependencies such as `llama.cpp`, `llama-tokenize`, `tesseract`, `pandoc`, `poppler` (`pdftotext`), `yq`, `bash`, `coreutils`, and `jq`.
3. Copies the `src/` contents into the install prefix and symlinks `okso` into your `PATH` (default: `/usr/local/bin`).
4. Uses llama.cpp's Hugging Face cache for models; download happens on demand through `--model`/`--model-branch` flags rather than manual cache setup.
5. Refuses to run on non-macOS hosts so platform assumptions stay consistent.

## Manual setup

If you prefer to manage dependencies yourself:

1. Ensure `bash`, `jq`, `rg`, `fd`, and a `llama.cpp` binary are on your `PATH`.
2. Clone the repository and run the CLI directly:
   ```bash
   ./src/bin/okso --help
   ```
3. Use `./src/bin/okso init` to write `${XDG_CONFIG_HOME:-~/.config}/okso/config.env` with your preferred defaults.
