[![Run Tests](https://github.com/cmccomb/do/actions/workflows/run_tests.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/run_tests.yml)
[![Installation](https://github.com/cmccomb/do/actions/workflows/installation.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/installation.yml)
[![Deploy Installer](https://github.com/cmccomb/do/actions/workflows/deploy_installer.yml/badge.svg)](https://github.com/cmccomb/do/actions/workflows/deploy_installer.yml)

# There is no try, just `okso`

A lightweight MCP-inspired planner that wraps a local `llama.cpp` binary, ranks registered tools via ToolRAG, and executes them with explicit approval controls, preview modes, and configurable model defaults.

## Installation

Use the macOS installer to bootstrap dependencies and set up the CLI. See [installation details](docs/user-guides/installation.md) for full options, hosted script usage, and manual setup notes.

## Basic usage

Prompted run (default):

```bash
./src/main.sh -- "inspect project layout and search notes"
```

Auto-approval with a specific model selection:

```bash
./src/main.sh --yes --model your-org/your-model:custom.gguf -- "save reminder"
```

Write a config file up front with a custom model branch (defaults to `bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf` on `main`):

```bash
./src/main.sh init --model your-org/your-model:custom.gguf --model-branch release
```

More scenarios and approval modes live in the [usage guide](docs/user-guides/usage.md). Configuration keys are covered in [configuration](docs/reference/configuration.md), and available tools are listed in [tools](docs/reference/tools.md). Development and testing steps are in [contributor docs](docs/contributor/development.md).

See the [documentation index](docs/index.md) for a complete map of guides, references, and contributor notes.

### Offline and testing behavior

Set `TESTING_PASSTHROUGH=true` to disable llama.cpp calls during tests or offline usage. The planner exposes deterministic fallbacks when `LLAMA_AVAILABLE=false`, returning a simple final-answer-only plan and concise responses that acknowledge the original request instead of invoking `llama.cpp`.

## Prompt catalogue

All prompts used by the assistant are centralized in [`src/prompts.sh`](src/prompts.sh) for easier maintenance. The file exposes prompt builders for direct responses, plan generation, and ReAct steps so updates to tone, structure, or schema can be made in one place.

Structured outputs are enforced with shared [JSON schemas](src/grammars/) referenced by the prompt builders and passed directly to `llama.cpp` during inference. Each schema file name documents its purpose (e.g., `planner_plan.schema.json`, `react_action.schema.json`, `concise_response.schema.json`) so contributors can update the shapes without hunting through inline prompt text.

## Structured error envelopes

Shared helpers in [`src/errors.sh`](src/errors.sh) emit JSON envelopes for fatal and warning paths while ensuring non-zero exit
codes from pipelines and subshells. The envelope format is consistent across runtime and tool scripts:

```json
{
  "name": "cli",
  "category": "usage",
  "message": "--model requires an HF repo[:file] value"
}
```

- `name` identifies the emitting runtime or tool.
- `category` classifies the error (for example, `usage`, `pipeline`, or `fatal`).
- `message` carries the human-readable detail for the failure.
