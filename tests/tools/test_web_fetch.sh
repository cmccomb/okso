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
SCRIPT

	[ "$status" -eq 0 ]
}

@test "web_fetch warns and skips anchoring when snippet map JSON is invalid" {
	run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
cat >"${body_file}" <<'BODY'
Welcome to the test page.
Here is the unique snippet to anchor.
More details follow below.
BODY
mock_response=$(jq -nc --arg body_path "${body_file}" --arg content_type "text/plain" '{status:200, final_url:"https://example.com/test", content_type:$content_type, headers:"", bytes:120, truncated:false, body_path:$body_path}')
source ./src/lib/executor/loop.sh
source ./src/tools/web/web_fetch.sh
web_http_request() { printf '%s' "${mock_response}"; }
malformed_snippets='{"https://example.com/test":"unique snippet"}}'
log_file="$(mktemp)"
sanitized_snippets="$(validate_web_fetch_snippet_map "${malformed_snippets}" 2>"${log_file}")"
export WEB_FETCH_SEARCH_SNIPPETS="${sanitized_snippets}"
TOOL_ARGS='{"url":"https://example.com/test"}'
output=$(tool_web_fetch)
jq -e '.anchor_match == false' <<<"${output}" >/dev/null
jq -e '.anchor_query == ""' <<<"${output}" >/dev/null
grep -q '"level":"WARN"' "${log_file}"
grep -q 'Invalid WEB_FETCH_SEARCH_SNIPPETS' "${log_file}"
SCRIPT

	[ "$status" -eq 0 ]
}

@test "web_fetch skips anchoring when no web_search snippet is present" {
	run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
printf '%s' "Sample body content" >"${body_file}"
mock_response=$(jq -nc --arg body_path "${body_file}" --arg content_type "text/plain" '{status:200, final_url:"https://example.com/path/to/page", content_type:$content_type, headers:"", bytes:20, truncated:false, body_path:$body_path}')
source ./src/tools/web/web_fetch.sh
web_http_request() { printf '%s' "${mock_response}"; }
TOOL_ARGS='{"url":"https://example.com/path/to/page"}'
output=$(tool_web_fetch)
echo "${output}"
jq -e '.anchor_query == ""' <<<"${output}" >/dev/null
jq -e '.anchor_match == false' <<<"${output}" >/dev/null
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
