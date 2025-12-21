#!/usr/bin/env bats
#
# Tests for the shared HTTP helper used by web tools.
#
# Usage:
#   bats tests/tools/test_web_http.sh

@test "web_http_request surfaces curl timeout failures" {
	run bash <<'SCRIPT'
set -euo pipefail
mock_bin="$(mktemp -d)"
cat >"${mock_bin}/curl" <<'MOCK'
#!/usr/bin/env bash
exit 28
MOCK
chmod +x "${mock_bin}/curl"
export PATH="${mock_bin}:$PATH"
source ./src/tools/web/http.sh
web_http_request "https://example.com" 1024
SCRIPT

	[ "$status" -ne 0 ]
}

@test "web_http_request returns metadata for HTTP errors" {
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
printf 'oops' >"${output_file}"
cat >"${header_file}" <<'HDR'
HTTP/1.1 500 Internal Server Error
Content-Type: text/plain

HDR
printf '500\nhttps://example.com/error\ntext/plain\n4'
MOCK
chmod +x "${mock_bin}/curl"
export PATH="${mock_bin}:$PATH"
source ./src/tools/web/http.sh
web_http_request "https://example.com/error" 1024
SCRIPT

	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.status == 500'
}

@test "web_http_request reports truncated byte length" {
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
                write_out="$2"
                shift 2
                ;;
        *)
                shift
                ;;
        esac
done
printf 'HTTP/1.1 200 OK\nContent-Type: text/plain\n\n' >"${header_file}"
printf 'abcdefghij' >"${output_file}"
if [[ -n "${write_out:-}" ]]; then
        printf '200\nhttps://example.com/large\ntext/plain\n10'
fi
MOCK
chmod +x "${mock_bin}/curl"
export PATH="${mock_bin}:$PATH"
source ./src/tools/web/http.sh
response=$(web_http_request "https://example.com/large" 5)
body_path=$(jq -r '.body_path' <<<"${response}")
wc -c <"${body_path}"
echo "${response}"
SCRIPT

	[ "$status" -eq 0 ]
	truncated_bytes=$(echo "$output" | sed -n '1p')
	response_json=$(echo "$output" | sed -n '2p')
	[ "$truncated_bytes" -eq 5 ]
	echo "$response_json" | jq -e '.truncated == true'
	echo "$response_json" | jq -e '.bytes == 5'
}
