#!/usr/bin/env bats

@test "summarize_terminal_output yields bounded JSON summary" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/observation_summary.sh
payload='{"output":"line1\nline2","error":"oops","exit_code":2,"cwd":"/tmp/work"}'
summary=$(summarize_terminal_output "${payload}" "/fallback")
printf '%s' "${summary}" | jq -e '(.exit_code == 2) and (.cwd == "/tmp/work") and (.output.head | contains("line1"))'
SCRIPT

	[ "$status" -eq 0 ]
}

@test "summarize_text_block avoids pipefail noise when truncated by consumer" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/observation_summary.sh
payload=$(printf '%*s' 400 | tr ' ' 'y')
summary=$(summarize_text_block "${payload}")
printf '%s' "${summary}" | head -n1 >/dev/null
SCRIPT

	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
}

@test "summarize_web_search_results captures top items deterministically" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/observation_summary.sh
payload=$(jq -nc '{output: {query:"alpha", total_results: 25, items: [ {title:"First", url:"http://a", snippet:"one"}, {title:"Second", url:"http://b", snippet:"two"}, {title:"Third", url:"http://c", snippet:"three"}, {title:"Fourth", url:"http://d", snippet:"four"}]}}')
summary=$(summarize_web_search_results "${payload}")
printf '%s' "${summary}" | jq -e '(.query == "alpha") and (.total_results == 25) and (.item_count == 4) and (.top_items | length == 3)'
SCRIPT

	[ "$status" -eq 0 ]
}

@test "summarize_web_fetch_results uses deterministic terminal summary" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/observation_summary.sh
body=$(printf '%*s' 300 | tr ' ' 'x')
payload=$(jq -nc --arg body "${body}" '{output:{output:$body,exit_code:0,cwd:null}}')
summary=$(summarize_observation "web_fetch" "${payload}" "/fallback")
printf '%s' "${summary}" | jq -e '(.cwd == "/fallback") and (.output.head | length == 120) and (.output.tail | length == 120)'
SCRIPT

	[ "$status" -eq 0 ]
}

@test "summarize_file_ops reports touched paths and summaries deterministically" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/observation_summary.sh
observation=$(jq -nc '{cwd:"/tmp/work",created:["a.txt"],updated:["b.txt"],deleted:["c.txt"],output:"preview"}')
summary=$(summarize_observation "write_files" "${observation}" "/fallback")
printf '%s' "${summary}" | jq -e '(.cwd == "/tmp/work") and (.created == ["a.txt"]) and (.updated == ["b.txt"]) and (.deleted == ["c.txt"]) and (.output.head == "preview")'
SCRIPT

	[ "$status" -eq 0 ]
}

@test "select_observation_summary prefers embedded summary" {
	run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/observation_summary.sh
observation=$(jq -nc '{output:"",exit_code:0,summary:{ok:true}}')
summary=$(select_observation_summary "terminal" "${observation}" "/tmp")
printf '%s' "${summary}" | jq -e '.ok == true'
SCRIPT

	[ "$status" -eq 0 ]
}
