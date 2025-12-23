# Execution model

okso separates high-level planning from step-by-step execution so that tool calls stay predictable and reviewable.

## Planner pass

1. The planner drafts a numbered outline that mentions the tools to use for each step.
2. A dedicated rephrasing step asks a Qwen3 1.7B model for 1–3 focused web search strings (constrained by a JSON schema) and runs
   a search for each, folding the aggregated snippets into the planner prompt.
3. The outline is emitted as structured JSON for logging and optional downstream automation.
4. Approval prompts give you a chance to refine or abort the plan before any commands run.
5. A side-effect-free scorer evaluates each sampled outline before selection. Plans that stay within the `PLANNER_MAX_PLAN_STEPS`
   budget, end with `final_answer`, use registered tools with schema-compliant arguments, and delay side-effecting actions receive
   higher scores and win ties when multiple candidates share the same numeric total.
6. Each planner invocation samples `PLANNER_SAMPLE_COUNT` candidates at `PLANNER_TEMPERATURE`; the scored JSONL history is written
   to `PLANNER_DEBUG_LOG` so you can audit how the winner was chosen.

See [Planner sampling](./planner-sampling.md) for detailed scoring heuristics and debug log fields that help compare candidates.

## ReAct loop

After the plan is approved, the runtime iterates through each item:

- **Default behaviour:** llama.cpp is queried before each step to pick the next tool and craft an appropriate call based on the running transcript.
- **Fallback behaviour:** if llama.cpp is unavailable or `USE_REACT_LLAMA=false` is set, okso runs a deterministic sequence that feeds the original user query to each planned tool.
- **Plan progression:** the plan index only advances after the expected tool for the pending plan step completes successfully or an explicit skip reason is recorded. Invalid model output, tool failures, or a tool choice that diverges from the plan keep the current step pending so the outline and execution stay aligned.

The active plan item and observations are streamed to the terminal to make model decisions auditable. Use `--dry-run` when you want to inspect the generated plan and tool calls without executing anything.

## Configuration hooks

- `USE_REACT_LLAMA`: toggles the ReAct pass (defaults to enabled).
- `OKSO_PLAN_OUTPUT`: file path for writing the approved plan JSON.
- `OKSO_TRACE_DIR`: directory for trace artifacts from each tool run.

See [usage](../user-guides/usage.md) for CLI flags that control approvals and dry runs.
