# Configuration

Defaults live in `${XDG_CONFIG_HOME:-~/.config}/okso/config.env`. Create or update that file without running a query:

```bash
./src/bin/okso init --planner-model bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf \
  --react-model bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf \
  --model-branch main
```

The config file is `KEY=value` style, with values shell-escaped so the file can
be `source`d directly by bash without extra trimming. `okso init` preserves
spaces and other special characters when writing strings, such as model specs.
Supported keys:

```
PLANNER_MODEL_SPEC=bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf
PLANNER_MODEL_BRANCH=main
REACT_MODEL_SPEC=bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf
REACT_MODEL_BRANCH=main
OKSO_CACHE_DIR=${XDG_CACHE_HOME:-~/.cache}/okso
OKSO_PLANNER_CACHE_FILE=${OKSO_CACHE_DIR}/planner.prompt-cache
OKSO_REACT_CACHE_FILE=${OKSO_CACHE_DIR}/runs/${OKSO_RUN_ID}/react.prompt-cache
OKSO_RUN_ID=20240101T000000Z
VERBOSITY=1
APPROVE_ALL=false
FORCE_CONFIRM=false
LLAMA_DEFAULT_CONTEXT_SIZE=4096
LLAMA_CONTEXT_CAP=8192
LLAMA_CONTEXT_MARGIN_PERCENT=15
PLANNER_SAMPLE_COUNT=3
PLANNER_TEMPERATURE=0.2
PLANNER_MAX_OUTPUT_TOKENS=1024
PLANNER_DEBUG_LOG=${TMPDIR:-/tmp}/okso_planner_candidates.log
```

- `PLANNER_MODEL_SPEC`: Hugging Face `repo[:file]` identifier for the planning llama.cpp model (default: `bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf`).
- `PLANNER_MODEL_BRANCH`: Optional branch or tag for the planner download (default: `main`).
- `REACT_MODEL_SPEC`: Hugging Face `repo[:file]` identifier for the ReAct llama.cpp model (default: `bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf`).
- `REACT_MODEL_BRANCH`: Optional branch or tag for the ReAct download (default: `main`).
- `OKSO_CACHE_DIR`: Base directory for llama.cpp prompt caches (default: `${XDG_CACHE_HOME:-~/.cache}/okso`).
- `OKSO_PLANNER_CACHE_FILE`: Prompt cache for planner llama.cpp calls (default: `${OKSO_CACHE_DIR}/planner.prompt-cache`).
- `OKSO_REACT_CACHE_FILE`: Prompt cache for the ReAct loop (default: `${OKSO_CACHE_DIR}/runs/${OKSO_RUN_ID}/react.prompt-cache`).
- `OKSO_RUN_ID`: Run identifier used to scope the ReAct prompt cache (default: UTC timestamp). Override to reuse a run-scoped cache across invocations.
- `LLAMA_BIN`: Path to the llama.cpp binary used for scoring (default: `llama-cli`).
- `LLAMA_DEFAULT_CONTEXT_SIZE`: Assumed default llama.cpp context window used when no override is requested (default: `4096`).
- `LLAMA_CONTEXT_CAP`: Maximum context window okso will request for llama.cpp invocations (default: `8192`).
- `LLAMA_CONTEXT_MARGIN_PERCENT`: Safety margin percentage applied to prompt + generation estimates when sizing context (default: `15`).
- `PLANNER_SAMPLE_COUNT`: Number of planner generations to sample before selecting a plan (default: `3`).
- `PLANNER_TEMPERATURE`: Temperature passed to planner llama.cpp generations (default: `0.2`).
- `PLANNER_MAX_OUTPUT_TOKENS`: Maximum tokens the planner requests from llama.cpp when drafting a plan (default: `1024`).
- `PLANNER_MAX_PLAN_STEPS`: Maximum allowed planner steps (including `final_answer`) before scoring penalties apply (default: `6`).
- `PLANNER_DEBUG_LOG`: Path to a JSONL file containing planner candidate plans and scores for troubleshooting (default: `${TMPDIR:-/tmp}/okso_planner_candidates.log`).
- `LLAMA_TEMPERATURE`: Temperature forwarded to llama.cpp inference; overrides tool-specific defaults when set.
- `TESTING_PASSTHROUGH`: `true` to bypass llama.cpp for offline or deterministic runs.
- `APPROVE_ALL`: `true` to skip prompts by default.
- `FORCE_CONFIRM`: `true` to always prompt, even when approvals are automatic.
- `VERBOSITY`: `0` (quiet), `1` (info), `2` (debug).
- `OKSO_GOOGLE_CSE_API_KEY`: Google Custom Search API key used by the `web_search` tool.
- `OKSO_GOOGLE_CSE_ID`: Google Custom Search Engine ID used by the `web_search` tool.

Environment variables with the same names as the config keys take precedence over file values when set. Google Custom Search credentials can also be provided via `OKSO_GOOGLE_CSE_API_KEY` and `OKSO_GOOGLE_CSE_ID`.

Planner sampling runs `PLANNER_SAMPLE_COUNT` generations at `PLANNER_TEMPERATURE` and logs each normalized candidate to `PLANNER_DEBUG_LOG` alongside its score, tie-breaker, and rationale. Lowering the temperature generally produces narrower plans, while increasing it explores more tool combinations. Candidates outside the `PLANNER_MAX_PLAN_STEPS` budget, that omit the final `final_answer` step, or that reference unknown tools drop in score and are unlikely to win when the best plan is selected.

ReAct runs create a cache directory under `${OKSO_CACHE_DIR}/runs/${OKSO_RUN_ID}` for the duration of the invocation. Successful runs remove that directory, while failures keep it intact for debugging.

API keys and other secrets belong in `~/.config/okso/config.env` or a locally sourced `.env` file—never commit them to version control. Consider adding local files containing secrets to `.gitignore` if you keep them alongside your working directory.

See the [Initialize config for a custom model](../user-guides/usage.md#initialize-config-for-a-custom-model) walkthrough for a step-by-step example that combines `okso init` with environment overrides.
