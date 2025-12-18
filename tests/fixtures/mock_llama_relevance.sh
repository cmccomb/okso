#!/usr/bin/env bash
# Mock llama.cpp binary for schema-constrained tool relevance detection.
# Arguments:
#   --hf-repo <repo> (string): repository name (ignored)
#   --hf-file <file> (string): model file (ignored)
#   --grammar <schema> (string): schema rules (ignored)
#   -p <prompt> (string): user prompt (ignored)
set -euo pipefail

prompt=""
user_request=""

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
user_request=$(printf '%s' "${prompt}" | awk 'tolower($0) ~ /^user request:/ {getline; print; exit}')

if [[ -z "${user_request}" ]]; then
	user_request=$(printf '%s' "${prompt}" | awk '/^# User request:/{getline; print; exit}')
fi

user_request_lower=$(to_lowercase "${user_request}")

if [[ "${prompt_lower}" == *"concise response"* ]]; then
	request=${prompt#*USER REQUEST: }
	request=${request%%.*}
	printf 'Responding directly to: %s\n' "${request}"
	exit 0
fi

if [[ "${prompt_lower}" == *"action schema"* ]]; then
	python3 - "$user_request" <<'PY'
import json
import sys

user_request = sys.argv[1]
request_lower = user_request.lower()

tool = "final_answer"
if "file" in request_lower or "folder" in request_lower or "todo" in request_lower:
    tool = "terminal"
elif "note" in request_lower:
    tool = "notes_create"
elif "remind" in request_lower:
    tool = "reminders_create"

print(json.dumps({"type": "tool", "tool": tool, "query": user_request}))
PY
	exit 0
fi

if [[ "${prompt_lower}" == *"json array of strings"* || "${prompt_lower}" == *"available tools"* ]]; then
	if [[ "${user_request_lower}" == *"remind"* ]]; then
		printf '["Use reminders_create to schedule the reminder.","Use final_answer to confirm for the user."]'
		exit 0
	fi

	if [[ "${user_request_lower}" == *"note"* ]]; then
		printf '["Use notes_create to capture the note.","Use final_answer to summarize what was saved."]'
		exit 0
	fi

	if [[ "${user_request_lower}" == *"todo"* ]]; then
		printf '["Use terminal to search for TODO markers.","Use final_answer to summarize findings."]'
		exit 0
	fi

	if [[ "${user_request_lower}" == *"file"* || "${user_request_lower}" == *"folder"* ]]; then
		printf '["Use terminal to inspect the files.","Use final_answer to relay the results."]'
		exit 0
	fi

	printf '["Use final_answer to respond directly."]'
	exit 0
fi

printf '1. Use final_answer to respond directly.\n'
