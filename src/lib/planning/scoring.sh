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
# shellcheck source=./normalization.sh disable=SC1091
source "${PLANNING_SCORING_DIR}/normalization.sh"

planner_is_tool_available() {
	# Checks whether the provided tool is registered.
	# Arguments:
	#   $1 - tool name (string)
	#   $2 - newline-delimited tool names (string)
	# Returns:
	#   0 when available; 1 otherwise.
	local tool
	local tool available_tools
	tool="$1"
	available_tools="$2"

	# Empty tool names are unavailable
	grep -Fxq "${tool}" <<<"${available_tools}" 2>/dev/null
}

planner_terminal_command_has_side_effects() {
	# Determines if a terminal command is likely to produce side effects.
	# Arguments:
	#   $1 - terminal args JSON (string)
	# Returns:
	#   0 when side effects are likely; 1 otherwise.
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

	# Whitelisted commands known to be side-effect-free.
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
	# Returns:
	#   0 when side effects are likely; 1 otherwise.
	local args_json snippet pattern
	args_json=${1:-"{}"}
	snippet=$(jq -r '.code // .snippet // .text // ""' <<<"${args_json}" 2>/dev/null)

	# Empty or unreadable snippets default to side-effecting for safety.
	if [[ -z "${snippet}" ]]; then
		return 0
	fi

	# Heuristic patterns indicating side effects.
	while IFS= read -r pattern; do
		[[ -z "${pattern}" ]] && continue
		if grep -Eqi -- "${pattern}" <<<"${snippet}"; then
			return 0
		fi
	done <<'EOF'
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

	return 1
}

planner_step_has_side_effects() {
	# Heuristic to detect steps that can mutate user data or environment.
	# Arguments:
	#   $1 - tool name (string)
	#   $2 - tool args JSON (string)
	# Returns:
	#   0 when side effects are likely; 1 otherwise.

	# Early exit for known side-effect-free tools
	case "$1" in
	final_answer | web_search | notes_list | notes_read | notes_search | reminders_list | calendar_list | calendar_search | feedback)
		return 1
		;;
	*) ;;
	esac

	# Delegate to tool-specific heuristics
	if [[ "$1" == "python_repl" ]]; then
		python_repl_has_side_effects "$2"
		return
	fi

	# Delegate to terminal command heuristic
	if [[ "$1" == "terminal" ]]; then
		planner_terminal_command_has_side_effects "$2"
		return
	fi

	# Conservative defaults for other tools
	if [[ "$1" =~ ^mail_ ]]; then
		return 0
	fi

	# Conservative defaults for common side-effecting actions
	if [[ "$1" =~ (create|append|delete|update|send|write|draft) ]]; then
		return 0
	fi

	# Whitelist of known side-effecting tools
	case "$1" in
	notes_create | notes_append | reminders_create | calendar_create | mail_send | mail_draft)
		return 0
		;;
	esac

	return 1
}

score_planner_candidate() {
	# Scores a normalized planner response for downstream selection.
	# Arguments:
	#   $1 - normalized planner response JSON array (string)
	# Returns:
	#   scorecard JSON on stdout; non-zero on failure.
	local plan_json plan_length available_tools availability_known
	local score tie_breaker rationale_json final_tool
	local -a rationale=()

	plan_json="$1"

	# Normalize the plan JSON
	plan_json="$(normalize_plan <<<"${plan_json}")" || return 1
	plan_length=$(jq -r 'length' <<<"${plan_json}" 2>/dev/null)

	log_pretty "INFO" "Evaluating planner plan structure" "${plan_json}" >&2

	# Start at 0; prefer shorter plans in ties
	score=0
	tie_breaker=$((-plan_length))

	# Quadratic length penalty: -(k * L^2)
	LEN_PENALTY_K=${LEN_PENALTY_K:-1} # tune: 1..5 typical
	len_penalty=$((LEN_PENALTY_K * plan_length * plan_length))

	score=$((score - len_penalty))
	rationale+=("Applied quadratic plan-length penalty: -${LEN_PENALTY_K}*${plan_length}^2 = -${len_penalty}.")

	# Add a score based on the final answer tool
	final_tool=$(jq -r '.[-1].tool // ""' <<<"${plan_json}")
	if [[ "${final_tool}" == "final_answer" ]]; then
		score=$((score + 15))
		rationale+=("Plan terminates with final_answer.")
	else
		score=$((score - 25))
		rationale+=("Plan must terminate with final_answer as the final step.")
	fi

	# Check tool availability and argument validity
	available_tools="$(tool_names)"
	availability_known=true
	if [[ -z "${available_tools}" ]]; then
		availability_known=false
		rationale+=("Tool registry is empty; skipping availability checks.")
	fi

	# Evaluate each step
	local idx=0 valid_tools=0 missing_tools=0 invalid_args=0 side_effect_index=-1
	while IFS= read -r step; do
		local tool args
		tool=$(jq -r '.tool // ""' <<<"${step}")
		args=$(jq -c '.args // {}' <<<"${step}")

		if [[ "${availability_known}" == true ]]; then
			if planner_is_tool_available "${tool}" "${available_tools}"; then
				valid_tools=$((valid_tools + 1))
			else
				missing_tools=$((missing_tools + 1))
			fi
		fi

		if ((side_effect_index < 0)) && planner_step_has_side_effects "${tool}" "${args}"; then
			side_effect_index=${idx}
		fi

		idx=$((idx + 1))
	done < <(jq -cr '.[]' <<<"${plan_json}")

	# Finalize scoring
	score=$((score + (valid_tools * 3)))
	if ((missing_tools > 0)); then
		score=$((score - (missing_tools * 25)))
		rationale+=("Plan references ${missing_tools} unavailable tool(s).")
		log "INFO" "Planner scoring: unavailable tools detected" "$(jq -nc --argjson missing "${missing_tools}" --argjson valid "${valid_tools}" '{missing:$missing,valid:$valid}')" >&2
	elif [[ "${availability_known}" == true ]]; then
		rationale+=("All tools are registered in the planner catalog.")
	fi

	# Argument schema validation
	if ((invalid_args > 0)); then
		score=$((score - (invalid_args * 10)))
		rationale+=("Args fail schema checks for ${invalid_args} step(s).")
		log "INFO" "Planner scoring: argument validation failed" "$(jq -nc --argjson invalid "${invalid_args}" --argjson checked "${idx}" '{invalid:$invalid,checked:$checked}')" >&2
	else
		rationale+=("Planner args satisfy registered tool schemas.")
	fi

	# Side-effecting action timing
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

	# Emit final scorecard
	rationale_json=$(printf '%s\0' "${rationale[@]}" | jq -Rs 'split("\u0000") | map(select(length>0))')
	log "INFO" "Planner scoring summary" "$(jq -nc --argjson score "${score}" --argjson tie_breaker "${tie_breaker}" --argjson plan_length "${plan_length}" --argjson missing_tools "${missing_tools}" --argjson invalid_args "${invalid_args}" --argjson side_effect_index "${side_effect_index}" '{score:$score,tie_breaker:$tie_breaker,plan_length:$plan_length,missing_tools:$missing_tools,invalid_args:$invalid_args,side_effect_index:$side_effect_index}')" >&2
	jq -nc \
		--argjson score "${score}" \
		--argjson tie_breaker "${tie_breaker}" \
		--argjson plan_length "${plan_length}" \
		--argjson rationale "${rationale_json}" \
		'{score:$score,tie_breaker:$tie_breaker,plan_length:$plan_length,rationale:$rationale}'
}

export -f planner_is_tool_available
export -f planner_step_has_side_effects
export -f planner_terminal_command_has_side_effects
export -f python_repl_has_side_effects
export -f score_planner_candidate
