# Configuration

Defaults live in `${XDG_CONFIG_HOME:-~/.config}/okso/config.env`. Create or update that file without running a query:

```bash
./src/bin/okso init --model your-org/your-model:custom.gguf --model-branch main
```

The config file is `KEY="value"` style. Supported keys:

- `MODEL_SPEC`: Hugging Face `repo[:file]` identifier for the llama.cpp model (default: `bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf`).
- `MODEL_BRANCH`: Optional branch or tag for the model download (default: `main`).
- `LLAMA_BIN`: Path to the llama.cpp binary used for scoring (default: `llama-cli`).
- `TESTING_PASSTHROUGH`: `true` to bypass llama.cpp for offline or deterministic runs.
- `APPROVE_ALL`: `true` to skip prompts by default.
- `FORCE_CONFIRM`: `true` to always prompt, even when approvals are automatic.
- `VERBOSITY`: `0` (quiet), `1` (info), `2` (debug).
- `OKSO_GOOGLE_CSE_API_KEY`: Google Custom Search API key used by the `web_search` tool.
- `OKSO_GOOGLE_CSE_ID`: Google Custom Search Engine ID used by the `web_search` tool.

Environment variables prefixed with `OKSO_` mirror the config keys and take precedence over file values.

API keys and other secrets belong in `~/.config/okso/config.env` or a locally sourced `.env` file—never commit them to version control. Consider adding local files containing secrets to `.gitignore` if you keep them alongside your working directory.

See the [Initialize config for a custom model](../user-guides/usage.md#initialize-config-for-a-custom-model) walkthrough for a step-by-step example that combines `okso init` with environment overrides.
