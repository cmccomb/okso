#!/usr/bin/env bash
# shellcheck shell=bash
#
# State and history helpers for the ReAct execution loop.
#
# Usage:
#   source "${BASH_SOURCE[0]%/history.sh}/history.sh"
#
# Environment variables:
#   REACT_RETRY_BUFFER (int): extra attempts beyond the plan length; default: 2.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on state failures.

REACT_LIB_DIR=${REACT_LIB_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)}

# shellcheck source=../core/logging.sh disable=SC1091
source "${REACT_LIB_DIR}/../core/logging.sh"
# shellcheck source=../core/state.sh disable=SC1091
source "${REACT_LIB_DIR}/../core/state.sh"
# shellcheck source=../assistant/respond.sh disable=SC1091
source "${REACT_LIB_DIR}/../assistant/respond.sh"
# shellcheck source=../formatting.sh disable=SC1091
source "${REACT_LIB_DIR}/../formatting.sh"
# shellcheck source=../dependency_guards/dependency_guards.sh disable=SC1091
source "${REACT_LIB_DIR}/../dependency_guards/dependency_guards.sh"

initialize_react_state() {
	# Initializes the ReAct state document with user query, tools, and plan.
	# Arguments:
	#   $1 - state prefix to populate (string)
	#   $2 - user query (string)
	#   $3 - allowed tools (string, newline delimited)
	#   $4 - ranked plan entries (string)
	#   $5 - plan outline text (string)
	local state_prefix
	state_prefix="$1"

	local plan_entries plan_length retry_buffer max_steps
	plan_entries="$4"

	plan_length=$(printf '%s\n' "${plan_entries}" | jq -s 'map(try (if type=="string" then fromjson else . end) catch empty) | length' 2>/dev/null || printf '0')
	if ! [[ "${plan_length}" =~ ^[0-9]+$ ]]; then
		plan_length=0
	fi

	retry_buffer=${REACT_RETRY_BUFFER:-2}
	if ! [[ "${retry_buffer}" =~ ^[0-9]+$ ]] || ((retry_buffer < 0)); then
		retry_buffer=2
	fi

	max_steps=$((plan_length + retry_buffer))
	if ((max_steps < 1)); then
		max_steps=retry_buffer
	fi

	state_set_json_document "${state_prefix}" "$(jq -c -n \
		--arg user_query "$2" \
		--arg allowed_tools "$3" \
		--arg plan_entries "$4" \
		--arg plan_outline "$5" \
		--argjson max_steps "${max_steps}" \
		--argjson plan_length "${plan_length}" \
		--argjson retry_buffer "${retry_buffer}" \
		'{
                        user_query: $user_query,
                        allowed_tools: $allowed_tools,
                        plan_entries: $plan_entries,
                        plan_outline: $plan_outline,
                        history: [],
                        step: 0,
                        attempts: 0,
                        retry_count: 0,
                        plan_index: 0,
                        pending_plan_step: null,
                        plan_skip_reason: "",
                        max_steps: $max_steps,
                        final_answer: "",
                        final_answer_action: "",
                        last_action: null
                }')"

	state_set "${state_prefix}" "plan_length" "${plan_length}"
	state_set "${state_prefix}" "retry_buffer" "${retry_buffer}"
}

record_history() {
	# Appends a formatted history entry to the ReAct state.
	# Arguments:
	#   $1 - state prefix (string)
	#   $2 - formatted history entry (string)
	local entry
	entry="$2"
	state_append_history "$1" "${entry}"
}

state_get_history_lines() {
	# Retrieves history as a newline-delimited string.
	# Arguments:
	#   $1 - state prefix (string)
	# Returns:
	#   Newline-delimited string of history entries where past steps include
	#   observation summaries and the latest step favors raw output when available.
	local state_prefix history_raw
	state_prefix="$1"
	history_raw="$(state_get "${state_prefix}" "history")"

	if jq -e 'type == "array"' <<<"${history_raw}" >/dev/null 2>&1; then
		jq -cr '
                        (. // []) as $entries
                        | ($entries | length) as $len
                        | $entries
                        | to_entries
                        | map(
                                . as $entry
                                | ($entry.value | try (fromjson // .) catch .) as $parsed
                                | if ($parsed | type == "object") then
                                        ($parsed + {
                                                observation: (
                                                        if $entry.key == ($len - 1) then
                                                                ($parsed.observation_raw // $parsed.observation_summary // $parsed.observation // "")
                                                        else
                                                                ($parsed.observation_summary // $parsed.observation // $parsed.observation_raw // "")
                                                        end
                                                )
                                        })
                                else
                                        $parsed
                                end
                        )
                        | .[]
                ' <<<"${history_raw}"
		return 0
	fi

	printf '%s' "${history_raw}"
}

record_tool_execution() {
	# Records a tool execution into history.
	# Arguments:
	#   $1 - state prefix
	#   $2 - tool name
	#   $3 - thought text
	#   $4 - args JSON
	#   $5 - observation raw payload
	#   $6 - observation summary
	#   $7 - step index
	local state_name
	local tool thought args_json observation_raw observation_summary step_index entry
	state_name="$1"
	tool="$2"
	thought="$3"
	args_json="$4"
	observation_raw="$5"
	observation_summary="$6"
	step_index="$7"
	if [[ -z "${args_json}" ]]; then
		args_json="{}"
	fi
	args_json="$(jq -cS '.' <<<"${args_json}" 2>/dev/null || printf '{}')"

	if [[ -z "${observation_summary}" ]]; then
		observation_summary="${observation_raw}"
	fi

	if ! require_python3_available "ReAct history serialization"; then
		log "ERROR" "Failed to record tool execution; python3 missing" "${tool}" >&2
		return 1
	fi

	entry=$(
		python3 - "$step_index" "$thought" "$tool" "$args_json" "$observation_raw" "$observation_summary" <<'PY'
import json
import sys

step = int(sys.argv[1])
thought = sys.argv[2]
tool = sys.argv[3]
args_raw = sys.argv[4]
observation_raw = sys.argv[5]
observation_summary = sys.argv[6]

try:
    args = json.loads(args_raw)
except Exception:  # noqa: BLE001
    args = {}

try:
    obs_raw_payload = json.loads(observation_raw)
except Exception:  # noqa: BLE001
    obs_raw_payload = observation_raw

try:
    obs_summary_payload = json.loads(observation_summary)
except Exception:  # noqa: BLE001
    obs_summary_payload = observation_summary

print(json.dumps({
    "step": step,
    "thought": thought,
    "action": {"tool": tool, "args": args},
    "observation_raw": obs_raw_payload,
    "observation_summary": obs_summary_payload,
    "observation": obs_summary_payload,
}, separators=(",", ":")))
PY
	)
	record_history "${state_name}" "${entry}"
	log "INFO" "Recorded tool execution" "$(printf 'step=%s tool=%s' "${step_index}" "${tool}")"
}

finalize_react_result() {
	# Finalizes and emits the ReAct run result.
	# Arguments:
	#   $1 - state prefix
	local state_name history_formatted final_answer observation final_answer_action
	state_name="$1"
	observation="$(state_get "${state_name}" "final_answer")"
	final_answer_action="$(state_get "${state_name}" "final_answer_action")"
	if [[ -z "${observation}" ]]; then
		if [[ -n "${final_answer_action}" ]]; then
			final_answer="${final_answer_action}"
		else
			log "ERROR" "Final answer missing; generating fallback" "${state_name}"
			history_formatted="$(format_tool_history "$(state_get_history_lines "${state_name}")")"
			final_answer="$(respond_text "$(state_get "${state_name}" "user_query")" 1000 "${history_formatted}")"
			state_set "${state_name}" "final_answer" "${final_answer}"
		fi
	else
		if jq -e '.output != null and .exit_code != null' <<<"${observation}" >/dev/null 2>&1; then
			final_answer=$(jq -r '.output' <<<"${observation}")
		else
			final_answer="${observation}"
		fi
	fi

	state_set "${state_name}" "final_answer" "${final_answer}"

	log_pretty "INFO" "Final answer" "${final_answer}"
	if [[ -z "$(format_tool_history "$(state_get_history_lines "${state_name}")")" ]]; then
		log "INFO" "Execution summary" "No tool runs"
	else
		log_pretty "INFO" "Execution summary" "$(format_tool_history "$(state_get_history_lines "${state_name}")")"
	fi

	emit_boxed_summary \
		"$(state_get "${state_name}" "user_query")" \
		"$(state_get "${state_name}" "plan_outline")" \
		"$(state_get_history_lines "${state_name}")" \
		"${final_answer}"
}
