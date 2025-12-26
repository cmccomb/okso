# Development

## Formatting, linting, and tests

Run the format and lint steps before the Bats suite:

```bash
find src scripts tests -type f \( -name '*.sh' -o -name 'okso' \) -print0 | xargs -0 shfmt -w
find src scripts tests -type f \( -name '*.sh' -o -name 'okso' \) -print0 | xargs -0 shellcheck
bats tests/core/test_planner.sh tests/tools/test_registry.sh tests/runtime/test_macos_tiny_llama.sh
```

The suite covers CLI help/version output, confirmation prompts, deterministic mock scoring via `tests/fixtures/mock_llama.sh`, and graceful handling when `LLAMA_BIN` is missing. Set `TESTING_PASSTHROUGH=true` to bypass llama.cpp during tests while keeping deterministic planner behavior.

### Coverage

Generate HTML, JSON, and Cobertura coverage reports with bashcov:

```bash
./scripts/coverage.sh
```

Artifacts are written to `coverage/`. Set `COVERAGE_THRESHOLD=75` to warn when totals dip below 75%, and enable `COVERAGE_STRICT=true` to fail the run when the threshold is not met.

## Planning workflow

The planner drives execution through a structured outline:

1. `generate_planner_response` prompts the model with the tool catalog to produce a tool-based plan object whose `plan` array ends with `final_answer`.
2. `derive_allowed_tools_from_plan` converts the structured plan into the allowed tool list, expanding `executor_fallback` to the full catalog.
3. `plan_json_to_entries` prepares newline-delimited entries for the ReAct loop while preserving the outline for tool-based plans.
4. The ReAct loop executes tools in order and finishes when the `final_answer` tool runs.

### Dependencies

Runtime helpers require `jq` and exit with a structured dependency error when it is unavailable. Install `jq` locally before running scripts.
