# Okso documentation

Okso is a local-first automation toolkit that turns natural-language intent into reliable command-line execution. It combines a planning loop, guarded tool execution, and transparent logs so teams can automate workflows without losing control of what runs or why.

## Features

- **Plan-aware execution** with step-by-step traces for accountability.
- **Configurable tools and prompts** to tailor Okso to your environment.
- **Deterministic schemas** that keep planner output predictable and auditable.
- **Developer-friendly workflow** with clear install, usage, and contributor guides.

## Getting Started

1. **Install Okso** by following the installation guide: [Installation](user-guides/installation.md).
2. **Run your first command** with the usage guide open for reference: [Usage](user-guides/usage.md).

If you want to go deeper, start with the core reference docs for configuration and execution details:

- [Configuration](reference/configuration.md)
- [Execution model](reference/execution-model.md)
- [Tools](reference/tools.md)

## Why Okso

Okso is built on principles that prioritize safety and clarity:

- **Transparency**: every plan and action is logged so you can review what happened.
- **Control**: you decide which tools are available and how they are configured.
- **Predictability**: schemas and sampling controls make outputs consistent and explainable.
- **Portability**: it runs where you work, from local terminals to CI environments.

## Next steps

- Install and upgrade guidance: [Installation](user-guides/installation.md)
- Learn CLI workflows and flags: [Usage](user-guides/usage.md)
- Explore core references: [Architecture](reference/architecture.md), [Prompts](reference/prompts.md), [Schemas](reference/schemas.md)

## Documentation Map

Use this map to find the right guide:

- **User guides** (`docs/user-guides/`)
  - [Installation](user-guides/installation.md): install, upgrade, or uninstall the CLI.
  - [Usage](user-guides/usage.md): command-line flags and common execution patterns.
- **Reference** (`docs/reference/`)
- [Architecture](reference/architecture.md): planner flow, executor loop, llama.cpp fallbacks, and tool ranking.
- [Execution model](reference/execution-model.md): planning steps and executor loop details.
  - [Planner sampling](reference/planner-sampling.md): sampling controls, scoring heuristics, and debug logs.
  - [Prompts](reference/prompts.md): template layout and schema links.
  - [Configuration](reference/configuration.md): environment variables and config file keys.
  - [Tools](reference/tools.md): available tool handlers and platform notes.
  - [Schemas](reference/schemas.md): JSON schemas that keep planner output predictable.
- **Contributor docs** (`docs/contributor/`)
  - [Development](contributor/development.md): formatting, linting, and workflow notes.
  - [Testing](contributor/testing.md): Bats entry points and coverage reporting.
  - [Platform quirks](contributor/platform-quirks.md): macOS Bash compatibility tips.
