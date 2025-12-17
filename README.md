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

More scenarios and reference material live in the [docs/](docs/index.md).

## Execution model

okso separates high-level planning from step-by-step execution:

- **Planner pass:** drafts a numbered outline that mentions the tools to use.
- **ReAct loop:** by default, llama.cpp is queried before each step to pick the next tool
  and craft an appropriate call based on prior observations.

If llama.cpp is unavailable or `USE_REACT_LLAMA=false` is set, okso falls back to a
deterministic sequence that feeds the original user query to each planned tool.

## Capturing feedback

The bundled `feedback` tool records a 1-5 rating and optional comments for the
current plan item. Provide a JSON context payload describing the step and
observation summary:

```bash
TOOL_QUERY='{"plan_item":"Summarize notes","observations":"Draft complete"}' \
  FEEDBACK_NONINTERACTIVE_INPUT="5|Clear summary" \
  bash -lc 'source ./src/tools/feedback.sh; tool_feedback'
```

Interactive prompts are enabled by default. Set `FEEDBACK_ENABLED=false` to
skip prompting entirely or `FEEDBACK_OUTPUT_PATH=${HOME}/.okso/feedback.json` to
persist the captured payload within the writable allowlist.

## Prompt assets

Prompt templates live alongside grammar definitions to keep the assistant behaviour easy to review.
Each prompt has a dedicated file in `src/prompts/` (for example, `concise_response.txt`, `planner.txt`, and `react.txt`) and is loaded by the helpers in `src/lib/prompts.sh` before being sent to llama.cpp.
