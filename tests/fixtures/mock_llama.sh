#!/usr/bin/env bash
# Mock llama.cpp binary for deterministic test scoring.
# Arguments:
#   -m <path> (string): model path (ignored)
#   -p <prompt> (string): prompt containing tool name and description
set -euo pipefail
PROMPT=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	-p)
		PROMPT="$2"
		shift 2
		;;
	*)
		shift 1
		;;
	esac
done
if printf '%s' "${PROMPT}" | grep -q "Tool: notes"; then
	printf '5\n'
else
	printf '1\n'
fi
