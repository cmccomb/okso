#!/usr/bin/env bash
# shellcheck shell=bash
#
# Planner candidate scoring utilities.
#
# The scorer runs after normalization to rank multiple planner candidates. It
# penalizes long or unsafe plans, rewards adherence to the final_answer contract,
# and encodes rationale strings so operators can trace why a candidate won. The
# resulting scorecard drives selection in planner.sh before execution begins.
#
# Usage:
#   source "${BASH_SOURCE[0]%/scoring.sh}/scoring.sh"
#
# Environment variables:
#   PLANNER_MAX_PLAN_STEPS (int): upper bound for plan length; defaults to 6.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on validation failures.

PLANNING_SCORING_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=../core/logging.sh disable=SC1091
source "${PLANNING_SCORING_DIR}/../core/logging.sh"

planner_is_tool_available() {
	# Checks whether the provided tool is registered.
	# Arguments:
	#   $1 - tool name (string)
	#   $2 - newline-delimited tool names (string)
	local tool available_tools
	tool="$1"
	available_tools="$2"

	grep -Fxq "${tool}" <<<"${available_tools}" 2>/dev/null
}

planner_terminal_command_has_side_effects() {
	# Determines if a terminal command is likely to produce side effects.
	# Arguments:
	#   $1 - terminal args JSON (string)
	# Returns 0 when side effects are likely; 1 otherwise.
	local args_json command first_word
	args_json=${1:-"{}"}
	command=$(jq -r '.command // ""' <<<"${args_json}" 2>/dev/null)

	# Missing command defaults to side-effecting for safety.
	if [[ -z "${command}" ]]; then
		return 0
	fi

	# Trim leading whitespace to find the first token.
	command=${command#"${command%%[![:space:]]*}"}
	first_word=${command%%[[:space:]]*}

	# Redirections imply filesystem mutations.
	if [[ "${command}" == *">"* ]] || [[ "${command}" == *">>"* ]] || [[ "${command}" == *"<<"* ]] || [[ "${command}" == *"2>"* ]] || [[ "${command}" == *"&>"* ]]; then
		return 0
	fi

	case "${first_word}" in
	ls | cat | pwd | head | tail | grep | find)
		return 1
		;;
	rm | mv | cp | touch | tee | chmod | chown | mkdir | rmdir | ln | mktemp)
		return 0
		;;
	sed)
		if [[ " ${command} " == *" -i"* ]]; then
			return 0
		fi
		return 1
		;;
	esac

	# Unknown commands default to side-effecting to avoid unsafe optimism.
	return 0
}

python_repl_has_side_effects() {
	# Detects if a python_repl snippet is likely to mutate state or perform I/O.
	# Arguments:
	#   $1 - python_repl args JSON (string)
	# Returns 0 when side effects are likely; 1 otherwise.
	local args_json snippet
	args_json=${1:-"{}"}
	snippet=$(jq -r '.code // .snippet // .text // ""' <<<"${args_json}" 2>/dev/null)

	# Empty or unreadable snippets default to side-effecting for safety.
	if [[ -z "${snippet}" ]]; then
		return 0
	fi

	local -a patterns=()
	mapfile -t patterns <<'EOF'
open\([^)]*["'](w|a|x)[^"']*["']
open\([^)]*["'][^"']*\+[^"']*["']
Path\([^)]*\)\.write_text\(
Path\([^)]*\)\.write_bytes\(
Path\([^)]*\)\.unlink\(
Path\([^)]*\)\.rename\(
Path\([^)]*\)\.replace\(
Path\([^)]*\)\.mkdir\(
Path\([^)]*\)\.rmdir\(
Path\([^)]*\)\.touch\(
os\.remove\(
os\.unlink\(
os\.rename\(
os\.replace\(
os\.rmdir\(
os\.mkdir\(
os\.makedirs\(
shutil\.(copy|copy2|copytree|move|rmtree)\(
subprocess\.(run|call|Popen|check_call|check_output)\(
os\.system\(
(import|from)[[:space:]]+requests
urllib\.request
http\.client
socket
requests\.(get|post|put|delete|head|patch|options)\(
os\.environ\[
EOF

	local pattern
	for pattern in "${patterns[@]}"; do
		if grep -Eqi -- "${pattern}" <<<"${snippet}"; then
			return 0
		fi
	done

	return 1
}

planner_step_has_side_effects() {
	# Heuristic to detect steps that can mutate user data or environment.
	# Arguments:
	#   $1 - tool name (string)
	#   $2 - tool args JSON (string)
	case "$1" in
	final_answer | web_search | notes_list | notes_read | notes_search | reminders_list | calendar_list | calendar_search | feedback)
		return 1
		;;
	*) ;;
	esac

	if [[ "$1" == "python_repl" ]]; then
		python_repl_has_side_effects "$2"
		return
	fi

	if [[ "$1" == "terminal" ]]; then
		planner_terminal_command_has_side_effects "$2"
		return
	fi

	if [[ "$1" =~ ^mail_ ]]; then
		return 0
	fi

	if [[ "$1" =~ (create|append|delete|update|send|write|draft) ]]; then
		return 0
	fi

	case "$1" in
	notes_create | notes_append | reminders_create | calendar_create | mail_send | mail_draft)
		return 0
		;;
	esac

	return 1
}

planner_args_satisfiable() {
	local schema_json args_json
	schema_json=${1:-"{}"}
	args_json=${2:-"{}"}

	# Empty schema => accept.
	if jq -e 'type=="object" and length==0' >/dev/null 2>&1 <<<"${schema_json}"; then
		return 0
	fi

	python3 - "${schema_json}" "${args_json}" <<'PY' 2>/dev/null
import json, sys
from jsonschema import Draft202012Validator

schema = json.loads(sys.argv[1])
args = json.loads(sys.argv[2])

# Allow partial args from the planner by removing the 'required' constraint
if isinstance(schema, dict):
    schema.pop("required", None)

try:
    Draft202012Validator(schema).validate(args)
except Exception:
    sys.exit(1)
sys.exit(0)
PY
}

score_planner_candidate() {
	# Scores a normalized planner response for downstream selection.
	# Arguments:
	#   $1 - normalized planner response JSON (string)
	local normalized_json plan_json plan_length max_steps available_tools availability_known
	local score tie_breaker over_budget rationale_json final_tool
	local -a rationale=()

	normalized_json="$1"
	max_steps=${PLANNER_MAX_PLAN_STEPS:-6}
	if ! [[ "${max_steps}" =~ ^[0-9]+$ ]] || ((max_steps < 1)); then
		max_steps=6
	fi

	plan_json=$(jq -c '.plan' <<<"${normalized_json}" 2>/dev/null) || return 1
	plan_length=$(jq -r 'length' <<<"${plan_json}" 2>/dev/null)

	log_pretty "INFO" "Evaluating planner plan structure" "${plan_json}" >&2

	# Start with a score of 0, and add a tie_breaker based on how well the plan fits within the step budget.
	score=0
	tie_breaker=$((max_steps - plan_length))

	# Add a score based on plan length
	if ((plan_length <= max_steps)); then
		score=$((score + 20 + tie_breaker))
		rationale+=("Plan fits within ${max_steps}-step budget.")
	else
		over_budget=$((plan_length - max_steps))
		score=$((score - (over_budget * 10)))
		tie_breaker=$((-over_budget))
		rationale+=("Plan exceeds ${max_steps}-step budget by ${over_budget} step(s).")
	fi

	# Add a score based on the final answer tool
	final_tool=$(jq -r '.[-1].tool // ""' <<<"${plan_json}")
	if [[ "${final_tool}" == "final_answer" ]]; then
		score=$((score + 15))
		rationale+=("Plan terminates with final_answer.")
	else
		score=$((score - 25))
		rationale+=("Plan must terminate with final_answer as the final step.")
	fi

	available_tools="$(tool_names)"
	availability_known=true
	if [[ -z "${available_tools}" ]]; then
		availability_known=false
		rationale+=("Tool registry is empty; skipping availability checks.")
	fi

	local idx=0 valid_tools=0 missing_tools=0 invalid_args=0 side_effect_index=-1
	while IFS= read -r step; do
		local tool args schema
		tool=$(jq -r '.tool // ""' <<<"${step}")
		args=$(jq -c '.args // {}' <<<"${step}")
		schema="$(tool_args_schema "${tool}")"

		if [[ "${availability_known}" == true ]]; then
			if planner_is_tool_available "${tool}" "${available_tools}"; then
				valid_tools=$((valid_tools + 1))
			else
				missing_tools=$((missing_tools + 1))
			fi
		fi

		if [[ -n "${schema}" ]] && ! planner_args_satisfiable "${schema}" "${args}"; then
			invalid_args=$((invalid_args + 1))
		fi

		if ((side_effect_index < 0)) && planner_step_has_side_effects "${tool}" "${args}"; then
			side_effect_index=${idx}
		fi

		idx=$((idx + 1))
	done < <(jq -cr '.[]' <<<"${plan_json}")

	score=$((score + (valid_tools * 3)))
	if ((missing_tools > 0)); then
		score=$((score - (missing_tools * 25)))
		rationale+=("Plan references ${missing_tools} unavailable tool(s).")
		log "INFO" "Planner scoring: unavailable tools detected" "$(jq -nc --argjson missing "${missing_tools}" --argjson valid "${valid_tools}" '{missing:$missing,valid:$valid}')" >&2
	elif [[ "${availability_known}" == true ]]; then
		rationale+=("All tools are registered in the planner catalog.")
	fi

	if ((invalid_args > 0)); then
		score=$((score - (invalid_args * 10)))
		rationale+=("Args fail schema checks for ${invalid_args} step(s).")
		log "INFO" "Planner scoring: argument validation failed" "$(jq -nc --argjson invalid "${invalid_args}" --argjson checked "${idx}" '{invalid:$invalid,checked:$checked}')" >&2
	else
		rationale+=("Planner args satisfy registered tool schemas.")
	fi

	if ((side_effect_index == 0 && plan_length > 1)); then
		score=$((score - 10))
		rationale+=("First step is side-effecting before gathering information.")
	elif ((side_effect_index > 0)); then
		score=$((score + 5))
		rationale+=("Side-effecting actions are deferred until step $((side_effect_index + 1)).")
	else
		score=$((score + 5))
		rationale+=("No side-effecting tools detected in the plan.")
	fi

	rationale_json=$(printf '%s\0' "${rationale[@]}" | jq -Rs 'split("\u0000") | map(select(length>0))')
	log "INFO" "Planner scoring summary" "$(jq -nc --argjson score "${score}" --argjson tie_breaker "${tie_breaker}" --argjson plan_length "${plan_length}" --argjson missing_tools "${missing_tools}" --argjson invalid_args "${invalid_args}" --argjson side_effect_index "${side_effect_index}" '{score:$score,tie_breaker:$tie_breaker,plan_length:$plan_length,missing_tools:$missing_tools,invalid_args:$invalid_args,side_effect_index:$side_effect_index}')" >&2
	jq -nc --argjson score "${score}" --argjson tie_breaker "${tie_breaker}" --argjson plan_length "${plan_length}" --argjson max_steps "${max_steps}" --argjson rationale "${rationale_json}" '{score:$score,tie_breaker:$tie_breaker,plan_length:$plan_length,max_steps:$max_steps,rationale:$rationale}'
}

export -f planner_args_satisfiable
export -f planner_is_tool_available
export -f planner_step_has_side_effects
export -f planner_terminal_command_has_side_effects
export -f python_repl_has_side_effects
export -f score_planner_candidate
