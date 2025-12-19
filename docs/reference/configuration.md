# Configuration

Defaults live in `${XDG_CONFIG_HOME:-~/.config}/okso/config.env`. Create or update that file without running a query:

```bash
./src/bin/okso init --planner-model bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf \
  --react-model bartowski/Qwen_Qwen3-1.7B-GGUF:Qwen_Qwen3-1.7B-Q4_K_M.gguf \
  --model-branch main
```

The config file is `KEY=value` style, with values shell-escaped so the file can
be `source`d directly by bash without extra trimming. `okso init` preserves
spaces and other special characters when writing strings, such as model specs.
Supported keys:

```
PLANNER_MODEL_SPEC=bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf
PLANNER_MODEL_BRANCH=main
REACT_MODEL_SPEC=bartowski/Qwen_Qwen3-1.7B-GGUF:Qwen_Qwen3-1.7B-Q4_K_M.gguf
REACT_MODEL_BRANCH=main
VERBOSITY=1
APPROVE_ALL=false
FORCE_CONFIRM=false
```

- `PLANNER_MODEL_SPEC`: Hugging Face `repo[:file]` identifier for the planning llama.cpp model (default: `bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf`).
- `PLANNER_MODEL_BRANCH`: Optional branch or tag for the planner download (default: `main`).
- `REACT_MODEL_SPEC`: Hugging Face `repo[:file]` identifier for the ReAct llama.cpp model (default: `bartowski/Qwen_Qwen3-1.7B-GGUF:Qwen_Qwen3-1.7B-Q4_K_M.gguf`).
- `REACT_MODEL_BRANCH`: Optional branch or tag for the ReAct download (default: `main`).
- `LLAMA_BIN`: Path to the llama.cpp binary used for scoring (default: `llama-cli`).
- `TESTING_PASSTHROUGH`: `true` to bypass llama.cpp for offline or deterministic runs.
- `APPROVE_ALL`: `true` to skip prompts by default.
- `FORCE_CONFIRM`: `true` to always prompt, even when approvals are automatic.
- `VERBOSITY`: `0` (quiet), `1` (info), `2` (debug).
- `OKSO_GOOGLE_CSE_API_KEY`: Google Custom Search API key used by the `web_search` tool.
- `OKSO_GOOGLE_CSE_ID`: Google Custom Search Engine ID used by the `web_search` tool.

Environment variables with the same names as the config keys take precedence over file values when set. Google Custom Search credentials can also be provided via `OKSO_GOOGLE_CSE_API_KEY` and `OKSO_GOOGLE_CSE_ID`.

API keys and other secrets belong in `~/.config/okso/config.env` or a locally sourced `.env` file—never commit them to version control. Consider adding local files containing secrets to `.gitignore` if you keep them alongside your working directory.

See the [Initialize config for a custom model](../user-guides/usage.md#initialize-config-for-a-custom-model) walkthrough for a step-by-step example that combines `okso init` with environment overrides.
