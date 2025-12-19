# Testing

Bats provides unit and integration coverage for the shell scripts. Run formatting and linting first to avoid masking failures:

```bash
find src scripts tests -type f \( -name '*.sh' -o -name 'okso' \) -print0 | xargs -0 shfmt -w
find src scripts tests -type f \( -name '*.sh' -o -name 'okso' \) -print0 | xargs -0 shellcheck
```

Execute the core suite:

```bash
bats tests/core/test_planner.sh tests/tools/test_registry.sh tests/runtime/test_macos_tiny_llama.sh
```

Set `TESTING_PASSTHROUGH=true` to disable llama.cpp calls while keeping deterministic tool-planning behavior. Point `LLAMA_BIN` at `tests/fixtures/mock_llama.sh` for stable scoring during offline runs. Generate aggregate coverage with:

```bash
./scripts/coverage.sh
```

Coverage artifacts land in `coverage/` (HTML, XML, and JSON).
