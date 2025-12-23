# Prompt assets

Prompt templates live alongside schema definitions so the assistant behaviour stays easy to review and update.

## Layout

- `src/prompts/`: text templates used by the planner, ReAct loop, and response helpers (for example, `final_answer_fallback.txt`, `planner.txt`, and `react.txt`).
- `src/lib/prompts.sh`: helper functions that load prompt files, substitute runtime variables, and pass the final strings to llama.cpp.
- `src/schemas/`: JSON schemas that constrain planner output and tool arguments.

## Working with prompts

- Edit templates directly to adjust tone or required fields. Keep schema changes in sync to avoid model errors.
- Store reusable snippets (such as safety disclaimers) in dedicated files and compose them within the main prompt templates.
- Keep prompts minimal and version-controlled; avoid inlining large instructions in code so they remain discoverable for audits.
- Oversized context (for example, verbose `web_fetch` results) is summarized automatically before llama.cpp is invoked so prompts stay within the configured token budget.
- The planner prompt now includes a `search_context` block derived from a deterministic pre-plan web search using the user query; planners consume this grounding directly instead of scheduling `web_search` steps.
- Planner instructions require tool arguments to stay concise (single-line string fields, no code fences, and short summaries) to prevent oversized or unsafe payloads from reaching tool handlers.

## Related resources

- [Schemas](schemas.md): schema details for planner and tool outputs.
- [Execution model](execution-model.md): how prompts feed into planning and the ReAct loop.
- [Tools](tools.md): available handlers that consume prompt output.
