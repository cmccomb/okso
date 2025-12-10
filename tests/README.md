# Test suite layout

The Bats suite is organized into focused subdirectories to make it easier to find and extend coverage:

- `cli/`: top-level command entry points, installer flows, and user-facing flags (`okso --help`, setup flows, etc.).
- `core/`: shared libraries such as config, prompts, planner utilities, and other non-tool helpers.
- `runtime/`: scenarios that exercise the orchestration/runtime loop or integration against local models.
- `tools/`: individual tool behaviors and registries (clipboard, calendar, terminal, notes, etc.).
- `helpers/` and `lib/`: shared Bats helpers and stubs used across suites.
- `fixtures/`: static test data and mock binaries (e.g., the llama relevance stub).
- `install/`: installer-specific integration coverage.

## Running tests

From the repository root, execute the suites directly to focus on a particular area:

```bash
bats tests/cli
bats tests/core
bats tests/runtime
bats tests/tools
```

Most CLI and runtime tests rely on `tests/fixtures/mock_llama_relevance.sh` as the default `LLAMA_BIN`. Set `LLAMA_BIN` explicitly to point at a real binary or the mock when debugging locally. The helper modules in `tests/helpers/` are available via relative `load ../helpers/<helper>` statements from within a suite.

For aggregate coverage, use `./scripts/coverage.sh`, which targets representative tests from each suite.
