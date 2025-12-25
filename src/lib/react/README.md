# Executor library

This package hosts the executor that runs after planning. The planner populates allowed tools, plan entries, and llama.cpp wiring, then delegates tool validation and execution to `react_loop`. The loop is deterministic: it iterates through planner actions, validates each tool against the allowlist, fills missing arguments in a single LLM round-trip when needed, retries safely, and records enriched error details rather than depending on multi-turn interactions. Callers that previously sourced `planning/react.sh` remain supported via the shim in that directory, but new entry points should source `react/react.sh` directly.

## Usage

Source the entry point to load the executor helpers and run the loop:

```bash
source "${PROJECT_ROOT}/src/lib/react/react.sh"
react_loop "${user_query}" "${allowed_tools}" "${plan_entries}" "${plan_outline}"
```

- `user_query`: original user request string.
- `allowed_tools`: newline-delimited tool names passed to schema generation and validation.
- `plan_entries`: newline-delimited JSON plan rows (optional; planner-provided).
- `plan_outline`: plain-text planner outline used to guide the loop.

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
