# Documentation index

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
  - [Feedback](reference/feedback.md): review process expectations and response constraints.
  - [Final answer validation](reference/final-answer-validation.md): final response checks and formatting requirements.
- **Contributor docs** (`docs/contributor/`)
  - [Development](contributor/development.md): formatting, linting, and workflow notes.
  - [Testing](contributor/testing.md): Bats entry points and coverage reporting.
  - [Platform quirks](contributor/platform-quirks.md): macOS Bash compatibility tips.
