# Final answer validation

The executor can run a lightweight validation pass before emitting the final response. When enabled, the helper sends a structured prompt to `llama.cpp` and expects a schema-constrained JSON object that indicates whether the answer satisfies the original query. Validation never blocks output: the executor always prints the answer and summary while optionally annotating state for consumers.

## Components

- Validation helper: `src/lib/validation/validation.sh`
- Schema: `src/schemas/final_answer_verification.schema.json`
- Integration point: `validate_and_optionally_replan()` in `src/lib/executor/history.sh`

## Flow

1. `finalize_executor_result()` builds the final answer from tool output or the `final_answer` action.
2. When `ENABLE_ANSWER_VALIDATION=true` and `LLAMA_AVAILABLE=true`, `validate_final_answer_against_query()` renders the prompt from `src/prompts/final_answer_verification.md` and calls `llama_infer` with the validation schema.
3. The helper logs the structured result and updates executor state flags:
   - `answer_validation_failed=true` when the validator returns `satisfied: false`
   - `validation_failure_reason` populated with the model-provided reasoning, when available
4. The executor prints the final answer and execution summary regardless of validation outcome, keeping the user-facing flow predictable.

Because the validator output already conforms to the JSON schema, no additional Bash-side validation is performed beyond type-friendly parsing.

## Configuration

- `ENABLE_ANSWER_VALIDATION` (default: `true`): disable to skip the validation call entirely.
- `VALIDATOR_MODEL_REPO` / `VALIDATOR_MODEL_FILE` / `VALIDATOR_CACHE_FILE`: optional overrides for the model and cache used during validation. When unset, the executor model configuration is reused.

Example:

```bash
export ENABLE_ANSWER_VALIDATION=true
export VALIDATOR_MODEL_REPO="bartowski/Qwen_Qwen3-4B-GGUF"
export VALIDATOR_MODEL_FILE="Qwen_Qwen3-4B-Q4_K_M.gguf"
export VALIDATOR_CACHE_FILE="${HOME}/.cache/okso/validator.promptcache"
```

