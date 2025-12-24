# ReAct library

This package hosts the ReAct execution loop extracted from the planning helpers. The
planner populates allowed tools, plan entries, and llama.cpp wiring, then delegates tool
selection and execution to `react_loop` defined here. Callers that previously sourced
`planning/react.sh` remain supported via the shim in that directory, but new entry points
should source `react/react.sh` directly.

## Usage

Source the entry point to load the ReAct helpers and run the loop:

```bash
source "${PROJECT_ROOT}/src/lib/react/react.sh"
react_loop "${user_query}" "${allowed_tools}" "${plan_entries}" "${plan_outline}"
```

- `user_query`: original user request string.
- `allowed_tools`: newline-delimited tool names passed to schema generation and validation.
- `plan_entries`: newline-delimited JSON plan rows (optional; planner-provided).
- `plan_outline`: plain-text planner outline used to guide the loop.

### Plan skip tracking

When a planned step cannot run (for example, a tool is not permitted, the model emits an
invalid action, or the loop detects a duplicate call), the loop records a skip reason and
keeps the current plan index unchanged. Callers can inspect `plan_skip_reason` and
`pending_plan_step` in the state to understand why a plan step was bypassed.

### Automatic replanning

Tool failures and plan divergence can trigger a fresh planning pass without losing the
ongoing transcript. The loop counts consecutive failures and, once the
`REACT_REPLAN_FAILURE_THRESHOLD` (default: 2) is met, asks the planner for a new outline.
The request includes the current execution transcript with stdout, stderr, and exit codes so
the new outline accounts for recent errors. Plan divergence (for example, when the selected
tool differs from the pending plan step) also schedules a single replanning pass to realign
execution without spamming the planner.

### Budgeting and completion

The loop derives its attempt budget from the number of planned steps plus the
`REACT_RETRY_BUFFER` environment variable (default: 2). The `max_steps` state field reflects
that dynamic budget, while `attempts` and `retry_count` capture how many actions have been
tried and how many of those failed to make progress. The `step` counter only increases when a
tool run succeeds or a plan step is explicitly advanced, so retries on a pending step do not
consume the plan budget. Completion always requires a successful `final_answer` action; if it
is missing when the budget is exhausted, the loop will synthesize a fallback answer.

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
