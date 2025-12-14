# Test suite layout

The Bats suite focuses on high-signal coverage for the core runtime and
portable tools:

- `core/`: planner and configuration helpers that drive end-user behavior.
- `tools/`: shared tool registry and cross-platform helpers.
- `runtime/`: targeted smoke tests for platform-specific flows.
- `tools_python_repl.bats`: sandbox coverage for the Python REPL helper.

## Running tests

From the repository root, run the entire suite:

```bash
bats tests
```

You can target a specific area by running a directory directly, such as:

```bash
bats tests/core
bats tests/tools
```

Most CLI and runtime tests rely on `tests/fixtures/mock_llama_relevance.sh` as
the default `LLAMA_BIN`. Set `LLAMA_BIN` explicitly to point at a real binary
or the mock when debugging locally. The helper modules in `tests/helpers/` are
available via relative `load ../helpers/<helper>` statements from within a
suite.
