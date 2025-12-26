#!/usr/bin/env bash
# shellcheck shell=bash
#
# State and history helpers for the executor loop.
#
# Usage:
#   source "${BASH_SOURCE[0]%/history.sh}/history.sh"
#
# Environment variables:
#   MAX_STEPS (int): maximum number of executor turns; default: 6.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on state failures.

EXECUTOR_LIB_DIR=${EXECUTOR_LIB_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)}

# shellcheck source=../core/logging.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../core/logging.sh"
# shellcheck source=../core/state.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../core/state.sh"
# shellcheck source=../assistant/respond.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../assistant/respond.sh"
# shellcheck source=../formatting.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../formatting.sh"
# shellcheck source=../dependency_guards/dependency_guards.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/../dependency_guards/dependency_guards.sh"

initialize_executor_state() {
	# Initializes the executor state document with user query, tools, and plan.
	# Arguments:
	#   $1 - state prefix to populate (string)
	#   $2 - user query (string)
	#   $3 - allowed tools (string, newline delimited)
	#   $4 - ranked plan entries (string)
	#   $5 - plan outline text (string)
	local state_prefix
	state_prefix="$1"

	state_set_json_document "${state_prefix}" "$(jq -c -n \
		--arg user_query "$2" \
		--arg allowed_tools "$3" \
		--arg plan_entries "$4" \
		--arg plan_outline "$5" \
		--argjson max_steps "${MAX_STEPS:-6}" \
		'{
                        user_query: $user_query,
                        allowed_tools: $allowed_tools,
                        plan_entries: $plan_entries,
                        plan_outline: $plan_outline,
                        history: [],
                        step: 0,
                        plan_index: 0,
                        max_steps: $max_steps,
                        final_answer: "",
                        final_answer_action: "",
                        last_action: null
                }')"
}

record_history() {
	# Appends a formatted history entry to the executor state.
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
	#   Newline-delimited string of history entries.
	local state_prefix history_raw
	state_prefix="$1"
	history_raw="$(state_get "${state_prefix}" "history")"

	if jq -e 'type == "array"' <<<"${history_raw}" >/dev/null 2>&1; then
		jq -r '.[]' <<<"${history_raw}"
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
	#   $5 - observation text
	#   $6 - step index
	local state_name
	local tool thought args_json observation step_index entry
	state_name="$1"
	tool="$2"
	thought="$3"
	args_json="$4"
	observation="$5"
	step_index="$6"
	if [[ -z "${args_json}" ]]; then
		args_json="{}"
	fi
	args_json="$(jq -cS '.' <<<"${args_json}" 2>/dev/null || printf '{}')"

	if ! require_python3_available "Executor history serialization"; then
		log "ERROR" "Failed to record tool execution; python3 missing" "${tool}" >&2
		return 1
	fi

	entry=$(
		python3 - "$step_index" "$thought" "$tool" "$args_json" "$observation" <<'PY'
import json
import sys

step = int(sys.argv[1])
thought = sys.argv[2]
tool = sys.argv[3]
args_raw = sys.argv[4]
observation = sys.argv[5]

try:
    args = json.loads(args_raw)
except Exception:  # noqa: BLE001
    args = {}

try:
    obs_payload = json.loads(observation)
except Exception:  # noqa: BLE001
    obs_payload = observation

print(json.dumps({
    "step": step,
    "thought": thought,
    "action": {"tool": tool, "args": args},
    "observation": obs_payload,
}, separators=(",", ":")))
PY
	)
	record_history "${state_name}" "${entry}"
	log "INFO" "Recorded tool execution" "$(printf 'step=%s tool=%s' "${step_index}" "${tool}")"
}

finalize_executor_result() {
	# Finalizes and emits the executor run result.
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
