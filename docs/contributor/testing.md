# Testing

Bats provides unit and integration coverage for the shell scripts. Run formatting and linting first to avoid masking failures:

```bash
find src scripts tests -type f \( -name '*.sh' -o -name 'okso' \) -print0 | xargs -0 shfmt -d
bash ./scripts/ci/run-shellcheck.sh
```

Execute the full suite:

```bash
bash ./scripts/ci/run-bats.sh
```

Run docs checks before opening a PR:

```bash
bash ./scripts/ci/check-docs.sh
```

Set `TESTING_PASSTHROUGH=true` to disable llama.cpp calls while keeping deterministic tool-planning behavior. Point `LLAMA_BIN` at `tests/fixtures/mock_llama_relevance.sh` for stable scoring during offline runs.
