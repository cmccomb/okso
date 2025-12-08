#!/usr/bin/env bash
# Mock llama.cpp binary for grammar-constrained tool relevance detection.
# Arguments:
#   --hf-repo <repo> (string): repository name (ignored)
#   --hf-file <file> (string): model file (ignored)
#   --grammar <grammar> (string): grammar rules (ignored)
#   -p <prompt> (string): user prompt (ignored)
set -euo pipefail

prompt=""

to_lowercase() {
	# Arguments:
	#   $1 - input string
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

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

prompt_lower=$(to_lowercase "${prompt}")
user_request=${prompt#*User request: }
if [[ "${user_request}" == "${prompt}" ]]; then
	user_request=${prompt#*USER REQUEST: }
fi
user_request_lower=$(to_lowercase "${user_request}")

if [[ "${prompt_lower}" == *"concise response"* ]]; then
	request=${prompt#*USER REQUEST: }
	request=${request%%.*}
	printf 'Responding directly to: %s\n' "${request}"
	exit 0
fi

if [[ "${prompt_lower}" == *"numbered list of high-level actions"* || "${prompt_lower}" == *"available tools"* ]]; then
	if [[ "${user_request_lower}" == *"remind"* ]]; then
		printf '1. Use reminders_create to schedule the reminder.\n2. Use final_answer to confirm for the user.\n'
		exit 0
	fi

	if [[ "${user_request_lower}" == *"note"* ]]; then
		printf '1. Use notes_create to capture the note.\n2. Use final_answer to summarize what was saved.\n'
		exit 0
	fi

	if [[ "${user_request_lower}" == *"todo"* ]]; then
		printf '1. Use terminal to search for TODO markers.\n2. Use final_answer to summarize findings.\n'
		exit 0
	fi

	if [[ "${user_request_lower}" == *"file"* || "${user_request_lower}" == *"folder"* ]]; then
		printf '1. Use terminal to inspect the files.\n2. Use final_answer to relay the results.\n'
		exit 0
	fi

	printf '1. Use final_answer to respond directly.\n'
	exit 0
fi

printf '1. Use final_answer to respond directly.\n'
