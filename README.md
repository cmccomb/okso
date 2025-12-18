[![CI - Unit](https://github.com/cmccomb/do/actions/workflows/ci-unit.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/ci-unit.yml)
[![CI - Install](https://github.com/cmccomb/do/actions/workflows/ci-install.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/ci-install.yml)
[![Deploy Installer](https://github.com/cmccomb/do/actions/workflows/deploy_installer.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/deploy_installer.yml)

# `okso`, let's go to work

A lightweight planner that runs against a local `llama.cpp` binary and executes registered tools with explicit approvals.

## Installation

Use the macOS installer from the repository root to set up dependencies and place the `okso` CLI on your `PATH`:

```bash
./scripts/install.sh [--prefix /custom/path] [--upgrade | --uninstall]
```

You can also install directly from the hosted script:

```bash
curl -fsSL https://cmccomb.github.io/okso/install.sh | bash
```

For offline deployments, set `OKSO_INSTALLER_ASSUME_OFFLINE=true` and point
`OKSO_INSTALLER_BASE_URL` to a directory or URL containing `okso.tar.gz`; the
installer will expand the archive instead of cloning the repository.

See [docs/user-guides/installation.md](docs/user-guides/installation.md) for additional options and manual setup notes.

## Basic usage

Run a prompted plan and tool execution:

```bash
./src/bin/okso -- "inspect project layout and search notes"
```

Skip confirmations and pick a specific model:

```bash
./src/bin/okso --yes --model your-org/your-model:custom.gguf -- "save reminder"
```

Initialize a config file with your preferred model settings:

```bash
./src/bin/okso init --model your-org/your-model:custom.gguf --model-branch main
```

More scenarios and reference material live in the [docs/](docs/index.md), including:

- [Execution model](docs/reference/execution-model.md): how planning and ReAct loops interact with tool calls.
- [Capturing feedback](docs/reference/feedback.md): recording plan ratings and configuring prompts.
- [Prompt assets](docs/reference/prompts.md): where prompts live and how they load.
- [Architecture overview](docs/reference/architecture.md): deeper look at the planner pass, ReAct loop, llama.cpp fallbacks, and tool ranking.
