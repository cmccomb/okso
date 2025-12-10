# Testing

The repository uses Bats for shell-based unit and integration coverage. Run the formatter and lint steps first to catch style
issues that can mask test failures:

```bash
shfmt -w src/*.sh src/tools/*.sh src/tools/notes/*.sh tests/*.bats tests/test_all.sh tests/test_install.bats tests/test_main.bats tests/test_modules.bats tests/test_notes.bats scripts/install.sh
shellcheck src/*.sh src/tools/*.sh src/tools/notes/*.sh tests/*.bats tests/test_all.sh tests/test_install.bats tests/test_main.bats tests/test_modules.bats tests/test_notes.bats scripts/install.sh
```

Execute the core suite with:

```bash
bats tests/test_all.sh tests/test_install.bats tests/test_main.bats tests/test_modules.bats tests/test_notes.bats
```

Set `TESTING_PASSTHROUGH=true` to disable llama.cpp invocation while preserving deterministic tool-planning behavior. The
`tests/fixtures/mock_llama.sh` helper provides stable scoring during runs, and `LLAMA_BIN` can point at that script for offline
verification. For aggregate reporting, run `./scripts/coverage.sh` to produce HTML and XML coverage artifacts in `coverage/`.
