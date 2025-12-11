[![Run Tests](https://github.com/cmccomb/do/actions/workflows/run_tests.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/run_tests.yml)
[![Installation](https://github.com/cmccomb/do/actions/workflows/installation.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/installation.yml)
[![Deploy Installer](https://github.com/cmccomb/do/actions/workflows/deploy_installer.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/deploy_installer.yml)

# okso

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

More scenarios and reference material live in the [docs/](docs/index.md).
