#!/usr/bin/env bats
#
# Tests for llama.cpp client helpers.
#
# Usage:
#   bats tests/lib/test_llama_client.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert helper outcomes.

@test "llama_infer short-circuits when unavailable" {
	run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                export LLAMA_AVAILABLE=false
                export LLAMA_BIN=/nonexistent
                export MODEL_REPO=repo
                export MODEL_FILE=file
                source ./src/lib/llama_client.sh
                llama_infer "prompt" "" 10
        '
	[ "$status" -eq 1 ]
}

@test "llama_infer forwards grammar and stop arguments" {
	run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                args_dir="$(mktemp -d)"
                args_file="${args_dir}/args.txt"
                mock_binary="${args_dir}/mock_llama.sh"
                cat >"${mock_binary}" <<SCRIPT
#!/usr/bin/env bash
printf "%s\n" "\$@" >"${args_file}"
SCRIPT
                chmod +x "${mock_binary}"
                export LLAMA_AVAILABLE=true
                export LLAMA_BIN="${mock_binary}"
                export MODEL_REPO=demo/repo
                export MODEL_FILE=model.gguf
                source ./src/lib/llama_client.sh
                llama_infer "example prompt" "STOP" 12 "${args_dir}/schema.json"
                mapfile -t args <"${args_file}"
                [[ "${args[*]}" == *"--json-schema-file"* ]]
                [[ "${args[*]}" == *"${args_dir}/schema.json"* ]]
                [[ "${args[*]}" == *"-r"* ]]
                [[ "${args[*]}" == *"STOP"* ]]
        '
	[ "$status" -eq 0 ]
}

@test "llama_infer uses grammar file flag for non-JSON grammars" {
        run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                args_dir="$(mktemp -d)"
                args_file="${args_dir}/args.txt"
                mock_binary="${args_dir}/mock_llama.sh"
                cat >"${mock_binary}" <<SCRIPT
#!/usr/bin/env bash
printf "%s\n" "\$@" >"${args_file}"
SCRIPT
                chmod +x "${mock_binary}"
                export LLAMA_AVAILABLE=true
                export LLAMA_BIN="${mock_binary}"
                export MODEL_REPO=demo/repo
                export MODEL_FILE=model.gguf
                source ./src/lib/llama_client.sh
                llama_infer "prompt" "" 8 "${args_dir}/grammar.gbnf"
                mapfile -t args <"${args_file}"
                [[ "${args[*]}" == *"--grammar-file"* ]]
                [[ "${args[*]}" == *"${args_dir}/grammar.gbnf"* ]]
                [[ " ${args[*]} " != *" -r "* ]]
        '
        [ "$status" -eq 0 ]
}

@test "llama_infer returns llama exit code and logs stderr" {
        run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                args_dir="$(mktemp -d)"
                mock_binary="${args_dir}/mock_llama.sh"
                cat >"${mock_binary}" <<SCRIPT
#!/usr/bin/env bash
echo "fatal llama error" >&2
exit 42
SCRIPT
                chmod +x "${mock_binary}"
                export LLAMA_AVAILABLE=true
                export LLAMA_BIN="${mock_binary}"
                export MODEL_REPO=demo/repo
                export MODEL_FILE=model.gguf
                source ./src/lib/llama_client.sh
                llama_infer "prompt" "STOP" 5
        '
        [ "$status" -eq 42 ]
        detail=$(printf '%s\n' "${output}" | jq -r '.detail')
        [[ "${detail}" == *"mock_llama.sh"* ]]
        [[ "${detail}" == *"--hf-repo demo/repo"* ]]
        [[ "${detail}" == *"--hf-file model.gguf"* ]]
        [[ "${detail}" == *"-p prompt"* ]]
        [[ "${detail}" == *"-r STOP"* ]]
        [[ "${detail}" == *"fatal llama error"* ]]
}

@test "llama_infer interrupts hung llama when timeout configured" {
        run bash -lc '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                args_dir="$(mktemp -d)"
                mock_binary="${args_dir}/mock_llama.sh"
                cat >"${mock_binary}" <<SCRIPT
#!/usr/bin/env bash
sleep 5
printf "hung output" >&2
SCRIPT
                chmod +x "${mock_binary}"
                export LLAMA_AVAILABLE=true
                export LLAMA_BIN="${mock_binary}"
                export MODEL_REPO=demo/repo
                export MODEL_FILE=model.gguf
                export LLAMA_TIMEOUT_SECONDS=1
                source ./src/lib/llama_client.sh
                llama_infer "prompt" "" 4
        '
        [ "$status" -eq 124 ]
        message=$(printf '%s\n' "${output}" | jq -r '.message')
        [[ "${message}" == "llama inference timed out" ]]
        detail=$(printf '%s\n' "${output}" | jq -r '.detail')
        [[ "${detail}" == *"timeout_seconds=1"* ]]
        [[ "${detail}" == *"elapsed_ms="* ]]
}
