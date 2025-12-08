# Configuration

The CLI stores defaults in `${XDG_CONFIG_HOME:-~/.config}/okso/config.env`. Initialize or update that file without running a query via:

```bash
./src/main.sh init --model your-org/your-model:custom.gguf --model-branch main
```

The config file is a simple `key="value"` env-style document. Supported keys:

- `MODEL_SPEC`: HF repo[:file] identifier for the llama.cpp model (default: `bartowski/Qwen_Qwen3-4B-Instruct-2507-GGUF:Qwen_Qwen3-4B-Instruct-2507-Q4_K_M.gguf`).
- `MODEL_BRANCH`: Optional branch or tag for the model download (default: `main`).
- `LLAMA_BIN`: Path to the llama.cpp binary used for scoring (default: `llama-cli`).
- `TESTING_PASSTHROUGH`: Set to `true` in automated tests to bypass llama.cpp entirely; leave unset for normal runs so the assistant always attempts llama-backed planning.
- `APPROVE_ALL`: `true` to skip prompts by default; `false` prompts before each tool.
- `FORCE_CONFIRM`: `true` to always prompt, even when `--yes` is set in the config.
- `VERBOSITY`: `0` (quiet), `1` (info), `2` (debug).

Legacy environment variables such as `DO_MODEL` and `DO_MODEL_BRANCH` are still honored when set for backward compatibility, but the CLI and config file are the primary configuration surfaces.
