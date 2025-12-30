# Executor library

This package hosts the executor that runs after planning. The planner populates allowed tools, plan entries, and llama.cpp wiring, then delegates tool validation and execution to `executor_loop`. The loop is deterministic: it iterates through planner actions, validates each tool against the allowlist, fills missing arguments in a single LLM round-trip when needed, retries safely, and records enriched error details rather than depending on multi-turn interactions. Callers that previously sourced `planning/react.sh` remain supported via the shim in that directory, but new entry points should source `executor/executor.sh` directly.

## Usage

Source the entry point to load the executor helpers and run the loop:

```bash
source "${PROJECT_ROOT}/src/lib/executor/executor.sh"
executor_loop "${user_query}" "${allowed_tools}" "${plan_entries}" "${plan_outline}"
```

- `user_query`: original user request string.
- `allowed_tools`: newline-delimited tool names passed to schema generation and validation.
- `plan_entries`: newline-delimited JSON plan rows (optional; planner-provided).
- `plan_outline`: plain-text planner outline used to guide the loop.

The executor honours planner `args_control` metadata. When a tool argument is marked as `context`,
the loop flags it for LLM completion instead of copying history directly into the arg list. The
context-enrichment prompt shares the serialized history from `state_get_history_lines`, the planner
thought, plan outline, and any partial arg text so llama.cpp can compose a response rooted in the
latest context while leaving planner-provided required arguments untouched. Validation keeps the
`args_control` map attached to each plan entry, ensuring `resolve_action_args` receives the
context-marked keys and forwards them to the LLM prompt when enrichment is required.

Context hints are sanitized before prompting: `resolve_action_args` strips planner annotations from
the final argument payload, coerces `__context_controlled` into an array, ignores malformed seed
maps, and preserves original values when llama.cpp is unavailable. This keeps the executor prompt
stable even when upstream planners emit inconsistent metadata.

## Dependencies

- bash 3.2+
- jq
- python3 (for rich history formatting)
- llama.cpp binaries and model assets configured via the planner (loaded through
  `llm/llama_client.sh`)

## Sourcing notes

The library expects shared utilities to be co-located: prompt builders under `prompt/`,
tool dispatchers in `exec/`, schemas in `schema/`, and llama helpers in `llm/`. When
vendoring the module, ensure those dependencies are available and update the compatibility
shim at `src/lib/planning/react.sh` if needed.
