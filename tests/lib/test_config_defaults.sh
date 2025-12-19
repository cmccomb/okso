#!/usr/bin/env bats

@test "config defaults prefer qwen3 planner/react split" {
        run bash -lc '
                set -e
                source ./src/lib/config.sh
                printf "%s\n%s\n%s\n%s\n%s\n%s\n" \
                        "${DEFAULT_MODEL_SPEC_BASE}" \
                        "${DEFAULT_REACT_MODEL_SPEC_BASE}" \
                        "${DEFAULT_PLANNER_MODEL_SPEC_BASE}" \
                        "${DEFAULT_MODEL_FILE_BASE}" \
                        "${DEFAULT_PLANNER_MODEL_FILE_BASE}" \
                        "${DEFAULT_MODEL_BRANCH_BASE}"
        '
        [ "$status" -eq 0 ]
        [ "${lines[0]}" = "bartowski/Qwen_Qwen3-1.7B-GGUF:Qwen_Qwen3-1.7B-Q4_K_M.gguf" ]
        [ "${lines[1]}" = "bartowski/Qwen_Qwen3-1.7B-GGUF:Qwen_Qwen3-1.7B-Q4_K_M.gguf" ]
        [ "${lines[2]}" = "bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf" ]
        [ "${lines[3]}" = "Qwen_Qwen3-1.7B-Q4_K_M.gguf" ]
        [ "${lines[4]}" = "Qwen_Qwen3-8B-Q4_K_M.gguf" ]
        [ "${lines[5]}" = "main" ]
}
