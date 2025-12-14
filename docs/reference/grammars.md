# Grammars

Structured outputs keep planner interactions predictable. Grammar files live in `src/grammars/` and are passed directly to `llama.cpp` during inference.

## Available schemas

- `planner_plan.schema.json`: numbered outline that proposes tools and ends with `final_answer`.
- `react_action.schema.json`: single tool call per ReAct turn with thought, tool name, and arguments.
- `concise_response.schema.json`: short direct answers when no tools should run.

Add new schemas alongside prompts in `src/lib/prompts.sh` when introducing new tool types or output formats.
