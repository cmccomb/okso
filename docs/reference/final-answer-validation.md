# Iterative Replanning with Final Answer Validation

## Overview

This document describes the iterative replanning capability that has been implemented in okso. The system now includes an automated final answer validation step that checks whether the generated answer satisfies the original user query. If validation fails, the system can optionally trigger replanning with the failed validation reason fed back to the planner.

## Architecture

### Components

1. **Validation Module** (`src/lib/validation/validation.sh`)
   - Core validation logic for checking final answers against user queries
   - Uses an 8B model for efficient validation
   - Structured output via JSON schema

2. **Validation Schema** (`src/schemas/final_answer_validation.schema.json`)
   - Defines the output format for validation results
   - Includes satisfaction boolean and reasoning string

3. **Integration Points**
   - Executor history finalization (`src/lib/executor/history.sh`)
   - Executor loop (`src/lib/executor/loop.sh`)

## Validation Flow

```
User Query
    ↓
Planner generates plan
    ↓
Executor runs tools
    ↓
Final answer captured
    ↓
[NEW] Validation Check ←──── 8B Model
    ├─ Satisfied: Output answer → User
    └─ Not Satisfied: Log failure reason + Trigger replanning
```

## Configuration

### Environment Variables

- **`ENABLE_ANSWER_VALIDATION`** (default: `true`)
  - Enable/disable the validation check entirely
  - Set to `false` to skip validation and use the answer as-is

- **`VALIDATOR_MODEL_REPO`** (default: uses `EXECUTOR_MODEL_REPO`)
  - Hugging Face repository for the validator model
  - Uses executor model if not specified

- **`VALIDATOR_MODEL_FILE`** (default: uses `EXECUTOR_MODEL_FILE`)
  - Model file within the repository
  - Uses executor model if not specified

- **`VALIDATOR_CACHE_FILE`** (default: uses `EXECUTOR_CACHE_FILE`)
  - Prompt cache file for validator inference
  - Uses executor cache if not specified

## Validation Schema

The validation output follows this JSON schema:

```json
{
  "satisfied": boolean,           // Whether answer satisfies query
  "reasoning": string,            // Explanation of validation result (required)
}
```

### Example Validation Output

**Passed Validation:**
```json
{
  "satisfied": true,
  "reasoning": "The answer directly addresses the user's request to find the current time and includes the relevant timezone information.",
}
```

**Failed Validation:**
```json
{
  "satisfied": false,
  "reasoning": "The user asked for a summary of the meeting agenda, but the final answer only provided attendee names without the actual agenda items.",
}
```

## Implementation Details

### Validation Function

Located in `src/lib/validation/validation.sh`:

```bash
validate_final_answer_against_query() {
  # Validates whether a final answer satisfies the original user query.
  # Uses the 8B model to perform validation.
  #
  # Arguments:
  #   $1 - user query (string)
  #   $2 - final answer text (string)
  #   $3 - execution trace/history (string, optional)
  #   $4 - output variable name for validation result (optional)
  #
  # Returns:
  #   0 if answer is validated as satisfied
  #   1 if validation indicates answer doesn't satisfy query
  #   2 if validation infrastructure fails
}
```

### Integration in Executor History

The `validate_and_optionally_replan()` function in `src/lib/executor/history.sh` handles:
1. Calling the validation function
2. Parsing validation results
3. Logging validation outcome and reasoning
4. Setting state flags for replanning
5. Outputting the final answer (whether validated or not)

## Logging

The validation system logs at various levels:

- **INFO**: Validation started, result (passed/failed), reasoning
- **WARN**: Validation failed, validation infrastructure errors
- **DEBUG**: Full validation result JSON

Example log output:
```
INFO: Running final answer validation
WARN: Final answer validation failed; answer may not satisfy query
INFO: Validation reasoning: The answer did not include the requested date range.
WARN: validation_failure_reason: The answer did not include the requested date range.
INFO: Final answer passed validation
```

## Iterative Replanning Implementation

### Current Design

When validation fails, the system currently:
1. Logs the failure reason
2. Sets state flags (`answer_validation_failed`, `validation_failure_reason`)
3. Outputs the answer anyway (graceful degradation)

### Future Enhancement: Automatic Replanning Loop

To implement full iterative replanning (automatic plan regeneration when validation fails), you would:

1. **Modify the main orchestrator** (`src/bin/okso` or `src/lib/runtime.sh`):
   ```bash
   while [[ ${replan_attempts} -lt ${MAX_REPLAN_ATTEMPTS} ]]; do
     executor_loop ...
     if state validation failed && replan_attempts < max:
       validation_reason=$(state_get validation_failure_reason)
       # Feed validation reason back to planner
       plan_response=$(generate_planner_response \
         "Original query: ${user_query}. Previous attempt failed: ${validation_reason}")
       # Re-run executor with new plan
     else
       break
     fi
   done
   ```

2. **Enhance planner prompt context** to include prior failed validation reasons:
   ```
   Previous attempt: [final answer]
   Validation feedback: [reason why it failed]
   Please generate a new plan that addresses this feedback.
   ```

3. **Track replanning metrics**:
   - Number of replan attempts
   - Validation failure reasons across iterations
   - Final success/failure status

## Testing

Test cases should verify:

1. **Validation succeeds** when answer satisfies query
2. **Validation fails** when answer doesn't satisfy query
3. **Validation handles errors gracefully** (missing model, schema issues)
4. **State flags are set correctly** for failed validations
5. **Final answer is output regardless** of validation status

Example test:
```bash
@test "validate_final_answer returns 0 for satisfying answer" {
  LLAMA_AVAILABLE=true
  user_query="What is the capital of France?"
  final_answer="The capital of France is Paris."
  
  validate_final_answer_against_query "$user_query" "$final_answer"
  [ "$?" -eq 0 ]
}
```

## Performance Considerations

1. **Model Selection**: Uses the 8B model (typically 4-6GB) for efficiency
2. **Inference Cost**: Adds one additional LLM inference call per execution
3. **Caching**: Supports prompt caching via `VALIDATOR_CACHE_FILE` to reduce repeated inference costs

## Troubleshooting

### Validation Skipped
- Check `LLAMA_AVAILABLE` is true
- Verify validator model is properly configured
- Check logs for schema loading errors

### Validation Always Fails
- Verify the 8B model is functioning correctly
- Check validation prompt quality
- Review model's understanding of the domain

### Performance Issues
- Enable prompt caching via `VALIDATOR_CACHE_FILE`
- Use a smaller model if available
- Consider disabling validation with `ENABLE_ANSWER_VALIDATION=false`

## Example Usage

```bash
# Enable validation with custom validator model
export ENABLE_ANSWER_VALIDATION=true
export VALIDATOR_MODEL_REPO="meta/llama-8b"
export VALIDATOR_MODEL_FILE="model.gguf"
export VALIDATOR_CACHE_FILE="/tmp/validator.cache"

# Run okso with validation enabled
./src/bin/okso -- "Your question here"

# Check state for validation results
# If validation failed, answer_validation_failed=true will be set
# And validation_failure_reason will contain the failure explanation
```

## Future Enhancements

2. **User feedback loop**: Allow user to provide feedback on validation
3. **Multi-criteria validation**: Validate multiple aspects (accuracy, completeness, clarity)
4. **Validation strategies**: Different validation approaches for different query types
5. **Learning from failures**: Track validation patterns to improve planning

