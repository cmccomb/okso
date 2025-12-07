[![Run Tests](https://github.com/cmccomb/do/actions/workflows/run_tests.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/run_tests.yml)
[![Installation](https://github.com/cmccomb/do/actions/workflows/installation.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/installation.yml)
[![Deploy Installer](https://github.com/cmccomb/do/actions/workflows/deploy_installer.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/deploy_installer.yml)

# There is no try, just `okso`

A lightweight MCP-inspired planner that wraps a local `llama.cpp` binary, ranks registered tools via ToolRAG, and executes them with explicit approval controls and preview modes.

## Installation

Use the macOS installer to bootstrap dependencies and set up the CLI. See [installation details](docs/installation.md) for full options, hosted script usage, and manual setup notes.

## Basic usage

Prompted run (default):

```bash
./src/main.sh -- "inspect project layout and search notes"
```

Auto-approval with a specific model selection:

```bash
./src/main.sh --yes --model your-org/your-model:custom.gguf -- "save reminder"
```

More scenarios and approval modes live in the [usage guide](docs/usage.md). Configuration keys are covered in [configuration](docs/configuration.md), and available tools are listed in [tools](docs/tools.md). Development and testing steps are in [development](docs/development.md).
