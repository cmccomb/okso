[![CI - Unit](https://github.com/cmccomb/okso/actions/workflows/ci-unit.yml/badge.svg)](https://github.com/cmccomb/okso/actions/workflows/ci-unit.yml)
[![CI - Install](https://github.com/cmccomb/okso/actions/workflows/ci-install.yml/badge.svg)](https://github.com/cmccomb/okso/actions/workflows/ci-install.yml)
[![Deploy Installer](https://github.com/cmccomb/okso/actions/workflows/deploy_installer.yml/badge.svg)](https://github.com/cmccomb/okso/actions/workflows/deploy_installer.yml)

# `okso`, let's go to work

**A local-first, agentic CLI tool for macOS; a polite ghost in your machine.**  
okso helps small language models *operate* inside a desktop environment by routing intent → plans → tool calls, with an emphasis on repeatability, tight I/O, and “no surprises.”

## What it does

okso is a command-line interface that:
- turns a user request into a **structured plan**
- selects from a **tool registry** (terminal, files, notes, etc.)
- executes tool calls with **bounded side effects**
- emits a **final answer** (and can record it as an artifact)


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

See [docs/user-guides/usage.md](docs/user-guides/usage.md) for task-based walkthroughs (approvals, offline and configuration setup). Reference material lives in the [docs/](docs/index.md), including:

- [Execution model](docs/reference/execution-model.md): how planning and executor loops interact with tool calls.
- [Prompt assets](docs/reference/prompts.md): where prompts live and how they load.
- [Architecture overview](docs/reference/architecture.md): deeper look at the planner pass, executor loop, llama.cpp fallbacks, and tool ranking.

