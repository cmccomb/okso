#!/usr/bin/env bash
# Mock llama.cpp binary for deterministic test scoring.
# Arguments:
#   -m <path> (string): model path (ignored)
#   -p <prompt> (string): prompt containing the tool catalog or plan request
set -euo pipefail
PROMPT=""
LOG_PATH="${MOCK_LLAMA_LOG:-}"
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

if [[ -n "${LOG_PATH}" ]]; then
	printf '%s\n' "${PROMPT}" >>"${LOG_PATH}"
fi

if printf '%s' "${PROMPT}" | grep -q "Plan a concise sequence"; then
	printf 'Use selected tools in ranked order.\n'
	exit 0
fi

printf 'tool=notes_create score=5 reason=stores reminders locally\n'
printf 'tool=terminal score=2 reason=basic filesystem context\n'
