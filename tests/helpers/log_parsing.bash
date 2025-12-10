# Utilities for extracting structured JSON logs from mixed stdout/stderr streams.
#
# Usage:
#   load helpers/log_parsing
#   logs_json="$(printf '%s' "$output" | parse_json_logs)"
parse_json_logs() {
	python -c 'import json,sys

data = sys.stdin.read()
decoder = json.JSONDecoder()
logs = []
pos = 0

while pos < len(data):
    try:
        entry, idx = decoder.raw_decode(data, pos)
    except json.JSONDecodeError:
        pos += 1
        continue

    if isinstance(entry, dict):
        logs.append(entry)

    pos = idx

print(json.dumps(logs))
'
}
