# Test suite layout

The Bats suite focuses on high-signal coverage for the core runtime and
portable tools:

- `core/`: planner and configuration helpers that drive end-user behavior.
- `executor/`: planner/executor handoff, allowlists, and arg-fill validation.
- `lib/`: shared runtime utilities (logging, state, validation, formatting).
- `planner/` and `planning/`: planner schema and prompt-normalization behavior.
- `tools/`: shared tool registry and cross-platform helpers.
- `runtime/`: targeted smoke tests for platform-specific flows.
- `install/`: Homebrew formula checks.

## Running tests

From the repository root, run the entire suite:

```bash
bash ./scripts/ci/run-bats.sh
```

You can target a specific area by running a directory directly, such as:

```bash
bats --verbose-run tests/core/*.sh
bats --verbose-run tests/tools/*.sh
```

Most CLI and runtime tests rely on `tests/fixtures/mock_llama_relevance.sh` as
the default `LLAMA_BIN`. Set `LLAMA_BIN` explicitly to point at a real binary
or the mock when debugging locally.
