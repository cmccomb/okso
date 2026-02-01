# Schemas

Structured outputs keep planner interactions predictable. Schema files live in `src/schemas/` and are passed directly to `llama.cpp` during inference. Because responses are already constrained by these schemas, we rely on the structured generation instead of layering additional validation in Bash.

## Available schemas

- `planner_plan.schema.json`: JSON array of tool steps and rationales; each item requires `tool`, `args`, and `thought`. The executor consumes the serialized plan directly from the planner response.
- `intent.schema.json`: intent classification payload (`intents`, `rationale`) used to filter tools and decide whether to run pre-planner web search.
- `pre_planner_search_terms.schema.json`: array of one to three concise search terms (5–80 characters each) used for pre-planning web lookups.
- `executor_action.schema.json`: template for dynamically generated per-tool schemas used during the executor loop. Tool names and argument shapes are injected at runtime before calls to `llama.cpp`.
- `final_answer_evaluation.schema.json`: evaluator output with `evaluation_type` (`FINAL`/`REPLAN`), `reasoning`, and `output` fields emitted by the final-answer evaluation helper.

Free-form text arguments always appear under `args.input` in planner payloads, keeping prompt templates and registry-driven schemas aligned on the same canonical field name.
