#!/usr/bin/env bats

setup() {
        unset -f chpwd _mise_hook 2>/dev/null || true
}

@test "react schema accepts required args marked missing" {
        run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/schema.sh

tool_registry_json() {
        cat <<'JSON'
{"names":["alpha"],"registry":{"alpha":{"args_schema":{"type":"object","properties":{"needed":{"type":"string"},"optional":{"type":"string"},"nested":{"type":"object","properties":{"inner":{"type":"integer"}},"required":["inner"]}},"required":["needed","nested"],"additionalProperties":false}}}}
JSON
}

tool_names() {
        printf 'alpha\n'
}

schema_path=$(build_react_action_schema "alpha")
action_missing='{"action":{"tool":"alpha","args":{"needed":"__MISSING__","nested":{"inner":"__MISSING__"},"optional":"ok"}}}'
validate_react_action "${action_missing}" "${schema_path}" >/tmp/validated_action.json
cat /tmp/validated_action.json
SCRIPT

        [ "$status" -eq 0 ]
        [[ "${output}" == *'"needed":"__MISSING__"'* ]]
        [[ "${output}" == *'"inner":"__MISSING__"'* ]]
}

@test "react schema accepts fully specified payloads" {
        run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/schema.sh

tool_registry_json() {
        cat <<'JSON'
{"names":["alpha"],"registry":{"alpha":{"args_schema":{"type":"object","properties":{"needed":{"type":"string"},"optional":{"type":"string"},"nested":{"type":"object","properties":{"inner":{"type":"integer"}},"required":["inner"]}},"required":["needed","nested"],"additionalProperties":false}}}}
JSON
}

tool_names() {
        printf 'alpha\n'
}

schema_path=$(build_react_action_schema "alpha")
action_full='{"action":{"tool":"alpha","args":{"needed":"value","optional":"skip","nested":{"inner":5}}}}'
validate_react_action "${action_full}" "${schema_path}" >/tmp/validated_action.json
cat /tmp/validated_action.json
SCRIPT

        [ "$status" -eq 0 ]
        [[ "${output}" == *'"needed":"value"'* ]]
        [[ "${output}" == *'"inner":5'* ]]
}

@test "react schema rejects unexpected fields with clear error" {
        run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/schema.sh

tool_registry_json() {
        cat <<'JSON'
{"names":["alpha"],"registry":{"alpha":{"args_schema":{"type":"object","properties":{"input":{"type":"string"}},"required":["input"],"additionalProperties":false}}}}
JSON
}

tool_names() {
        printf 'alpha\n'
}

schema_path=$(build_react_action_schema "alpha")
invalid_action='{"action":{"tool":"alpha","args":{"input":"value","extra":"nope"},"unexpected":true}}'

set +e
validate_react_action "${invalid_action}" "${schema_path}" 2>err.log
status=$?
set -e

rm -f "${schema_path}"

if [[ ${status} -eq 0 ]]; then
        echo "validation unexpectedly succeeded"
        exit 1
fi

cat err.log
grep -F "action/args: Additional properties are not allowed ('extra' was unexpected)" err.log
rm -f err.log
SCRIPT

        [ "$status" -eq 0 ]
}

@test "react schema surfaces argument type failures" {
        run bash <<'SCRIPT'
set -euo pipefail
source ./src/lib/react/schema.sh

tool_registry_json() {
        cat <<'JSON'
{"names":["alpha"],"registry":{"alpha":{"args_schema":{"type":"object","properties":{"count":{"type":"integer"}},"required":["count"],"additionalProperties":false}}}}
JSON
}

tool_names() {
        printf 'alpha\n'
}

schema_path=$(build_react_action_schema "alpha")
invalid_action='{"action":{"tool":"alpha","args":{"count":"oops"}}}'

set +e
validate_react_action "${invalid_action}" "${schema_path}" 2>err.log
status=$?
set -e

rm -f "${schema_path}"

if [[ ${status} -eq 0 ]]; then
        echo "validation unexpectedly succeeded"
        exit 1
fi

cat err.log
grep -F "action/args/count: 'oops' is not of type 'integer'" err.log
rm -f err.log
SCRIPT

        [ "$status" -eq 0 ]
}
