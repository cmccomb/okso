[![Run Tests](https://github.com/cmccomb/do/actions/workflows/run_tests.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/run_tests.yml)
[![Installation](https://github.com/cmccomb/do/actions/workflows/installation.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/installation.yml)
[![Deploy Installer](https://github.com/cmccomb/do/actions/workflows/deploy_installer.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/deploy_installer.yml)

# There is no try, just `okso`

A lightweight MCP-inspired planner that wraps a local `llama.cpp` binary, ranks registered tools via ToolRAG, and executes them with explicit approval controls, preview modes, and configurable model defaults.

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

Write a config file up front with a custom model branch (defaults to `bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF:Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf` on `main`):

```bash
./src/main.sh init --model your-org/your-model:custom.gguf --model-branch release
```

More scenarios and approval modes live in the [usage guide](docs/usage.md). Configuration keys are covered in [configuration](docs/configuration.md), and available tools are listed in [tools](docs/tools.md). Development and testing steps are in [development](docs/development.md).

### Offline and testing behavior

Set `TESTING_PASSTHROUGH=true` to disable llama.cpp calls during tests or offline usage. The planner exposes deterministic fallbacks when `LLAMA_AVAILABLE=false`, returning a simple final-answer-only plan and concise responses that acknowledge the original request instead of invoking `llama.cpp`.

## Prompt catalogue

All prompts used by the assistant are centralized in [`src/prompts.sh`](src/prompts.sh) for easier maintenance. The file exposes prompt builders for direct responses, plan generation, and ReAct steps so updates to tone, structure, or schema can be made in one place.

Structured outputs are enforced with shared [GBNF grammars](src/grammars/) referenced by the prompt builders and passed directly to `llama.cpp` during inference. Each grammar file name documents its purpose (e.g., `planner_plan.gbnf`, `react_action.gbnf`, `concise_response.gbnf`) so contributors can update schemas without hunting through inline prompt text.
