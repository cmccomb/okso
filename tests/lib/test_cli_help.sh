#!/usr/bin/env bats

@test "CLI help advertises Qwen3 planner/executor defaults" {
	run bash -lc '
                set -e
                source ./src/lib/config.sh
                source ./src/lib/cli/cli.sh
                build_usage_text
        '
	[ "$status" -eq 0 ]
	[[ "$output" == *"planning llama.cpp calls (default: bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf)."* ]]
        [[ "$output" == *"executor llama.cpp calls (default: bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf)."* ]]
        [[ "$output" == *"--model VALUE     HF repo[:file] used for both planner and executor models when specific flags are not set (default: bartowski/Qwen_Qwen3-4B-GGUF:Qwen_Qwen3-4B-Q4_K_M.gguf)."* ]]
}
