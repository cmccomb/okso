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

### How the planner is wired

1. **Tool + schema discovery:** `planner.sh` loads tool registrations and the planner
   JSON schema so the model knows what actions exist and how to call them.
2. **Context collection:** `planner_fetch_search_context` optionally performs a web
   search before prompting, providing citations the model can reuse when drafting an
   outline.
3. **Prompt assembly:** `prompt/build_planner.sh` renders a static prefix plus a dynamic
   suffix containing tools, schemas, examples, and timestamps. The combined prompt is
   fed to `llama_client.sh`.
4. **Normalization + scoring:** Raw model output is cleaned by
   `normalization.sh#normalize_planner_response`, then ranked via
   `scoring.sh#score_planner_candidate`. The best candidate's response and allowed tools
   are forwarded to the ReAct loop.
5. **Execution:** `react/react.sh` executes the plan with approvals and emits the final
   user-visible answer.
