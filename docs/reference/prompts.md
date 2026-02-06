# Prompt assets

Prompt templates live alongside schema definitions so the assistant behaviour stays easy to review and update.

## Layout

- `src/prompts/`: text templates used by the planner, executor, intent classifier, and response helpers (for example, `planner.md` and `executor.md`).
- `src/lib/llm/templates.sh`: helper functions that load prompt files, substitute runtime variables, and pass the final strings to llama.cpp.
- `src/schemas/`: JSON schemas that constrain planner output and tool arguments.

## Working with prompts

- Edit templates directly to adjust tone or required fields. Keep schema changes in sync to avoid model errors.
- Store reusable snippets (such as safety disclaimers) in dedicated files and compose them within the main prompt templates.
- Keep prompts minimal and version-controlled; avoid inlining large instructions in code so they remain discoverable for audits.
- Oversized context (for example, verbose `web_fetch` results) is summarized automatically before llama.cpp is invoked so prompts stay within the configured token budget.
- The planner prompt includes an intent context block plus a `search_context` block derived from a deterministic pre-plan web search. When llama.cpp is available, a rephraser model generates 1–3 queries; otherwise the raw user query is used. If search is disabled or fails, the block may be empty.
- The search context formatter emits a default "No search results were captured for this query." message when the pre-plan search yields no items.
- Planner instructions require tool arguments to stay concise (single-line string fields, no code fences, and short summaries) to prevent oversized or unsafe payloads from reaching tool handlers.

## Related resources

- [Schemas](schemas.md): schema details for planner and tool outputs.
- [Execution model](execution-model.md): how prompts feed into planning and the executor.
- [Tools](tools.md): available handlers that consume prompt output.
