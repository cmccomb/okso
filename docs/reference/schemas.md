# Schemas

Structured outputs keep planner interactions predictable. Schema files live in `src/schemas/` and are passed directly to `llama.cpp` during inference.

## Available schemas

- `planner_plan.schema.json`: numbered outline that proposes tools and ends with `final_answer`; loaded at runtime by `planner.sh` before plan validation.
- `react_action.schema.json`: executor action template; tool enums, per-tool args, and missing-value sentinels are injected during schema generation and consumed by the executor in `react/loop.sh` for validation and fallback selection.
- `concise_response.schema.json`: short direct answers when no tools should run; used by `respond.sh` to constrain final-answer fallback summaries.

Free-form text arguments always appear under `args.input` in planner payloads, keeping prompt templates and registry-driven
schemas aligned on the same canonical field name. Planner normalization also maps common aliases like `args.code` to `args.input`
before validation to guard against minor LLM formatting drift.

Add new schemas alongside prompts in `src/lib/prompts.sh` when introducing new tool types or output formats.
