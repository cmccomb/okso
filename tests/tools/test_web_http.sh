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

@test "web_http_request sets explicit user agent" {
	run bash <<'SCRIPT'
set -euo pipefail
mock_bin="$(mktemp -d)"
args_file="$(mktemp)"
cat >"${mock_bin}/curl" <<'MOCK'
#!/usr/bin/env bash
args_file="${CURL_ARGS_FILE}"
output_file=""
header_file=""
user_agent=""
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
shift 2
;;
*)
shift
;;
esac
done
printf '%s\n' "$@" >"${args_file}"
printf '%s' "${user_agent}" >"${args_file}.ua"
if [[ -z "${user_agent}" ]]; then
printf 'missing ua' >&2
exit 1
fi
printf 'HTTP/1.1 200 OK\nContent-Type: text/plain\n\n' >"${header_file}"
printf 'ok' >"${output_file}"
printf '200\nhttps://example.com/ua\ntext/plain\n2'
MOCK
chmod +x "${mock_bin}/curl"
export PATH="${mock_bin}:$PATH"
export CURL_ARGS_FILE="${args_file}"
source ./src/tools/web/http.sh
response=$(web_http_request "https://example.com/ua" 1024 --header "X-Test: allowed")
printf 'UA:%s\n' "$(cat "${args_file}.ua")"
echo "${response}"
SCRIPT

	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "UA:okso-web-fetch/1.0" ]]
}
