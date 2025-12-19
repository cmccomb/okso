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

@test "web_http_request fails on HTTP errors" {
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

	[ "$status" -ne 0 ]
}
