# Final answer evaluation

The executor can run a lightweight evaluation pass before emitting the final response. When enabled, the helper sends a structured prompt to `llama.cpp` and expects a schema-constrained JSON object that either returns the final answer (`FINAL`) or requests replanning (`REPLAN`). The evaluator is used to produce the final answer whenever it is available, while replanning continues to be optional and bounded to a single retry.

## Components

- Evaluation helper: `src/lib/validation/validation.sh`
- Schema: `src/schemas/final_answer_evaluation.schema.json`
- Integration point: `evaluate_and_optionally_replan()` in `src/lib/executor/history.sh`

## Flow

1. The `final_answer` plan step has no arguments and immediately invokes `evaluate_final_answer_against_query()` to generate the response when evaluation is enabled.
2. The evaluator uses `src/prompts/final_answer_evaluation.md` and the schema in `src/schemas/final_answer_evaluation.schema.json` to return `FINAL` with the best possible response text or `REPLAN` when the trace is insufficient.
3. The helper logs the structured result and updates executor state flags:
   - `answer_validation_failed=true` when the evaluator returns `REPLAN`
   - `validation_failure_reason` populated with the model-provided reasoning, when available
   - `final_answer` replaced with the evaluator `output` when the evaluator returns `FINAL`
4. When the evaluator returns `REPLAN`, the executor logs the reasoning, stores it on state, and forwards the feedback into a fresh planner+executor cycle so the user receives a revised answer. Replanning only runs once per executor invocation and resets the plan outline, history, and allowed tools before executing the replacement plan.
5. The executor prints the final answer and execution summary regardless of evaluation outcome, keeping the user-facing flow predictable when validation is unavailable.

Because the evaluator output already conforms to the JSON schema, no additional Bash-side validation is performed beyond type-friendly parsing.

## Configuration

- `ENABLE_ANSWER_VALIDATION` (default: `true`): disable to skip the validation call entirely.
- `VALIDATOR_MODEL_SPEC` / `VALIDATOR_MODEL_BRANCH` / `VALIDATOR_CACHE_FILE`: optional overrides for the model and cache used during validation. When unset, the executor model configuration is reused.
- `VALIDATION_MAX_TOKENS` (default: `2048`): max tokens for the evaluator response.

Example:

```bash
export ENABLE_ANSWER_VALIDATION=true
export VALIDATOR_MODEL_SPEC="bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf"
export VALIDATOR_MODEL_BRANCH=main
export VALIDATOR_CACHE_FILE="${HOME}/.cache/okso/validator.promptcache"
```
