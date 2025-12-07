#!/usr/bin/env bash
# Mock llama.cpp binary for grammar-constrained tool relevance detection.
# Arguments:
#   --hf-repo <repo> (string): repository name (ignored)
#   --hf-file <file> (string): model file (ignored)
#   --grammar <grammar> (string): grammar rules (ignored)
#   -p <prompt> (string): user prompt (ignored)
set -euo pipefail

prompt=""

while [[ $# -gt 0 ]]; do
        case "$1" in
        --hf-repo | --hf-file | --grammar)
                shift 2
                ;;
        -p)
                prompt="$2"
                shift 2
                ;;
        *)
                shift 1
                ;;
        esac
done

prompt_lower=${prompt,,}

if [[ "${prompt_lower}" == *"joke"* || "${prompt_lower}" == *"chat"* ]]; then
        printf '{}\n'
        exit 0
fi

if [[ "${prompt_lower}" == *"remind"* ]]; then
        printf '{"reminders_create":true}\n'
        exit 0
fi

if [[ "${prompt_lower}" == *"note"* ]]; then
        printf '{"notes_create":true}\n'
        exit 0
fi

if [[ "${prompt_lower}" == *"todo"* ]]; then
        printf '{"terminal":true}\n'
        exit 0
fi

if [[ "${prompt_lower}" == *"file"* || "${prompt_lower}" == *"folder"* ]]; then
        printf '{"terminal":true}\n'
        exit 0
fi

printf '{}\n'
