# Test Fixtures

- `sample.env`: example environment configuration for running `./src/main.sh`.
  When exported, it defaults to a debug-friendly unsupervised mode with a mock llama
  binary and emits a tool prompt highlighting the notes tool for reminder-style
  queries.
- `mock_llama.sh`: deterministic scorer used by the Bats suite. It ranks the
  `notes_create` tool highest by emitting a score of 5 when the prompt includes
  `Tool: notes_create`, and 1 otherwise. The planner summary will therefore start
  with `[notes_create executed]` when called with a reminder query.
- `mock_llama_relevance.sh`: emits a JSON map of tool names to booleans for
  grammar-constrained relevance tests.
