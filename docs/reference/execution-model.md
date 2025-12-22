# Execution model

okso separates high-level planning from step-by-step execution so that tool calls stay predictable and reviewable.

## Planner pass

1. The planner drafts a numbered outline that mentions the tools to use for each step.
2. The outline is emitted as structured JSON for logging and optional downstream automation.
3. Approval prompts give you a chance to refine or abort the plan before any commands run.
4. A side-effect-free scorer evaluates each sampled outline before selection. Plans that stay within the `PLANNER_MAX_PLAN_STEPS`
   budget, end with `final_answer`, use registered tools with schema-compliant arguments, and delay side-effecting actions receive
   higher scores and win ties when multiple candidates share the same numeric total.

## ReAct loop

After the plan is approved, the runtime iterates through each item:

- **Default behaviour:** llama.cpp is queried before each step to pick the next tool and craft an appropriate call based on the running transcript.
- **Fallback behaviour:** if llama.cpp is unavailable or `USE_REACT_LLAMA=false` is set, okso runs a deterministic sequence that feeds the original user query to each planned tool.

The active plan item and observations are streamed to the terminal to make model decisions auditable. Use `--dry-run` when you want to inspect the generated plan and tool calls without executing anything.

## Configuration hooks

- `USE_REACT_LLAMA`: toggles the ReAct pass (defaults to enabled).
- `OKSO_PLAN_OUTPUT`: file path for writing the approved plan JSON.
- `OKSO_TRACE_DIR`: directory for trace artifacts from each tool run.

See [usage](../user-guides/usage.md) for CLI flags that control approvals and dry runs.
