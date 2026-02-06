# Configuration

Defaults live in `${XDG_CONFIG_HOME:-~/.config}/okso/config.env`. Create or update that file without running a query:

```bash
export PLANNER_MODEL_SPEC="bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf"
export EXECUTOR_MODEL_SPEC="bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf"
export SEARCH_REPHRASER_MODEL_SPEC="bartowski/Qwen_Qwen3-1.7B-GGUF:Qwen_Qwen3-1.7B-Q4_K_M.gguf"
export PLANNER_MODEL_BRANCH=main
export EXECUTOR_MODEL_BRANCH=main
export SEARCH_REPHRASER_MODEL_BRANCH=main
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/okso/config.env" ./src/bin/okso init
```

The config file is `KEY=value` style, with values shell-escaped so the file can
be `source`d directly by bash without extra trimming. `okso init` preserves
spaces and other special characters when writing strings, such as model specs.
Supported keys stored in `config.env`:

```
PLANNER_MODEL_SPEC=bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf
PLANNER_MODEL_BRANCH=main
EXECUTOR_MODEL_SPEC=bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf
EXECUTOR_MODEL_BRANCH=main
VALIDATOR_MODEL_SPEC=bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf
VALIDATOR_MODEL_BRANCH=main
CACHE_DIR=${XDG_CACHE_HOME:-${HOME}/.cache}/okso
SEARCH_REPHRASER_MODEL_SPEC=bartowski/Qwen_Qwen3-1.7B-GGUF:Qwen_Qwen3-1.7B-Q4_K_M.gguf
SEARCH_REPHRASER_MODEL_BRANCH=main
VERBOSITY=1
APPROVE_ALL=false
```

Defaults for the model specs are derived from the system profile autotune logic (see the [model autotuning](../../README.md#model-autotuning) overview for tier-to-size mappings). Use these keys to pin specific repos or branches:

- `PLANNER_MODEL_SPEC`: Hugging Face `repo[:file]` identifier for the planning llama.cpp model.
- `PLANNER_MODEL_BRANCH`: Branch or tag for the planner download.
- `EXECUTOR_MODEL_SPEC`: Hugging Face `repo[:file]` identifier for the executor llama.cpp model.
- `EXECUTOR_MODEL_BRANCH`: Branch or tag for the executor download.
- `SEARCH_REPHRASER_MODEL_SPEC`: Hugging Face `repo[:file]` identifier for the search rephraser llama.cpp model.
- `SEARCH_REPHRASER_MODEL_BRANCH`: Branch or tag for the rephraser download.
- `VALIDATOR_MODEL_SPEC`: Hugging Face `repo[:file]` identifier for the final-answer evaluator model.
- `VALIDATOR_MODEL_BRANCH`: Branch or tag for the evaluator download.
- `CACHE_DIR`: Base directory for prompt caches (runtime currently recomputes this from `OKSO_CACHE_DIR` or the default path, so set `OKSO_CACHE_DIR` when you need to change the cache location).
- `APPROVE_ALL`: `true` to skip prompts by default.
- `VERBOSITY`: `0` (quiet), `1` (info), `2` (debug).

Environment variables with the same names as the config keys take precedence over file values when set. Additional environment-only controls include:

- `CONFIG_FILE`: Override the config path used by `okso init` and runtime loads.
- `OKSO_CACHE_DIR`: Override the prompt cache directory.
- `OKSO_RUN_ID`: Run identifier used to scope executor caches (default: UTC timestamp).
- `OKSO_NOTES_DIR`: Override the local notes storage directory (default: `${HOME}/.okso`).
- `LLAMA_BIN`: Path to the llama.cpp binary used for inference (default: `llama-completion`).
- `LLAMA_DEFAULT_CONTEXT_SIZE`: Assumed default llama.cpp context window used when no override is requested (default: `4096`).
- `LLAMA_CONTEXT_CAP`: Maximum context window okso will request for llama.cpp invocations (default: `8192`).
- `LLAMA_CONTEXT_MARGIN_PERCENT`: Safety margin percentage applied to prompt + generation estimates when sizing context (default: `15`).
- `LLAMA_TIMEOUT_SECONDS`: Hard timeout for llama.cpp invocations; `0` disables the timeout (default: `0`).
- `LLAMA_TEMPLATE`: Optional llama.cpp prompt template name.
- `LLAMA_GRAMMAR`: Optional llama.cpp grammar file path.
- `LLAMA_ROPE_FREQ_BASE`: Optional RoPE base override for llama.cpp.
- `LLAMA_ROPE_FREQ_SCALE`: Optional RoPE scale override for llama.cpp.
- `LLAMA_EXTRA_ARGS`: Extra llama.cpp CLI args appended to each invocation.
- `PLANNER_SAMPLE_COUNT`: Number of planner generations to sample before selecting a plan (currently pinned to `1` in `planner.sh`).
- `PLANNER_TEMPERATURE`: Temperature passed to planner llama.cpp generations (default: `0.7`).
- `PLANNER_MAX_OUTPUT_TOKENS`: Maximum tokens the planner requests from llama.cpp when drafting a plan (default: `1024`).
- `PLANNER_MAX_PLAN_STEPS`: Maximum allowed planner steps (including `final_answer`) before scoring penalties apply (default: `6`).
- `PLANNER_DEBUG_LOG`: Path to a JSONL file containing planner candidate plans and scores for troubleshooting (default: `${TMPDIR:-/tmp}/okso_planner_candidates.log`).
- `INTENT_MODEL_REPO`: Hugging Face repository for intent recognition; defaults to the planner model when unset (requires `INTENT_MODEL_FILE` when set explicitly).
- `INTENT_MODEL_FILE`: GGUF filename for intent recognition; defaults to the planner model file when unset.
- `INTENT_CACHE_FILE`: Prompt cache file for intent recognition (default: `${XDG_CACHE_HOME:-${HOME}/.cache}/okso/intent.prompt-cache`; `OKSO_INTENT_CACHE_FILE` is also accepted).
- `INTENT_MAX_OUTPUT_TOKENS`: Maximum tokens requested from llama.cpp for intent recognition (default: `256`).
- `INTENT_DISABLE_SEARCH`: When `true`, skip the pre-planner search stage regardless of intent (default: `false`).
- `LLAMA_TEMPERATURE`: Temperature forwarded to llama.cpp inference; overrides tool-specific defaults when set.
- `TESTING_PASSTHROUGH`: `true` to bypass llama.cpp for offline runs; note that planner generation still requires llama.cpp unless you stub planner output in tests.
- `REPHRASER_MAX_OUTPUT_TOKENS`: Maximum tokens for search rephrasing (default: `256`).
- `SEARCH_REPHRASER_DRY_ARGS`: Extra dry-run sampling args for search rephrasing (default: `--dry-multiplier 0.35 --dry-base 1.75 --dry-allowed-length 2 --dry-penalty-last-n 1024 --dry-sequence-breaker none`).
- `SEARCH_REPHRASER_CACHE_FILE`: Prompt cache file for the search rephraser (no default unless set explicitly).
- `PLANNER_CACHE_FILE`: Prompt cache file for planner llama.cpp calls (no default unless set explicitly).
- `EXECUTOR_CACHE_FILE`: Prompt cache file for executor llama.cpp calls (no default unless set explicitly).
- `VALIDATOR_CACHE_FILE`: Prompt cache file for final-answer validation (defaults to `EXECUTOR_CACHE_FILE` when set).
- `ENABLE_ANSWER_VALIDATION`: `true` to run final-answer evaluation (default: `true`).
- `VALIDATION_MAX_TOKENS`: Maximum tokens for the evaluator response (default: `2048`).
- `GOOGLE_SEARCH_API_KEY`: Google Custom Search API key used by the `web_search` tool (optional; falls back to the bundled key when unset).
- `GOOGLE_SEARCH_CX`: Google Custom Search Engine ID used by the `web_search` tool (optional; falls back to the bundled CX when unset).

Planner sampling currently generates a single candidate per run (with `PLANNER_SAMPLE_COUNT` pinned to `1`), logs the normalized candidate to `PLANNER_DEBUG_LOG`, and records its score, tie-breaker, and rationale. Lowering the temperature generally produces narrower plans, while increasing it explores more tool combinations. Candidates outside the `PLANNER_MAX_PLAN_STEPS` budget, that omit the final `final_answer` step, or that reference unknown tools drop in score and are unlikely to win when the best plan is selected.

API keys and other secrets belong in `~/.config/okso/config.env` or a locally sourced `.env` file—never commit them to version control. Consider adding local files containing secrets to `.gitignore` if you keep them alongside your working directory.

See the [Initialize config for a custom model](../user-guides/usage.md#initialize-config-for-a-custom-model) walkthrough for a step-by-step example that combines `okso init` with environment overrides.
