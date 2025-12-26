# Test Fixtures

- `sample.env`: example environment configuration for running `./src/bin/okso`.
  When exported, it defaults to a debug-friendly unsupervised mode with a mock llama
  binary and emits a tool prompt highlighting the notes tool for reminder-style
  queries.
- `mock_llama.sh`: deterministic scorer used by the Bats suite. It ranks the
  `notes_create` tool highest by emitting a score of 5 when the prompt includes
  `Tool: notes_create`, and 1 otherwise. The planner summary will therefore start
  with `[notes_create executed]` when called with a reminder query.
- `mock_llama_relevance.sh`: emits a JSON map of tool names to booleans for
  schema-constrained relevance tests.

## macOS tiny-model cache

The macOS GitHub Actions job downloads a small GGUF (`TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF:tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf`) into the default Hugging Face cache under `~/Library/Caches/huggingface/hub`. The cache keeps the runtime Bats test fast while exercising the full `llama.cpp` pipeline. To update the model, edit the `EXECUTOR_MODEL_SPEC`, `EXECUTOR_MODEL_BRANCH` (or the legacy `REACT_*` aliases), and `HF_HOME` entries in `.github/workflows/macos_llama.yml` to point at the new artifact and cache location.
