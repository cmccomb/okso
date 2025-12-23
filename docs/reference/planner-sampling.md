# Planner sampling, scoring, and debugging

Planner runs sample multiple outline candidates before execution. Use these controls to guide the search, understand scoring, and inspect alternatives.

## Sampling controls

- `PLANNER_SAMPLE_COUNT` sets how many candidates to generate and score. Values below `1` are clamped to `1` so selection always has a plan to review.
- `PLANNER_TEMPERATURE` forwards directly to llama.cpp for planner generations. Lower values keep plans conservative; higher values explore more tool permutations. Values should stay between `0` and `1` for predictable entropy.

All normalized candidates are scored before selection to ensure the highest-quality plan is chosen, even when early samples look promising.

## Scoring rules

Planner scoring rewards concise, compliant plans and penalizes risky or invalid suggestions:

- Plans within the `PLANNER_MAX_PLAN_STEPS` budget earn a baseline bonus; going over budget subtracts points per extra step.
- Ending with `final_answer` is required; missing it incurs a heavy penalty.
- Steps that reference unknown tools or include args that fail schema validation reduce the score, while registered tools with valid args earn a small bonus.
- Side-effecting tools that appear after information-gathering steps receive a positive adjustment; starting with a side-effecting action introduces a deduction.
- A tie-breaker favors shorter plans when scores are equal by comparing remaining budget vs. overages.

See [`src/lib/planning/scoring.sh`](../../src/lib/planning/scoring.sh) for the exact heuristics applied to each candidate.

## Debugging planner output

Every candidate plan is normalized and appended to `PLANNER_DEBUG_LOG` (default `${TMPDIR:-/tmp}/okso_planner_candidates.log`) as a JSON object containing:

- `index`: 1-based sample order.
- `score` and `tie_breaker`: numeric values produced by the scoring pass.
- `rationale`: explanation strings backing each score component.
- `response`: the normalized planner output, including the selected mode and plan steps.

The log is truncated at the start of each planner invocation to keep runs isolated. Use the file to audit why the winning plan beat the alternatives or to reproduce scoring decisions during development.
