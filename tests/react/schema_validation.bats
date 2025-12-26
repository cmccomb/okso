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
