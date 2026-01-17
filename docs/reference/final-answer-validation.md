# Final answer evaluation

The executor can run a lightweight evaluation pass before emitting the final response. When enabled, the helper sends a structured prompt to `llama.cpp` and expects a schema-constrained JSON object that selects whether the answer should pass through, be rephrased, or trigger replanning. Evaluation never blocks output: the executor always prints the answer and summary while optionally annotating state for consumers.

## Components

- Evaluation helper: `src/lib/validation/validation.sh`
- Schema: `src/schemas/final_answer_evaluation.schema.json`
- Integration point: `evaluate_and_optionally_replan()` in `src/lib/executor/history.sh`

## Flow

1. `finalize_executor_result()` builds the final answer from tool output or the `final_answer` action.
2. When `ENABLE_ANSWER_VALIDATION=true` and `LLAMA_AVAILABLE=true`, `evaluate_final_answer_against_query()` renders the prompt from `src/prompts/final_answer_evaluation.md` and calls `llama_infer` with the evaluation schema.
3. The helper logs the structured result and updates executor state flags:
   - `answer_validation_failed=true` when the evaluator returns `REPLAN`
   - `validation_failure_reason` populated with the model-provided reasoning, when available
   - `final_answer` replaced only when the evaluator returns `REPHRASE`
4. When the evaluator returns `REPLAN`, the executor logs the reasoning, stores it on state, and
   forwards the feedback into a fresh planner+executor cycle so the user receives a revised answer.
   Replanning only runs once per executor invocation and resets the plan outline, history, and
   allowed tools before executing the replacement plan.
5. The executor prints the final answer and execution summary regardless of evaluation outcome,
   keeping the user-facing flow predictable when validation is unavailable or passes.

If the evaluator returns malformed JSON, the helper logs a warning, marks the evaluation as `PASS`, and preserves the original answer. This avoids jq parse errors while keeping user output predictable.

## Configuration

- `ENABLE_ANSWER_VALIDATION` (default: `true`): disable to skip the validation call entirely.
- `VALIDATOR_MODEL_REPO` / `VALIDATOR_MODEL_FILE` / `VALIDATOR_CACHE_FILE`: optional overrides for the model and cache used during validation. When unset, the executor model configuration is reused.
- `VALIDATION_MAX_TOKENS` (default: `2048`): max tokens for the evaluator response.

Example:

```bash
export ENABLE_ANSWER_VALIDATION=true
export VALIDATOR_MODEL_REPO="bartowski/Qwen_Qwen3-4B-GGUF"
export VALIDATOR_MODEL_FILE="Qwen_Qwen3-4B-Q4_K_M.gguf"
export VALIDATOR_CACHE_FILE="${HOME}/.cache/okso/validator.promptcache"
```
