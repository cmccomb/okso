# Grammars

The assistant enforces structured responses for plans, tool calls, and final answers. Grammar files live in `src/grammars/` and
are passed directly to `llama.cpp` during inference to keep outputs predictable.

## Available schemas

- `planner_plan.schema.json`: describes the numbered outline that proposes tools and ends with `final_answer`.
- `react_action.schema.json`: constrains the ReAct loop to a single tool call per turn with the tool name, arguments, and
  optional planner context.
- `concise_response.schema.json`: ensures the assistant can emit short, direct answers when no tools need to run.

Each schema file documents its shape and intent inline so contributors can update fields without editing prompt text. When
adding a new tool or output type, create an accompanying schema in `src/grammars/` and reference it from the prompt builders in
`src/prompts.sh`.
