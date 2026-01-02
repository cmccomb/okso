# LLM helpers

This package contains the local-inference and prompt-sizing utilities used across okso’s planner/executor pipeline:

- `tokens.sh` provides a tiny, dependency-free token estimator (character-count heuristic) that higher-level code can use for quick budgeting decisions.
- `context_budget.sh` enforces a prompt budget via `PROMPT_TOKEN_BUDGET` by summarizing/truncating oversized context blocks (preserving line structure and special-casing `Content:` payload lines from fetch-style context).
- `llama_client.sh` is the llama.cpp wrapper: it handles optional timeouts, Hugging Face `--hf-repo/--hf-file` model selection, dynamic context sizing with caps + safety margin, optional constrained decoding via `--json-schema`, and output sanitization for downstream parsing.

These scripts intentionally depend only on small, stable primitives (e.g., `core/logging.sh`, `jq` where needed) so the rest of the system can “estimate”, “budget”, and “infer” without duplicating shell logic or introducing circular dependencies.