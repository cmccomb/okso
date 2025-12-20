#!/usr/bin/env bats
# shellcheck disable=SC2154,SC2016
#
# Tests for llama.cpp client helpers.
#
# Usage:
#   bats tests/lib/test_llama_client.sh
#
# Dependencies:
#   - bats
#   - bash 3.2+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert helper outcomes.

setup() {
	export HOME="${BATS_TMPDIR}/llama_client_home"
	mkdir -p "${HOME}/.cargo"
	: >"${HOME}/.cargo/env"
}

@test "llama_infer short-circuits when unavailable" {
	run env BASH_ENV= ENV= bash --noprofile --norc -c '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                export LLAMA_AVAILABLE=false
                export LLAMA_BIN=/nonexistent
                export REACT_MODEL_REPO=repo
                export REACT_MODEL_FILE=file
                source ./src/lib/planning/llama_client.sh
                llama_infer "prompt" "" 10
        '
	[ "$status" -eq 1 ]
}

@test "llama_infer forwards JSON schema content and stop arguments" {
	run env BASH_ENV= ENV= bash --noprofile --norc -c '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                args_dir="$(mktemp -d)"
                args_file="${args_dir}/args.txt"
                mock_binary="${args_dir}/mock_llama.sh"
                json_schema="${args_dir}/schema.json"
                printf "{\"title\":\"sentinel-schema\"}" >"${json_schema}"
                cat >"${mock_binary}" <<SCRIPT
#!/usr/bin/env bash
printf "%s\n" "\$@" >"${args_file}"
SCRIPT
                chmod +x "${mock_binary}"
                export LLAMA_AVAILABLE=true
                export LLAMA_BIN="${mock_binary}"
                export REACT_MODEL_REPO=demo/repo
                export REACT_MODEL_FILE=model.gguf
                source ./src/lib/planning/llama_client.sh
                llama_infer "example prompt" "STOP" 12 "${json_schema}"
                args=()
                while IFS= read -r line; do
                        args+=("$line")
                done <"${args_file}"
                [[ "${args[*]}" == *"--json-schema"* ]]
                [[ "${args[*]}" == *"sentinel-schema"* ]]
                [[ "${args[*]}" == *"-r"* ]]
                [[ "${args[*]}" == *"STOP"* ]]
        '
	[ "$status" -eq 0 ]
}

@test "llama_infer uses grammar file flag for non-JSON schemas" {
	run env BASH_ENV= ENV= bash --noprofile --norc -c '
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
                export REACT_MODEL_REPO=demo/repo
                export REACT_MODEL_FILE=model.gguf
                source ./src/lib/planning/llama_client.sh
                llama_infer "prompt" "" 8 "${args_dir}/schema.gbnf"
                args=()
                while IFS= read -r line; do
                        args+=("$line")
                done <"${args_file}"
                [[ "${args[*]}" == *"--grammar-file"* ]]
                [[ "${args[*]}" == *"${args_dir}/schema.gbnf"* ]]
                [[ " ${args[*]} " != *" -r "* ]]
        '
	[ "$status" -eq 0 ]
}

@test "llama_infer returns llama exit code and logs stderr" {
	run env BASH_ENV= ENV= bash --noprofile --norc -c '
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
                export REACT_MODEL_REPO=demo/repo
                export REACT_MODEL_FILE=model.gguf
                source ./src/lib/planning/llama_client.sh
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
	run env BASH_ENV= ENV= bash --noprofile --norc -c '
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
                export REACT_MODEL_REPO=demo/repo
                export REACT_MODEL_FILE=model.gguf
                export LLAMA_TIMEOUT_SECONDS=1
                source ./src/lib/planning/llama_client.sh
                llama_infer "prompt" "" 4
        '
	[ "$status" -eq 124 ]
	message=$(printf '%s\n' "${output}" | jq -r '.message')
	[[ "${message}" == "llama inference timed out" ]]
	detail=$(printf '%s\n' "${output}" | jq -r '.detail')
	[[ "${detail}" == *"timeout_seconds=1"* ]]
	[[ "${detail}" == *"elapsed_ms="* ]]
}

@test "llama_infer fails when JSON schema cannot be read" {
	local missing_schema
	missing_schema="${BATS_TMPDIR}/missing-schema.json"

	run env BASH_ENV= ENV= MISSING_SCHEMA="${missing_schema}" bash --noprofile --norc -c '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                args_dir="$(mktemp -d)"
                missing_schema="${MISSING_SCHEMA}"
                mock_binary="${args_dir}/mock_llama.sh"
                cat >"${mock_binary}" <<SCRIPT
#!/usr/bin/env bash
printf "%s\n" "should not run" >&2
exit 99
SCRIPT
                chmod +x "${mock_binary}"
                export LLAMA_AVAILABLE=true
                export LLAMA_BIN="${mock_binary}"
                export REACT_MODEL_REPO=demo/repo
                export REACT_MODEL_FILE=model.gguf
                source ./src/lib/planning/llama_client.sh
                llama_infer "prompt" "" 8 "${missing_schema}"
        '
	[ "$status" -eq 1 ]
	message=$(printf '%s\n' "${output}" | jq -r '.message')
	[[ "${message}" == "failed to read JSON schema" ]]
	detail=$(printf '%s\n' "${output}" | jq -r '.detail')
	[[ "${detail}" == *"${missing_schema}"* ]]
}

@test "llama_infer keeps default context when estimate fits" {
	run env BASH_ENV= ENV= bash --noprofile --norc -c '
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
                export REACT_MODEL_REPO=demo/repo
                export REACT_MODEL_FILE=model.gguf
                export LLAMA_DEFAULT_CONTEXT_SIZE=128
                export LLAMA_CONTEXT_CAP=256
                export LLAMA_CONTEXT_MARGIN_PERCENT=15
                source ./src/lib/planning/llama_client.sh
                llama_infer "small prompt" "" 16
                args=()
                while IFS= read -r line; do
                        args+=("$line")
                done <"${args_file}"
                [[ " ${args[*]} " != *" -c "* ]]
        '
	[ "$status" -eq 0 ]
}

@test "llama_infer expands context for large prompts" {
	run env BASH_ENV= ENV= bash --noprofile --norc -c '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                args_dir="$(mktemp -d)"
                args_file="${args_dir}/args.txt"
                mock_binary="${args_dir}/mock_llama.sh"
                cat >"${mock_binary}" <<SCRIPT
#!/usr/bin/env bash
printf "%s\n" "\$@" >"${args_file}"
SCRIPT
                chmod +x "${mock_binary}"
                long_prompt=$(printf "p%.0s" {1..200})
                export LLAMA_AVAILABLE=true
                export LLAMA_BIN="${mock_binary}"
                export REACT_MODEL_REPO=demo/repo
                export REACT_MODEL_FILE=model.gguf
                export LLAMA_DEFAULT_CONTEXT_SIZE=64
                export LLAMA_CONTEXT_CAP=512
                export LLAMA_CONTEXT_MARGIN_PERCENT=15
                source ./src/lib/planning/llama_client.sh
                llama_infer "${long_prompt}" "" 20
                args=()
                while IFS= read -r line; do
                        args+=("$line")
                done <"${args_file}"
                context_value=""
                for i in "${!args[@]}"; do
                        if [[ "${args[$i]}" == "-c" ]]; then
                                context_value="${args[$((i + 1))]}"
                        fi
                done
                [[ "${context_value}" == "81" ]]
        '
	[ "$status" -eq 0 ]
}

@test "llama_infer caps requested context" {
	run env BASH_ENV= ENV= bash --noprofile --norc -c '
                cd "$(git rev-parse --show-toplevel)" || exit 1
                args_dir="$(mktemp -d)"
                args_file="${args_dir}/args.txt"
                mock_binary="${args_dir}/mock_llama.sh"
                cat >"${mock_binary}" <<SCRIPT
#!/usr/bin/env bash
printf "%s\n" "\$@" >"${args_file}"
SCRIPT
                chmod +x "${mock_binary}"
                long_prompt=$(printf "c%.0s" {1..400})
                export LLAMA_AVAILABLE=true
                export LLAMA_BIN="${mock_binary}"
                export REACT_MODEL_REPO=demo/repo
                export REACT_MODEL_FILE=model.gguf
                export LLAMA_DEFAULT_CONTEXT_SIZE=64
                export LLAMA_CONTEXT_CAP=90
                export LLAMA_CONTEXT_MARGIN_PERCENT=15
                source ./src/lib/planning/llama_client.sh
                llama_infer "${long_prompt}" "" 40
                args=()
                while IFS= read -r line; do
                        args+=("$line")
                done <"${args_file}"
                context_value=""
                for i in "${!args[@]}"; do
                        if [[ "${args[$i]}" == "-c" ]]; then
                                context_value="${args[$((i + 1))]}"
                        fi
                done
                [[ "${context_value}" == "90" ]]
        '
	[ "$status" -eq 0 ]
	message=$(printf '%s\n' "${output}" | jq -r '.message')
	detail=$(printf '%s\n' "${output}" | jq -r '.detail')
	[[ "${message}" == "llama context capped" ]]
	[[ "${detail}" == *"required_context=161"* ]]
	[[ "${detail}" == *"capped_context=90"* ]]
}
