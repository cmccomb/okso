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

@test "web_fetch rejects disallowed headers" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/tools/web/web_fetch.sh
TOOL_ARGS='{"url":"https://example.com","headers":{"Authorization":"secret"}}' tool_web_fetch
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
source ./src/lib/tools.sh
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
cat tests/fixtures/web_fetch_sample.md
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

@test "web_fetch forwards allowed headers and default user agent" {
	run bash <<'SCRIPT'
set -euo pipefail
args_file="$(mktemp)"
mock_bin="$(mktemp -d)"
cat >"${mock_bin}/curl" <<'MOCK'
#!/usr/bin/env bash
args_file="${CURL_ARGS_FILE}"
output_file=""
header_file=""
user_agent=""
headers=()
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
write_out="$2"
shift 2
;;
--user-agent)
user_agent="$2"
shift 2
;;
--header)
headers+=("$2")
shift 2
;;
*)
shift
;;
esac
done
printf '%s' "${user_agent}" >"${args_file}.ua"
printf '%s\n' "${headers[@]}" >"${args_file}.headers"
if [[ -z "${user_agent}" ]]; then
printf 'missing ua' >&2
exit 1
fi
required=false
for header in "${headers[@]}"; do
if [[ "${header}" == "X-Debug: allow" ]]; then
required=true
fi
done
if [[ "${required}" != true ]]; then
printf 'missing header' >&2
exit 1
fi
printf 'HTTP/1.1 200 OK\nContent-Type: text/plain\n\n' >"${header_file}"
printf 'ok' >"${output_file}"
printf '200\nhttps://example.com/allow\ntext/plain\n2'
MOCK
chmod +x "${mock_bin}/curl"
export PATH="${mock_bin}:$PATH"
export CURL_ARGS_FILE="${args_file}"
source ./src/tools/web/web_fetch.sh
TOOL_ARGS='{"url":"https://example.com/allow","headers":{"X-Debug":"allow"}}'
output=$(tool_web_fetch)
printf 'UA:%s\n' "$(cat "${args_file}.ua")"
while IFS= read -r header_line; do
printf 'Header:%s\n' "${header_line}"
done <"${args_file}.headers"
echo "${output}"
SCRIPT

	[ "$status" -eq 0 ]
	printf '%s\n' "${lines[@]}" | grep -q '^UA:okso-web-fetch/1.0'
	printf '%s\n' "${lines[@]}" | grep -q '^Header:X-Debug: allow'
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
