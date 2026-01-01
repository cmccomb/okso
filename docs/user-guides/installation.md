# Installation

The project now installs via a Homebrew tap that bundles dependencies and places the `okso` CLI on your `PATH` without requiring a global Homebrew upgrade.

## Install from the Homebrew tap

Tap the repository and install the formula:

```bash
brew tap cmccomb/okso
brew install okso
```

Upgrades and removals follow standard Homebrew flows:

```bash
brew upgrade okso
brew uninstall okso
```

The tap lives at [cmccomb/okso](https://github.com/cmccomb/okso) alongside the source. The formula installs tagged release tarballs; if you need to pin a specific version, use `brew pin okso` after installation.

## Migration note for the curl installer

The prior `scripts/install.sh` bootstrapper and hosted installer bundle are no longer maintained. Users who previously ran `curl -fsSL https://cmccomb.github.io/okso/install.sh | bash` should migrate to the tap-based flow above. Homebrew handles the dependencies the installer previously managed and keeps the `okso` symlink current.

## Manual setup

If you prefer to manage dependencies yourself:

1. Ensure `bash`, `jq`, `pandoc`, `xmllint` (`libxml2`), `rg`, `fd`, and a `llama.cpp` binary are on your `PATH` (macOS includes `mdfind` for Spotlight-backed searches).
2. Clone the repository and run the CLI directly:
   ```bash
   ./src/bin/okso --help
   ```
3. Use `./src/bin/okso init` to write `${XDG_CONFIG_HOME:-~/.config}/okso/config.env` with your preferred defaults.
