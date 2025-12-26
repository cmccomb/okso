# Schemas

Structured outputs keep planner interactions predictable. Schema files live in `src/schemas/` and are passed directly to `llama.cpp` during inference.

## Available schemas

- `planner_plan.schema.json`: JSON object with a `plan` array of tool steps and rationales; each step requires `tool`, `args`, and `thought`, and may set `args_control` entries (matching `args` keys) to lock values or request executor-provided context; loaded at runtime by `planner.sh` before plan validation.
- `react_action.schema.json`: executor action template; tool enums and per-tool args are injected during schema generation and consumed by the executor in `react/loop.sh` for validation and fallback selection. Planner output must include every required argument up front while planner-marked context-controlled fields can be enriched by the executor LLM when available.
- `concise_response.schema.json`: short direct answers when no tools should run; used by `respond.sh` to constrain final-answer fallback summaries.

Free-form text arguments always appear under `args.input` in planner payloads, keeping prompt templates and registry-driven
schemas aligned on the same canonical field name. Planner normalization also maps common aliases like `args.code` to `args.input`
before validation to guard against minor LLM formatting drift.

Add new schemas alongside prompts in `src/lib/prompts.sh` when introducing new tool types or output formats.
