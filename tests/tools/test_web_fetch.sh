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
exit 22
MOCK
chmod +x "${mock_bin}/curl"
export PATH="${mock_bin}:$PATH"
source ./src/tools/web/web_fetch.sh
TOOL_ARGS='{"url":"https://example.com"}'
tool_web_fetch
SCRIPT

        [ "$status" -ne 0 ]
}

@test "web_fetch trims oversized bodies" {
        run bash <<'SCRIPT'
set -euo pipefail
mock_bin="$(mktemp -d)"
cat >"${mock_bin}/curl" <<'MOCK'
#!/usr/bin/env bash
output_file=""
write_out=""
while [[ $# -gt 0 ]]; do
        case "$1" in
        --output)
                output_file="$2"
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
printf '200'
MOCK
chmod +x "${mock_bin}/curl"
export PATH="${mock_bin}:$PATH"
source ./src/tools/web/web_fetch.sh
TOOL_ARGS='{"url":"https://example.com","max_bytes":5}'
output="$(tool_web_fetch 2>/dev/null)"
rm -rf "${mock_bin}"
printf '%s' "${output}"
SCRIPT

        [ "$status" -eq 0 ]
        expected='{"url":"https://example.com","status":200,"body":"ABCDE","truncated":true}'
        [ "${output}" = "${expected}" ]
}

@test "web tools register through the aggregator" {
        run bash <<'SCRIPT'
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
source ./src/lib/tools.sh
init_tool_registry
initialize_tools
mapfile -t names < <(tool_names)
for name in "${names[@]}"; do
        printf '%s\n' "${name}"
done
SCRIPT

        [ "$status" -eq 0 ]
        [[ " ${lines[*]} " == *" web_search "* ]]
        [[ " ${lines[*]} " == *" web_fetch "* ]]
}
