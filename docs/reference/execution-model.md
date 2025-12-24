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

After the plan is approved, the runtime iterates through a predictable loop:

1. **Plan**: keep a numbered outline with allowed tools in memory. When a replan occurs, the outline and allowed tools are replaced and the plan index resets to `0` so the refreshed outline drives the remaining execution.
2. **Execute Step**: llama.cpp proposes the next tool call based on the running transcript (or a deterministic sequence runs when `USE_REACT_LLAMA=false`). The current plan index only advances after the expected tool for the pending step completes successfully or an explicit skip reason is recorded.
3. **Observe**: capture `observation_raw` (verbatim output) and `observation_summary` (tool-aware digest). Terminal and `web_fetch` summarize stdout/stderr with bounded head/tail snippets plus exit metadata; `web_search` summaries track queries and top results; file-oriented tools capture cwd and created/updated/deleted paths. The latest step shows raw output for auditing while earlier steps prefer summaries for readability.
4. **Update Plan**: failure and divergence counters gate optional replanning. When triggered, okso calls the planner with the full execution transcript—including stdout, stderr, exit codes, and skip reasons—so the refreshed outline accounts for what just happened.

The active plan item and observations are streamed to the terminal so model decisions stay auditable. Use `--dry-run` to inspect the generated plan and tool calls without executing anything.

## Replanning behaviour

Replanning adds resilience without hiding problems. The ReAct loop tracks two signals:

- **Failure streaks:** after `REACT_REPLAN_FAILURE_THRESHOLD` consecutive failed tool runs (default: `2`), the planner is asked for a replacement outline. Set the variable higher to reduce replans or to `1` to replan after every failure.
- **Plan divergence:** when the chosen tool differs from the pending plan step, a single replanning attempt is scheduled to realign the outline with observed behaviour.

Each attempt forwards the current transcript to the planner and then resets `plan_index` to `0` with fresh `plan_entries`, `plan_outline`, and `allowed_tools`. The loop records `last_replan_attempt` and logs an `INFO` entry when the replacement outline is applied so you can correlate the refresh with the triggering step.

## Inspecting plans and traces

- `USE_REACT_LLAMA`: toggles the ReAct pass (defaults to enabled).
- `REACT_REPLAN_FAILURE_THRESHOLD`: consecutive failure budget before replanning (default: `2`).
- `OKSO_PLAN_OUTPUT`: file path for writing the approved plan JSON.
- `OKSO_TRACE_DIR`: directory for trace artifacts from each tool run. Trace entries include the evolving transcript, so replans and their replacement outlines are visible alongside tool stdout/stderr.

See [usage](../user-guides/usage.md) for CLI flags that control approvals, dry runs, and replanning demonstrations.
