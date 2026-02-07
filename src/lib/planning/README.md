# Planning utilities

Planner helpers live here: orchestration (`planner.sh`), prompt assembly (`prompting.sh`), pre-plan search (`search.sh`), normalization (`normalization.sh`), and scoring (`scoring.sh`). They depend on sibling modules under `src/lib/` (notably `llm/`, `tools/`, `intent/`, `settings/`, `executor/`, `core/`, and `cli/`), plus templates in `src/prompts/` and schemas in `src/schemas/`.

The executor loop lives in `../executor`. The planner emits plan JSON and allowed tools; the executor performs approvals, argument fill, tool execution, and final answer evaluation.

## How the planner is wired

1. **Tool + schema discovery:** `planner.sh` loads tool registrations and builds a planner schema from `src/schemas/planner_plan.schema.json` plus per-tool argument schemas, with tuple variants that require a terminal `final_answer` step.
2. **Search query rephrasing:** `search.sh` renders the `pre_planner_search_terms` prompt. When llama.cpp is available, the search rephraser model (`SEARCH_REPHRASER_MODEL_SPEC`) produces 1–3 queries using schema-constrained decoding and DRY sampling (`SEARCH_REPHRASER_DRY_ARGS`). If llama.cpp is unavailable, the raw user query is used instead.
3. **Context collection:** `planner_fetch_search_context` runs `web_search` for each query and formats the snippets into prompt-ready context.
4. **Prompt assembly:** `prompting.sh` renders the planner prompt with tools, schemas, timestamps, intent context, feedback, and search context, then sends it to `llama_client.sh`.
5. **Normalization + scoring:** `normalization.sh#normalize_plan` enforces the plan array shape and expands workflows. `scoring.sh#score_planner_candidate` ranks candidates and pre-validates python_repl snippets for syntax/import issues.
6. **Execution:** `executor/loop.sh` runs the approved plan, handles context argument infill, and emits the final user-visible answer.
