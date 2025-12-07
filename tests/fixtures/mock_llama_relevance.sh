#!/usr/bin/env bash
# Mock llama.cpp binary for grammar-constrained tool relevance detection.
# Arguments:
#   --hf-repo <repo> (string): repository name (ignored)
#   --hf-file <file> (string): model file (ignored)
#   --grammar <grammar> (string): grammar rules (ignored)
#   -p <prompt> (string): user prompt (ignored)
set -euo pipefail

while [[ $# -gt 0 ]]; do
        case "$1" in
        --hf-repo|--hf-file|--grammar|-p)
                # Skip option and its argument
                shift 2
                ;;
        *)
                shift 1
                ;;
        esac
done

printf '{"terminal":true,"notes_create":false,"reminders_create":false}\n'
