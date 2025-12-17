#!/usr/bin/env bats
# Utilities for extracting structured JSON logs from mixed stdout/stderr streams.
#
# Usage:
#   load helpers/log_parsing
#   logs_json="$(printf '%s' "$output" | parse_json_logs)"
parse_json_logs() {
        python -c 'import json, sys

data = sys.stdin.read()
decoder = json.JSONDecoder()
logs = []
search_start = 0

while True:
    brace_index = data.find("{", search_start)
    if brace_index == -1:
        break

    try:
        entry, end_index = decoder.raw_decode(data, brace_index)
    except json.JSONDecodeError:
        search_start = brace_index + 1
        continue

    if isinstance(entry, dict):
        logs.append(entry)

    search_start = end_index

print(json.dumps(logs))
'
}
