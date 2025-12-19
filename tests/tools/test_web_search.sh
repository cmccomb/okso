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

@test "web_search fails without configuration" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/web/web_search.sh
TOOL_ARGS='{"query":"test"}'
tool_web_search
SCRIPT

	[ "$status" -ne 0 ]
}

@test "web_search parses responses into structured output" {
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
  "queries": {"request": [{"searchTerms": "demo"}]},
  "searchInformation": {"totalResults": "2"},
  "items": [
    {"title": "First", "link": "https://example.com/1", "snippet": "One", "displayLink": "example.com"},
    {"title": "Second", "link": "https://example.com/2"}
  ]
}
JSON
cat >"${header_file}" <<'HDR'
HTTP/1.1 200 OK
Content-Type: application/json

HDR
printf '200\nhttps://www.googleapis.com/customsearch/v1\napplication/json\n200'
MOCK
chmod +x "${mock_bin}/curl"
export PATH="${mock_bin}:$PATH"
export GOOGLE_SEARCH_API_KEY="key"
export GOOGLE_SEARCH_CX="cx"
source ./src/tools/web/web_search.sh
TOOL_ARGS='{"query":"demo","num":2}'
output="$(tool_web_search 2>/dev/null)"
rm -rf "${mock_bin}"
printf '%s' "${output}"
SCRIPT

	[ "$status" -eq 0 ]
	expected='{"query":"demo","total_results":2,"items":[{"title":"First","link":"https://example.com/1","snippet":"One","displayLink":"example.com"},{"title":"Second","link":"https://example.com/2","snippet":"","displayLink":""}]}'
	[ "${output}" = "${expected}" ]
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
