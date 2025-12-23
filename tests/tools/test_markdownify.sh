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
output=$(./src/tools/web/markdownify.sh --path "${body_file}" --content-type "text/html; charset=utf-8" --limit 64)
python3 - "${output}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["markdown"].strip(), "markdown should not be empty"
assert "Example Title" in payload["preview"], payload["preview"]
PY
SCRIPT

        [ "$status" -eq 0 ]
}

@test "markdownify formats json bodies" {
        run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
cp tests/fixtures/web_fetch_sample.json "${body_file}"
output=$(./src/tools/web/markdownify.sh --path "${body_file}" --content-type "application/json" --limit 80)
python3 - "${output}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["markdown"].startswith("```json"), payload["markdown"]
assert "Sample" in payload["preview"], payload["preview"]
PY
SCRIPT

        [ "$status" -eq 0 ]
}

@test "markdownify prettifies xml with xmllint" {
        run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
cp tests/fixtures/web_fetch_sample.xml "${body_file}"
output=$(./src/tools/web/markdownify.sh --path "${body_file}" --content-type "application/xml" --limit 120)
python3 - "${output}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["markdown"].startswith("```xml"), payload["markdown"]
assert "<note>" in payload["markdown"], payload["markdown"]
assert "note" in payload["preview"], payload["preview"]
PY
SCRIPT

        [ "$status" -eq 0 ]
}

@test "markdownify builds truncated previews" {
        run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
printf '%s' 'abcdefg' >"${body_file}"
output=$(./src/tools/web/markdownify.sh --path "${body_file}" --content-type "text/plain" --limit 3)
preview=$(python3 - "${output}" <<'PY'
import json
import sys

print(json.loads(sys.argv[1])["preview"])
PY)
[[ "${#preview}" -eq 3 ]]
[[ "${preview}" == "ab…" ]]
SCRIPT

        [ "$status" -eq 0 ]
}

@test "markdownify surfaces missing pandoc errors" {
        run bash <<'SCRIPT'
set -euo pipefail
body_file="$(mktemp)"
cp tests/fixtures/web_fetch_sample.html "${body_file}"
tmp_path="$(mktemp -d)"
cat >"${tmp_path}/pandoc" <<'MOCK'
#!/usr/bin/env bash
printf 'pandoc unavailable on PATH\n' >&2
exit 127
MOCK
chmod +x "${tmp_path}/pandoc"
PATH="${tmp_path}:${PATH_ORIG}"
./src/tools/web/markdownify.sh --path "${body_file}" --content-type "text/html" --limit 10
SCRIPT

        [ "$status" -ne 0 ]
        [[ "$output" == *"pandoc failed to convert HTML"* ]]
}
