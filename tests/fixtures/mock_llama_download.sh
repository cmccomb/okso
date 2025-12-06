#!/usr/bin/env bash
set -euo pipefail

model_path=""
repo=""
file=""
branch=""
while [[ $# -gt 0 ]]; do
        case "$1" in
        --model)
                model_path="$2"
                shift 2
                ;;
        --hf-repo)
                repo="$2"
                shift 2
                ;;
        --hf-file)
                file="$2"
                shift 2
                ;;
        --hf-branch)
                branch="$2"
                shift 2
                ;;
        --hf-token)
                shift 2
                ;;
        --only-download)
                shift
                ;;
        *)
                shift
                ;;
        esac
done

if [[ -z "${model_path}" ]]; then
        echo "missing --model destination" >&2
        exit 1
fi
mkdir -p "$(dirname "${model_path}")"
printf '%s\n' "stub-model-body" >"${model_path}"

if [[ -n "${LLAMA_CALL_LOG:-}" ]]; then
        printf '%s %s %s %s\n' "${repo}" "${file}" "${branch}" "${model_path}" >>"${LLAMA_CALL_LOG}"
fi
