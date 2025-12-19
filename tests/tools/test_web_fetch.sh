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

@test "web_fetch emits metadata with body snippet" {
	run bash <<'SCRIPT'
set -euo pipefail
mock_bin="$(mktemp -d)"
cat >"${mock_bin}/curl" <<'MOCK'
#!/usr/bin/env bash
output_file=""
header_file=""
write_out=""
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
        *)
                shift
                ;;
        esac
done
printf 'ABCDEFGHIJ' >"${output_file}"
cat >"${header_file}" <<'HDR'
HTTP/1.1 200 OK
Content-Type: text/plain; charset=utf-8

HDR
printf '200\nhttps://example.com/resource\ntext/plain; charset=utf-8\n10'
MOCK
chmod +x "${mock_bin}/curl"
export PATH="${mock_bin}:$PATH"
source ./src/tools/web/web_fetch.sh
TOOL_ARGS='{"url":"https://example.com/resource","max_bytes":20}'
output="$(tool_web_fetch 2>/dev/null)"
rm -rf "${mock_bin}"
printf '%s' "${output}"
SCRIPT

	[ "$status" -eq 0 ]
	jq -er '.status == 200' <<<"${output}" >/dev/null
	jq -er '.final_url == "https://example.com/resource"' <<<"${output}" >/dev/null
	jq -er '.content_type | contains("text/plain")' <<<"${output}" >/dev/null
	jq -er '.headers | contains("Content-Type: text/plain")' <<<"${output}" >/dev/null
	jq -er '.bytes == 10' <<<"${output}" >/dev/null
	jq -er '.truncated == false' <<<"${output}" >/dev/null
	jq -er '.body_encoding == "text"' <<<"${output}" >/dev/null
	jq -er '.body_snippet == "ABCDEFGHIJ"' <<<"${output}" >/dev/null
}

@test "web_fetch trims oversized bodies" {
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
printf 'ABCDEFGHIJ' >"${output_file}"
cat >"${header_file}" <<'HDR'
HTTP/1.1 200 OK
Content-Type: text/plain

HDR
printf '200\nhttps://example.com/truncated\ntext/plain\n10'
MOCK
chmod +x "${mock_bin}/curl"
export PATH="${mock_bin}:$PATH"
source ./src/tools/web/web_fetch.sh
TOOL_ARGS='{"url":"https://example.com/truncated","max_bytes":5}'
output="$(tool_web_fetch 2>/dev/null)"
rm -rf "${mock_bin}"
printf '%s' "${output}"
SCRIPT

	[ "$status" -eq 0 ]
	jq -er '.truncated == true' <<<"${output}" >/dev/null
	jq -er '.body_snippet == "ABCDE"' <<<"${output}" >/dev/null
	jq -er '.bytes == 10' <<<"${output}" >/dev/null
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
