# Development

## Formatting, linting, and tests

Run the same checks used by CI:

```bash
find src scripts tests -type f \( -name '*.sh' -o -name 'okso' \) -print0 | xargs -0 shfmt -d
bash ./scripts/ci/run-shellcheck.sh
bash ./scripts/ci/run-bats.sh
bash ./scripts/ci/check-docs.sh
```

The suite covers CLI help/version output, confirmation prompts, deterministic mock scoring via `tests/fixtures/mock_llama_relevance.sh`, and graceful handling when `LLAMA_BIN` is missing. Set `TESTING_PASSTHROUGH=true` to bypass llama.cpp during tests while keeping deterministic planner behavior.

## Planning workflow

The planner drives execution through a structured outline:

1. `generate_planner_response` prompts the model with the tool catalog to produce a tool-based plan array that ends with `final_answer`.
2. `derive_allowed_tools_from_plan` converts the structured plan into the allowed tool list.
3. `plan_json_to_entries` prepares newline-delimited entries for the executor loop while preserving the outline for tool-based plans.
4. The executor loop executes tools in order and finishes when the `final_answer` tool runs.

### Dependencies

Runtime helpers require `jq` and exit with a structured dependency error when it is unavailable. Install `jq` locally before running scripts.
