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

Environment variables prefixed with `OKSO_` mirror the config keys and take precedence. Legacy `DO_*` aliases remain available for compatibility but prefer the `OKSO_*` names.
