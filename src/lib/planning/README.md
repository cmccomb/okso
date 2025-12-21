# Planning utilities

Planner-related helpers reside here, including the planner orchestration flow, plan
normalization, and formatting helpers. Shared utilities such as llama.cpp integration,
prompt rendering, schema lookup, and execution dispatchers live in sibling modules under
`../llm`, `../prompt`, `../schema`, and `../exec`. These helpers coordinate model
interactions and planning responses while relying on `../core` for logging/state and
`../cli` for user-facing output.

The ReAct loop now lives in `../react`. Existing callers that previously sourced
`planning/react.sh` still work through the compatibility shim in this directory, but new
entry points should source `../react/react.sh` directly. The planner populates plan
entries, schema constraints, and llama.cpp client wiring that the ReAct loop consumes to
execute tool calls and emit final answers.
