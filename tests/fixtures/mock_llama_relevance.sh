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
user_request=${prompt#*User request: }
if [[ "${user_request}" == "${prompt}" ]]; then
	user_request=${prompt#*USER REQUEST: }
fi
user_request_lower=${user_request,,}

if [[ "${prompt_lower}" == *"concise response"* ]]; then
	request=${prompt#*USER REQUEST: }
	request=${request%%.*}
	printf 'Responding directly to: %s\n' "${request}"
	exit 0
fi

if [[ "${user_request_lower}" == *"joke"* || "${user_request_lower}" == *"chat"* ]]; then
	printf '{}\n'
	exit 0
fi

if [[ "${user_request_lower}" == *"remind"* ]]; then
	printf '{"reminders_create":true}\n'
	exit 0
fi

if [[ "${user_request_lower}" == *"note"* ]]; then
	printf '{"notes_create":true}\n'
	exit 0
fi

if [[ "${user_request_lower}" == *"todo"* ]]; then
	printf '{"terminal":true}\n'
	exit 0
fi

if [[ "${user_request_lower}" == *"file"* || "${user_request_lower}" == *"folder"* ]]; then
	printf '{"terminal":true}\n'
	exit 0
fi

printf '{}\n'
