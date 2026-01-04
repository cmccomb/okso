#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2154,SC2016,SC2030,SC2031
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
                export EXECUTOR_MODEL_REPO=repo
                export EXECUTOR_MODEL_FILE=file
                source ./src/lib/llm/llama_client.sh
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
                printf "{\"title\":\"forwarded-schema\"}" >"${json_schema}"
                cat >"${mock_binary}" <<SCRIPT
#!/usr/bin/env bash
printf "%s\n" "\$@" >"${args_file}"
SCRIPT
                chmod +x "${mock_binary}"
                export LLAMA_AVAILABLE=true
                export LLAMA_BIN="${mock_binary}"
                export EXECUTOR_MODEL_REPO=demo/repo
                export EXECUTOR_MODEL_FILE=model.gguf
                source ./src/lib/llm/llama_client.sh
                llama_infer "example prompt" "STOP" 12 "$(cat "${json_schema}")"
                args=()
                while IFS= read -r line; do
                        args+=("$line")
                done <"${args_file}"
                [[ "${args[*]}" == *"--json-schema"* ]]
                [[ "${args[*]}" == *"forwarded-schema"* ]]
                [[ "${args[*]}" == *"-r"* ]]
                [[ "${args[*]}" == *"STOP"* ]]
        '
	[ "$status" -eq 0 ]
}

@test "llama_infer forwards optional extra arguments" {
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
                export EXECUTOR_MODEL_REPO=demo/repo
                export EXECUTOR_MODEL_FILE=model.gguf
                export LLAMA_EXTRA_ARGS="--dry-multiplier 0.35 --dry-base 1.75 --dry-allowed-length 2"
                source ./src/lib/llm/llama_client.sh
                llama_infer "example prompt" "" 12
                args=()
                while IFS= read -r line; do
                        args+=("$line")
                done <"${args_file}"
                [[ " ${args[*]} " == *" --dry-multiplier 0.35 "* ]]
                [[ " ${args[*]} " == *" --dry-base 1.75 "* ]]
                [[ " ${args[*]} " == *" --dry-allowed-length 2 "* ]]
        '
	[ "$status" -eq 0 ]
}

@test "llama_infer accepts multiline schema strings" {
	run env BASH_ENV= ENV= bash --noprofile --norc -c '
                set -uo pipefail
                cd "$(git rev-parse --show-toplevel)" || exit 1
                script_dir="$(mktemp -d)"
                runner="${script_dir}/runner.sh"
                cat >"${runner}" <<"SCRIPT"
#!/usr/bin/env bash
set -euo pipefail
args_dir="$(mktemp -d)"
args_file="${args_dir}/args.txt"
mock_binary="${args_dir}/mock_llama.sh"
cat >"${mock_binary}" <<INNER
#!/usr/bin/env bash
printf "%s\n" "\$@" >"${args_file}"
INNER
chmod +x "${mock_binary}"
export LLAMA_AVAILABLE=true
export LLAMA_BIN="${mock_binary}"
export REACT_MODEL_REPO=demo/repo
export REACT_MODEL_FILE=model.gguf
source ./src/lib/llm/llama_client.sh
                schema_doc="{\"type\":\"object\",\"properties\":{\"key\":{\"type\":\"string\"}}}"
                llama_infer "prompt" "" 8 "${schema_doc}"
                schema_args=$(tr -d '[[:space:]]' <"${args_file}")
                grep -Fq -- "\"properties\":{\"key\":{\"type\":\"string\"}}" <<<"${schema_args}"
SCRIPT
                chmod +x "${runner}"
                "${runner}"
        '
	[ "$status" -eq 0 ]
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
                source ./src/lib/llm/llama_client.sh
                llama_infer "prompt" "" 4
        '
	[ "$status" -eq 124 ]
	message=$(printf '%s\n' "${output}" | jq -r 'select(.message=="llama inference timed out") | .message')
	[[ "${message}" == "llama inference timed out" ]]
	detail=$(printf '%s\n' "${output}" | jq -r 'select(.message=="llama inference timed out") | .detail')
	[[ "${detail}" == *"timeout_seconds=1"* ]]
	[[ "${detail}" == *"elapsed_ms="* ]]
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
                source ./src/lib/llm/llama_client.sh
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
                source ./src/lib/llm/llama_client.sh
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
                source ./src/lib/llm/llama_client.sh
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
	message=$(printf '%s\n' "${output}" | jq -r 'select(.message=="llama context capped") | .message')
	detail=$(printf '%s\n' "${output}" | jq -r 'select(.message=="llama context capped") | .detail')
	[[ "${message}" == "llama context capped" ]]
	[[ "${detail}" == *"required_context=161"* ]]
	[[ "${detail}" == *"capped_context=90"* ]]
}
