#!/usr/bin/env bats

@test "CLI help advertises Qwen3 planner/react defaults" {
        run bash -lc '
                set -e
                source ./src/lib/config.sh
                source ./src/lib/cli/cli.sh
                build_usage_text
        '
        [ "$status" -eq 0 ]
        [[ "$output" == *"planning llama.cpp calls (default: bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf)."* ]]
        [[ "$output" == *"ReAct llama.cpp calls (default: bartowski/Qwen_Qwen3-1.7B-GGUF:Qwen_Qwen3-1.7B-Q4_K_M.gguf)."* ]]
        [[ "$output" == *"--model VALUE     HF repo[:file] used for both planner and ReAct models when specific flags are not set (default: bartowski/Qwen_Qwen3-1.7B-GGUF:Qwen_Qwen3-1.7B-Q4_K_M.gguf)."* ]]
}
