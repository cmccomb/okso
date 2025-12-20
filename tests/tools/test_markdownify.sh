#!/usr/bin/env bats
#
# Tests for the markdownify shell converter.
#
# Usage:
#   bats tests/tools/test_markdownify.sh

setup() {
	export PATH_ORIG="${PATH}"
}

teardown() {
	export PATH="${PATH_ORIG}"
}

@test "markdownify converts html using text-mode browser" {
	run bash <<'SCRIPT'
set -euo pipefail
mock_bin="$(mktemp -d)"
cat >"${mock_bin}/lynx" <<'MOCK'
#!/usr/bin/env bash
# minimal lynx mock: echo stdin when called with -dump -stdin
if [[ "$1" == "-dump" && "$2" == "-stdin" ]]; then
        sed -E 's/<[^>]+>//g'
        exit 0
fi
exit 1
MOCK
chmod +x "${mock_bin}/lynx"
PATH="${mock_bin}:$PATH"
body_file="$(mktemp)"
cp tests/fixtures/web_fetch_sample.html "${body_file}"
output=$(./src/tools/web/markdownify.sh --path "${body_file}" --content-type "text/html; charset=utf-8" --limit 64)
jq -e '(.markdown | length) > 0' <<<"${output}" >/dev/null
jq -e '(.preview | contains("Example Title"))' <<<"${output}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}

@test "markdownify formats json bodies" {
	run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
cp tests/fixtures/web_fetch_sample.json "${body_file}"
output=$(./src/tools/web/markdownify.sh --path "${body_file}" --content-type "application/json" --limit 80)
jq -e '.markdown | startswith("```json")' <<<"${output}" >/dev/null
jq -e '.preview | contains("Sample")' <<<"${output}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}

@test "markdownify prettifies xml with xmllint" {
	run bash <<'SCRIPT'
set -euo pipefail
mock_bin="$(mktemp -d)"
cat >"${mock_bin}/xmllint" <<'MOCK'
#!/usr/bin/env bash
# simple xmllint mock: pretty-print with line breaks between tags
if [[ "$1" == "--format" ]]; then
        input="$2"
        sed 's/></>\n</g' "${input}"
        exit 0
fi
exit 1
MOCK
chmod +x "${mock_bin}/xmllint"
PATH="${mock_bin}:$PATH"
body_file="$(mktemp)"
cp tests/fixtures/web_fetch_sample.xml "${body_file}"
output=$(./src/tools/web/markdownify.sh --path "${body_file}" --content-type "application/xml" --limit 120)
jq -e '.markdown | startswith("```xml")' <<<"${output}" >/dev/null
jq -e '.preview | contains("note")' <<<"${output}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}

@test "markdownify builds truncated previews" {
	run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
printf '%s' 'abcdefg' >"${body_file}"
output=$(./src/tools/web/markdownify.sh --path "${body_file}" --content-type "text/plain" --limit 3)
preview=$(jq -r '.preview' <<<"${output}")
[[ "${#preview}" -eq 3 ]]
[[ "${preview}" == "ab…" ]]
SCRIPT

	[ "$status" -eq 0 ]
}
