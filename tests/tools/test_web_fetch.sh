#!/usr/bin/env bats
#
# Tests for the web_fetch tool, including argument validation and registration.
#
# Usage:
#   bats tests/tools/test_web_fetch.sh

setup() {
	export TOOL_ARGS=''
}

@test "web_fetch rejects missing url" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/web/web_fetch.sh
TOOL_ARGS='{}' tool_web_fetch
SCRIPT

	[ "$status" -ne 0 ]
}

@test "web_fetch rejects unexpected args" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/web/web_fetch.sh
TOOL_ARGS='{"url":"https://example.com","snippet":"nope"}' tool_web_fetch
SCRIPT

	[ "$status" -ne 0 ]
}

@test "web_fetch surfaces curl failures" {
	run bash <<'SCRIPT'
set -euo pipefail
mock_bin="$(mktemp -d)"
cat >"${mock_bin}/curl" <<'MOCK'
#!/usr/bin/env bash
exit 28
MOCK
chmod +x "${mock_bin}/curl"
export PATH="${mock_bin}:$PATH"
source ./src/tools/web/web_fetch.sh
TOOL_ARGS='{"url":"https://example.com"}'
tool_web_fetch
SCRIPT

	[ "$status" -ne 0 ]
}

@test "web tools register through the aggregator" {
	run bash <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source ./src/lib/tools/index.sh
init_tool_registry
initialize_tools
names=()
while IFS= read -r line; do
    names+=("$line")
done < <(tool_names)
for name in "${names[@]}"; do
        printf '%s\n' "${name}"
done
SCRIPT

	[ "$status" -eq 0 ]
	[[ " ${lines[*]} " == *" web_search "* ]]
	[[ " ${lines[*]} " == *" web_fetch "* ]]
}

@test "web_fetch converts html bodies to markdown previews" {
	run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
cp tests/fixtures/web_fetch_sample.html "${body_file}"
mock_bin="$(mktemp -d)"
cat >"${mock_bin}/lynx" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "-dump" && "$2" == "-stdin" ]]; then
        sed -E 's/<[^>]+>//g'
        exit 0
fi
exit 1
MOCK
cat >"${mock_bin}/pandoc" <<'MOCK'
#!/usr/bin/env bash
input="${@: -1}"
sed -E 's/<[^>]+>//g' "${input}"
MOCK
chmod +x "${mock_bin}/lynx"
chmod +x "${mock_bin}/pandoc"
export PATH="${mock_bin}:$PATH"
mock_response=$(jq -nc --arg body_path "${body_file}" --arg final_url "https://example.com/final" --arg content_type "text/html" --arg headers "X-Test: 1" '{status:200, final_url:$final_url, content_type:$content_type, headers:$headers, bytes:200, truncated:false, body_path:$body_path}')
source ./src/tools/web/web_fetch.sh
web_http_request() { printf '%s' "${mock_response}"; }
TOOL_ARGS='{"url":"https://example.com"}'
output=$(tool_web_fetch)
echo "${output}"
jq -e '.body_encoding == "text"' <<<"${output}" >/dev/null
jq -e '(.body_markdown | length) > 0' <<<"${output}" >/dev/null
jq -e '(.body_snippet | contains("Example Title"))' <<<"${output}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}

@test "web_fetch anchors previews to web_search snippets when available" {
	run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
cat >"${body_file}" <<'BODY'
Welcome to the test page.
Here is the unique snippet to anchor.
More details follow below.
BODY
mock_response=$(jq -nc --arg body_path "${body_file}" --arg content_type "text/plain" '{status:200, final_url:"https://example.com/test", content_type:$content_type, headers:"", bytes:120, truncated:false, body_path:$body_path}')
source ./src/tools/web/web_fetch.sh
web_http_request() { printf '%s' "${mock_response}"; }
export WEB_FETCH_SEARCH_SNIPPETS='{"https://example.com/test":"unique snippet"}'
TOOL_ARGS='{"url":"https://example.com/test"}'
output=$(tool_web_fetch)
echo "${output}"
jq -e '.anchor_match == true' <<<"${output}" >/dev/null
jq -e '(.body_snippet | contains("unique snippet"))' <<<"${output}" >/dev/null
jq -e '(.body_snippet | contains("Showing content surrounding search match"))' <<<"${output}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}

@test "web_fetch generates a search query when no web_search snippet is present" {
	run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
printf '%s' "Sample body content" >"${body_file}"
mock_response=$(jq -nc --arg body_path "${body_file}" --arg content_type "text/plain" '{status:200, final_url:"https://example.com/path/to/page", content_type:$content_type, headers:"", bytes:20, truncated:false, body_path:$body_path}')
source ./src/tools/web/web_fetch.sh
web_http_request() { printf '%s' "${mock_response}"; }
export LLAMA_AVAILABLE=false
TOOL_ARGS='{"url":"https://example.com/path/to/page"}'
output=$(tool_web_fetch)
echo "${output}"
jq -e '.anchor_query | contains("site:example.com")' <<<"${output}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}

@test "web_fetch truncates lengthy markdown previews" {
	run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
cp tests/fixtures/web_fetch_long.txt "${body_file}"
mock_response=$(jq -nc --arg body_path "${body_file}" --arg content_type "text/plain" '{status:200, final_url:"https://example.com", content_type:$content_type, headers:"", bytes:4000, truncated:false, body_path:$body_path}')
source ./src/tools/web/web_fetch.sh
web_http_request() { printf '%s' "${mock_response}"; }
TOOL_ARGS='{"url":"https://example.com"}'
output=$(tool_web_fetch)
snippet=$(jq -r '.body_snippet' <<<"${output}")
length=${#snippet}
[[ "${length}" -eq 1024 ]]
[[ "${snippet}" == *"…" ]]
SCRIPT

	[ "$status" -eq 0 ]
}

@test "web_fetch falls back when markdown conversion fails" {
	run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
printf '%s' "not json" >"${body_file}"
mock_response=$(jq -nc --arg body_path "${body_file}" --arg content_type "application/json" '{status:200, final_url:"https://example.com", content_type:$content_type, headers:"", bytes:8, truncated:false, body_path:$body_path}')
source ./src/tools/web/web_fetch.sh
web_http_request() { printf '%s' "${mock_response}"; }
TOOL_ARGS='{"url":"https://example.com"}'
output=$(tool_web_fetch)
jq -e '.body_markdown == null' <<<"${output}" >/dev/null
jq -e '.body_snippet == "not json"' <<<"${output}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}
