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

@test "markdownify converts html using pandoc" {
        run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
cp tests/fixtures/web_fetch_sample.html "${body_file}"
tbin="$(mktemp -d)"
cat >"${tbin}/pandoc" <<'MOCK'
#!/usr/bin/env bash
cat <<'OUT'
# Example Title

Example body
OUT
MOCK
chmod +x "${tbin}/pandoc"
PATH="${tbin}:${PATH}" output=$(./src/tools/web/markdownify.sh --path "${body_file}" --content-type "text/html; charset=utf-8" --limit 64)
jq -e '
        (.markdown | length) > 0 and
        (.preview | contains("Example Title"))
' <<<"${output}" >/dev/null
SCRIPT

        [ "$status" -eq 0 ]
}

@test "markdownify falls back to lynx when pandoc is unavailable" {
        run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
cp tests/fixtures/web_fetch_sample.html "${body_file}"
tbin="$(mktemp -d)"
cat >"${tbin}/lynx" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "-dump" && "$2" == "-stdin" ]]; then
        sed -E 's/<[^>]+>//g'
        exit 0
fi
exit 1
MOCK
chmod +x "${tbin}/lynx"
PATH="${tbin}:${PATH_ORIG}" output=$(./src/tools/web/markdownify.sh --path "${body_file}" --content-type "text/html" --limit 64)
jq -e '
        (.markdown | contains("Example Title")) and
        (.preview | contains("Example Title"))
' <<<"${output}" >/dev/null
SCRIPT

        [ "$status" -eq 0 ]
}

@test "markdownify formats json bodies" {
        run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
cp tests/fixtures/web_fetch_sample.json "${body_file}"
output=$(./src/tools/web/markdownify.sh --path "${body_file}" --content-type "application/json" --limit 80)
jq -e '
        (.markdown | startswith("```json")) and
        (.preview | contains("Sample"))
' <<<"${output}" >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
}

@test "markdownify prettifies xml with xmllint" {
	run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
cp tests/fixtures/web_fetch_sample.xml "${body_file}"
tbin="$(mktemp -d)"
cat >"${tbin}/xmllint" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "--format" ]]; then
        shift
fi
cat "$@"
MOCK
chmod +x "${tbin}/xmllint"
PATH="${tbin}:${PATH}" output=$(./src/tools/web/markdownify.sh --path "${body_file}" --content-type "application/xml" --limit 120)
jq -e '
        (.markdown | startswith("```xml")) and
        (.markdown | contains("<note>")) and
        (.preview | contains("note"))
' <<<"${output}" >/dev/null
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

@test "markdownify errors when no HTML converter exists" {
        run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
cp tests/fixtures/web_fetch_sample.html "${body_file}"
PATH="/bin:/usr/bin"
./src/tools/web/markdownify.sh --path "${body_file}" --content-type "text/html" --limit 10
SCRIPT

        [ "$status" -ne 0 ]
        [[ "$output" == *"no HTML converter available"* ]]
}
