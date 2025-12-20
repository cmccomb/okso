# Schemas

Structured outputs keep planner interactions predictable. Schema files live in `src/schemas/` and are passed directly to `llama.cpp` during inference.

## Available schemas

- `planner_plan.schema.json`: numbered outline that proposes tools and ends with `final_answer`.
- `react_action.schema.json`: compiled ReAct shape with `terminal` and `final_answer` oneOf branches, const tool names, and args objects that reject extra properties.
- `concise_response.schema.json`: short direct answers when no tools should run.

Free-form text arguments always appear under `args.input` in planner and ReAct payloads, keeping prompt templates and registry-driven
schemas aligned on the same canonical field name.

Add new schemas alongside prompts in `src/lib/prompts.sh` when introducing new tool types or output formats.
