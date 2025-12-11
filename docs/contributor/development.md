# Development

## Formatting, linting, and tests

Run the format and lint steps before the Bats suite:

```bash
find src scripts tests -type f \( -name '*.sh' -o -name '*.bats' -o -name 'okso' \) -print0 | xargs -0 shfmt -w
find src scripts tests -type f \( -name '*.sh' -o -name '*.bats' -o -name 'okso' \) -print0 | xargs -0 shellcheck
bats tests/cli/test_all.sh tests/cli/test_install.sh tests/cli/test_main.sh tests/core/test_modules.sh tests/tools/test_notes.sh
```

The suite covers CLI help/version output, confirmation prompts, deterministic mock scoring via `tests/fixtures/mock_llama.sh`, and graceful handling when `LLAMA_BIN` is missing. Set `TESTING_PASSTHROUGH=true` to bypass llama.cpp during tests while keeping deterministic planner behavior.

### Coverage

Generate HTML, JSON, and Cobertura coverage reports with bashcov:

```bash
./scripts/coverage.sh
```

Artifacts are written to `coverage/`. Set `COVERAGE_THRESHOLD=75` to warn when totals dip below 75%, and enable `COVERAGE_STRICT=true` to fail the run when the threshold is not met.

## Planning workflow

The planner drives execution through an outline:

1. `generate_plan_outline` prompts the model with the tool catalog to produce a numbered plan that ends with `final_answer`.
2. `extract_tools_from_plan` reads the outline to build the allowed tool list.
3. `build_plan_entries_from_tools` derives concrete tool queries for the ReAct loop while preserving the outline.
4. The ReAct loop executes tools in order and finishes when the `final_answer` tool runs.

### Dependencies

Runtime helpers require `jq` and exit with a structured dependency error when it is unavailable. Install `jq` locally before running scripts.
