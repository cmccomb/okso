# Development

## Testing and linting

Run the formatting and lint targets before executing the Bats suite:

```bash
shfmt -w src/*.sh src/tools/*.sh src/tools/notes/*.sh tests/*.bats tests/test_all.sh tests/test_install.bats tests/test_main.bats tests/test_modules.bats tests/test_notes.bats scripts/install.sh
shellcheck src/*.sh src/tools/*.sh src/tools/notes/*.sh tests/*.bats tests/test_all.sh tests/test_install.bats tests/test_main.bats tests/test_modules.bats tests/test_notes.bats scripts/install.sh
bats tests/test_all.sh tests/test_install.bats tests/test_main.bats tests/test_modules.bats tests/test_notes.bats
```

The Bats suite covers CLI help/version output, confirmation prompts, deterministic mock scoring via `tests/fixtures/mock_llama.sh`, and graceful handling when `LLAMA_BIN` is missing.
