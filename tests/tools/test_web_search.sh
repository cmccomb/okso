#!/usr/bin/env bats
#
# Tests for web search result parsing and sanitization.
#
# Usage:
#   bats tests/tools/test_web_search.sh

setup() {
	export TOOL_ARGS=''
}

@test "web_search rejects missing query" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/web/web_search.sh
TOOL_ARGS='{}' tool_web_search
SCRIPT

	[ "$status" -ne 0 ]
}

@test "web_search accepts input alias for query" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/web/web_search.sh
parsed=$(TOOL_ARGS='{"input":"aliased query"}' web_search_parse_args)
jq -e '.query == "aliased query" and .num == 5' <<<"${parsed}"
SCRIPT

	[ "$status" -eq 0 ]
}

@test "web_search surfaces API errors" {
	run bash <<'SCRIPT'
set -euo pipefail
mock_bin="$(mktemp -d)"
cat >"${mock_bin}/curl" <<'MOCK'
#!/usr/bin/env bash
output_file=""
header_file=""
while [[ $# -gt 0 ]]; do
        case "$1" in
        --output)
                output_file="$2"
                shift 2
                ;;
        --dump-header)
                header_file="$2"
                shift 2
                ;;
        --write-out)
                shift 2
                ;;
        *)
                shift
                ;;
        esac
done
cat >"${output_file}" <<'JSON'
{"error":{"message":"quota exceeded"}}
JSON
cat >"${header_file}" <<'HDR'
HTTP/1.1 200 OK
Content-Type: application/json

HDR
printf '200\nhttps://www.googleapis.com/customsearch/v1\napplication/json\n40'
MOCK
chmod +x "${mock_bin}/curl"
export PATH="${mock_bin}:$PATH"
export GOOGLE_SEARCH_API_KEY="key"
export GOOGLE_SEARCH_CX="cx"
source ./src/tools/web/web_search.sh
TOOL_ARGS='{"query":"demo"}'
tool_web_search
SCRIPT

	[ "$status" -ne 0 ]
}

@test "web_search returns results with url field" {
	run bash <<'SCRIPT'
set -euo pipefail
mock_bin="$(mktemp -d)"
cat >"${mock_bin}/curl" <<'MOCK'
#!/usr/bin/env bash
output_file=""
header_file=""
while [[ $# -gt 0 ]]; do
        case "$1" in
        --output)
                output_file="$2"
                shift 2
                ;;
        --dump-header)
                header_file="$2"
                shift 2
                ;;
        --write-out)
                shift 2
                ;;
        *)
                shift
                ;;
        esac
done
cat >"${output_file}" <<'JSON'
{
  "queries": { "request": [ { "searchTerms": "demo" } ] },
  "searchInformation": { "totalResults": "1" },
  "items": [
    {
      "title": "Example",
      "link": "https://example.com",
      "snippet": "An example site",
      "displayLink": "example.com"
    }
  ]
}
JSON
cat >"${header_file}" <<'HDR'
HTTP/1.1 200 OK
Content-Type: application/json

HDR
printf '200\nhttps://www.googleapis.com/customsearch/v1\napplication/json\n100'
MOCK
chmod +x "${mock_bin}/curl"
export PATH="${mock_bin}:$PATH"
export GOOGLE_SEARCH_API_KEY="key"
export GOOGLE_SEARCH_CX="cx"
source ./src/tools/web/web_search.sh
TOOL_ARGS='{"query":"demo"}'
tool_web_search
SCRIPT

	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.items[0].url == "https://example.com"'
}

@test "web_search uses default num when not provided" {
	run bash <<'SCRIPT'
set -euo pipefail
mock_bin="$(mktemp -d)"
capture_file="$(mktemp)"
cat >"${mock_bin}/curl" <<'MOCK'
#!/usr/bin/env bash
output_file=""
header_file=""
num_value=""
while [[ $# -gt 0 ]]; do
        case "$1" in
        --output)
                output_file="$2"
                shift 2
                ;;
        --dump-header)
                header_file="$2"
                shift 2
                ;;
        --write-out)
                shift 2
                ;;
        --data)
                data_value="$2"
                if [[ "${data_value}" == num=* ]]; then
                        num_value="${data_value#num=}"
                fi
                shift 2
                ;;
        --data-urlencode|--header|--get|--silent|--show-error|--location)
                shift
                ;;
        --max-time|--connect-timeout|--retry|--retry-delay)
                shift 2
                ;;
        *)
                shift
                ;;
        esac
done
if [[ -n "${CAPTURE_FILE:-}" ]]; then
        printf '%s' "${num_value}" >"${CAPTURE_FILE}"
fi
cat >"${output_file}" <<'JSON'
{
  "queries": { "request": [ { "searchTerms": "demo" } ] },
  "searchInformation": { "totalResults": "1" },
  "items": []
}
JSON
cat >"${header_file}" <<'HDR'
HTTP/1.1 200 OK
Content-Type: application/json

HDR
printf '200\nhttps://www.googleapis.com/customsearch/v1\napplication/json\n100'
MOCK
chmod +x "${mock_bin}/curl"
export PATH="${mock_bin}:$PATH"
export GOOGLE_SEARCH_API_KEY="key"
export GOOGLE_SEARCH_CX="cx"
export CAPTURE_FILE="${capture_file}"
source ./src/tools/web/web_search.sh
TOOL_ARGS='{"query":"demo"}'
tool_web_search
printf 'CAPTURE:%s' "$(cat "${capture_file}")"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "$output" =~ CAPTURE:5 ]]
}

@test "web_search forwards provided num to API" {
	run bash <<'SCRIPT'
set -euo pipefail
mock_bin="$(mktemp -d)"
capture_file="$(mktemp)"
cat >"${mock_bin}/curl" <<'MOCK'
#!/usr/bin/env bash
output_file=""
header_file=""
num_value=""
while [[ $# -gt 0 ]]; do
        case "$1" in
        --output)
                output_file="$2"
                shift 2
                ;;
        --dump-header)
                header_file="$2"
                shift 2
                ;;
        --write-out)
                shift 2
                ;;
        --data)
                data_value="$2"
                if [[ "${data_value}" == num=* ]]; then
                        num_value="${data_value#num=}"
                fi
                shift 2
                ;;
        --data-urlencode|--header|--get|--silent|--show-error|--location)
                shift
                ;;
        --max-time|--connect-timeout|--retry|--retry-delay)
                shift 2
                ;;
        *)
                shift
                ;;
        esac
done
if [[ -n "${CAPTURE_FILE:-}" ]]; then
        printf '%s' "${num_value}" >>"${CAPTURE_FILE}"
        printf '\n' >>"${CAPTURE_FILE}"
fi
cat >"${output_file}" <<'JSON'
{
  "queries": { "request": [ { "searchTerms": "demo" } ] },
  "searchInformation": { "totalResults": "1" },
  "items": []
}
JSON
cat >"${header_file}" <<'HDR'
HTTP/1.1 200 OK
Content-Type: application/json

HDR
printf '200\nhttps://www.googleapis.com/customsearch/v1\napplication/json\n100'
MOCK
chmod +x "${mock_bin}/curl"
export PATH="${mock_bin}:$PATH"
export GOOGLE_SEARCH_API_KEY="key"
export GOOGLE_SEARCH_CX="cx"
export CAPTURE_FILE="${capture_file}"
source ./src/tools/web/web_search.sh
TOOL_ARGS='{"query":"demo","num":3}'
tool_web_search
TOOL_ARGS='{"query":"demo","num":10}'
tool_web_search
printf 'CAPTURE:%s' "$(tr '\n' ',' <"${capture_file}")"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "$output" =~ CAPTURE:3,10,? ]]
}
