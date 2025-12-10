# Development

## Testing and linting

Run the formatting and lint targets before executing the Bats suite:

```bash
find src scripts tests -type f \( -name '*.sh' -o -name '*.bats' -o -name 'okso' \) -print0 | xargs -0 shfmt -w
find src scripts tests -type f \( -name '*.sh' -o -name '*.bats' -o -name 'okso' \) -print0 | xargs -0 shellcheck
bats tests/test_all.sh tests/test_install.bats tests/test_main.bats tests/test_modules.bats tests/test_notes.bats
```

The Bats suite covers CLI help/version output, confirmation prompts, deterministic mock scoring via `tests/fixtures/mock_llama.sh`, and graceful handling when `LLAMA_BIN` is missing.

Set `TESTING_PASSTHROUGH=true` when running the suite to disable llama.cpp invocation and surface test-only code paths without muting runtime errors that depend on llama availability.

### Coverage collection

Generate HTML, JSON, and Cobertura coverage reports with bashcov:

```bash
./scripts/coverage.sh
```

Artifacts are written to `coverage/` (HTML + XML + JSON). Set `COVERAGE_THRESHOLD=75` to warn when totals dip below 75%, and enable `COVERAGE_STRICT=true` to fail the run when the threshold is not met. The script defaults to `TESTING_PASSTHROUGH=false` while pointing `LLAMA_BIN` at the mocked binary used in tests.

## Planning workflow

The planner now drives execution through an explicit, tool-aware outline:

1. `generate_plan_outline` prompts the model with the full tool catalog to produce a numbered, high-level plan that explicitly names tools and always ends with `final_answer`.
2. `extract_tools_from_plan` reads that outline to build the allowed tool list (ensuring `final_answer` is available for the final handoff).
3. `build_plan_entries_from_tools` derives concrete tool queries for the React loop while preserving the outline for agent guidance.
4. The React loop executes tools in sequence, adapting after each observation until the `final_answer` tool is invoked.
