#!/usr/bin/env bash
# shellcheck shell=bash
#
# State and history helpers for the executor loop.
#
# Usage:
#   source "${BASH_SOURCE[0]%/history.sh}/history.sh"
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Environment variables:
#   EXECUTOR_HISTORY_SNIPPET_LIMIT (int): maximum characters to preserve for web_fetch body_markdown summaries (default: 240).
#
# Exit codes:
#   Functions return non-zero on state failures.

EXECUTOR_LIB_DIR=${EXECUTOR_LIB_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)}

# shellcheck source=src/lib/core/logging.sh
source "${EXECUTOR_LIB_DIR}/../core/logging.sh"
# shellcheck source=src/lib/core/json_state.sh
source "${EXECUTOR_LIB_DIR}/../core/json_state.sh"
# shellcheck source=src/lib/cli/output.sh
source "${EXECUTOR_LIB_DIR}/../cli/output.sh"
# shellcheck source=src/lib/validation/validation.sh
source "${EXECUTOR_LIB_DIR}/../validation/validation.sh"

summarize_executor_history() {
	# Summarizes history entries for prompt-safe reuse.
	# Arguments:
	#   $1 - history text (newline-delimited JSON entries)
	# Returns:
	#   Summarized history text (newline-delimited JSON entries)
	# Notes:
	#   For web_fetch observations that use the enriched wrapper format
	#   ({output: "<json>", exit_code: <int>, error: "<string>"}), the
	#   output payload is parsed as JSON and summarized like a normal
	#   web_fetch observation. If the output JSON cannot be parsed,
	#   the original history line is preserved to avoid data loss.
	local history_text limit line summarized_line
	local -a summarized_lines=()
	history_text="$1"
	limit=${EXECUTOR_HISTORY_SNIPPET_LIMIT:-240}

	if [[ -z "${history_text}" ]]; then
		printf '%s' "${history_text}"
		return 0
	fi

	while IFS= read -r line || [[ -n "${line}" ]]; do
		if [[ -z "${line}" ]]; then
			summarized_lines+=("")
			continue
		fi

		if ! summarized_line=$(jq -c --argjson limit "${limit}" '
                        def normalize_observation:
                                if (type == "object" and has("output") and has("exit_code")) then
                                        try (.output | fromjson) catch error("invalid_observation_json")
                                else
                                        .
                                end;
                        if type != "object" then
                                .
                        elif (.action.tool? // "") != "web_fetch" then
                                .
                        elif (.observation | type) != "object" then
                                .
                        else
                                (.observation | normalize_observation) as $obs
                                | if ($obs | type) != "object" then
                                        .
                                else
                                        .observation = ($obs | {
                                                url: .url,
                                                final_url: .final_url,
                                                status: .status,
                                                content_type: .content_type,
                                                anchor_query: .anchor_query,
                                                anchor_match: .anchor_match,
                                                body_encoding: .body_encoding,
                                                body_snippet: .body_snippet,
                                                body_markdown: (
                                                        if (.body_snippet // "") != "" then
                                                                .body_snippet
                                                        elif (.body_markdown // "") != "" then
                                                                (.body_markdown | tostring | .[0:$limit])
                                                        else
                                                                null
                                                        end
                                                ),
                                                bytes: .bytes,
                                                truncated: .truncated
                                        })
                                end
                        end
                ' <<<"${line}" 2>/dev/null); then
			summarized_lines+=("${line}")
			continue
		fi

		summarized_lines+=("${summarized_line}")
	done <<<"${history_text}"

	printf '%s\n' "${summarized_lines[@]}"
}

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

	# Initialize the JSON state document
	json_state_set_document "${state_prefix}" "$(jq -c -n \
		--arg user_query "$2" \
		--arg allowed_tools "$3" \
		--arg plan_entries "$4" \
		--arg plan_outline "$5" \
		'{
                        user_query: $user_query,
                        allowed_tools: $allowed_tools,
                        plan_entries: $plan_entries,
                        plan_outline: $plan_outline,
                        history: [],
                        step: 0,
                        plan_index: 0,
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

	# Append to history array in state
	json_state_append_history "$1" "${entry}"
}

state_get_history_lines() {
	# Retrieves history as a newline-delimited string.
	# Arguments:
	#   $1 - state prefix (string)
	# Returns:
	#   Newline-delimited string of history entries.
	local state_prefix history_raw
	state_prefix="$1"

	# Fetch history array from state
	history_raw="$(json_state_get_key "${state_prefix}" "history")"

	# Format history as newline-delimited string
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
	local tool thought args_json observation step_index entry observation_json
	state_name="$1"
	tool="$2"
	thought="$3"
	args_json="$4"
	observation="$5"
	step_index="$6"

	# Normalize args JSON
	if [[ -z "${args_json}" ]]; then
		args_json="{}"
	fi

	# Ensure args_json is valid JSON
	args_json="$(jq -cS '.' <<<"${args_json}" 2>/dev/null || printf '{}')"

	# Attempt to parse observation as JSON
	if observation_json=$(jq -c '.' <<<"${observation}" 2>/dev/null); then
		observation_json_value="${observation_json}"
	else
		observation_json_value="null"
	fi

	# Build history entry
	entry=$(
		jq -c -n \
			--arg step "${step_index}" \
			--arg thought "${thought}" \
			--arg tool "${tool}" \
			--argjson args "${args_json}" \
			--arg observation_raw "${observation}" \
			--argjson observation_json "${observation_json_value}" \
			'{
                  step: ($step | tonumber // 0),
                  thought: $thought,
                  action: {tool: $tool, args: $args},
                  observation: (if ($observation_json | type) == "null" then $observation_raw else $observation_json end)
                }'
	) || return 1

	# Append entry to history and log
	record_history "${state_name}" "${entry}"
	log "INFO" "Recorded tool execution" "$(printf 'step=%s tool=%s' "${step_index}" "${tool}")"
}

finalize_executor_result() {
	# Finalizes and emits the executor run result.
	# Arguments:
	#   $1 - state prefix
	local state_name observation final_answer_action needs_replanning user_feedback
	local final_answer
	state_name="$1"

	# Check if replanning is needed due to user feedback
	needs_replanning="$(json_state_get_key "${state_name}" "needs_replanning" 2>/dev/null || echo "")"

	# If replanning is needed, check for user feedback
	if [[ "${needs_replanning}" == "true" ]]; then
		user_feedback="$(json_state_get_document "${state_name}" | jq -r '.user_feedback // empty' 2>/dev/null || echo "")"
		if [[ -n "${user_feedback}" ]]; then
			log "INFO" "Replanning with user feedback" "feedback=${user_feedback}"
			jq -nc --arg feedback "${user_feedback}" '{status: "feedback_received", feedback: $feedback}'
			return 0
		fi
	fi

	# Determine final answer from state
	observation="$(json_state_get_key "${state_name}" "final_answer" 2>/dev/null || echo "")"
	final_answer_action="$(json_state_get_key "${state_name}" "final_answer_action" 2>/dev/null || echo "")"

	# Prioritize observation if valid
	if [[ -n "${observation}" ]]; then
		if jq -e '.output != null and .exit_code != null' <<<"${observation}" >/dev/null 2>&1; then
			final_answer="$(jq -r '.output' <<<"${observation}")"
		else
			final_answer="${observation}"
		fi
	elif [[ -n "${final_answer_action}" ]]; then
		final_answer="${final_answer_action}"
	else
		final_answer=""
	fi

	# Store final answer back into state
	json_state_set_key "${state_name}" "final_answer" "${final_answer}"

	# Evaluate final answer if enabled
	if [[ "${ENABLE_ANSWER_VALIDATION:-true}" == "true" ]]; then
		evaluate_and_optionally_replan "${state_name}" "${final_answer}"
		return $?
	fi

	# Emit final answer and summary
	log_pretty "INFO" "Final answer" "${final_answer}"
	if [[ -z "$(format_tool_history "$(state_get_history_lines "${state_name}")")" ]]; then
		log "INFO" "Execution summary" "No tool runs"
	else
		log_pretty "INFO" "Execution summary" "$(format_tool_history "$(state_get_history_lines "${state_name}")")"
	fi

	# Emit boxed summary
	emit_boxed_summary \
		"$(json_state_get_key "${state_name}" "user_query")" \
		"$(json_state_get_key "${state_name}" "plan_outline")" \
		"$(state_get_history_lines "${state_name}")" \
		"${final_answer}"
}

executor_replan_with_feedback() {
	# Triggers a planner rerun using validator feedback and executes the new plan.
	# Arguments:
	#   $1 - executor state prefix (string)
	#   $2 - feedback text for the planner (string)
	# Returns:
	#   Exit status from the downstream executor loop when replanning succeeds;
	#   non-zero when replanning cannot be attempted.

	local state_name feedback_text user_query plan_response plan_outline plan_entries allowed_tools
	state_name="$1"
	feedback_text="$2"

	# Prevent infinite replanning loops
	if [[ "${VALIDATION_REPLAN_ATTEMPTED:-false}" == "true" ]]; then
		log "WARN" "Skipping evaluation-driven replanning; attempt already made" || true
		return 1
	fi
	VALIDATION_REPLAN_ATTEMPTED=true

	# Save the user query to the state
	user_query="$(json_state_get_key "${state_name}" "user_query")"

	# Mark state as needing replanning with feedback
	json_state_set_key "${state_name}" "needs_replanning" "true" || true
	if [[ -n "${feedback_text}" ]]; then
		json_state_set_key "${state_name}" "user_feedback" "${feedback_text}" || true
	fi
	log "INFO" "Replanning after failed evaluation" "${feedback_text}" || true

	# Set feedback context for planner
	local previous_feedback_context feedback_context_in_env
	feedback_context_in_env=false
	if printenv PLANNER_FEEDBACK_CONTEXT >/dev/null 2>&1; then
		feedback_context_in_env=true
	fi
	previous_feedback_context="${PLANNER_FEEDBACK_CONTEXT:-}"
	PLANNER_FEEDBACK_CONTEXT="${feedback_text}"
	export PLANNER_FEEDBACK_CONTEXT

	# Generate new plan
	if ! plan_response="$(generate_planner_response "${user_query}")"; then
		log "ERROR" "Evaluation-driven replanning failed" "plan_regeneration_error" || true
		if [[ "${feedback_context_in_env}" == true ]]; then
			PLANNER_FEEDBACK_CONTEXT="${previous_feedback_context}"
			export PLANNER_FEEDBACK_CONTEXT
		else
			unset PLANNER_FEEDBACK_CONTEXT
		fi
		return 1
	fi

	# Restore previous feedback context
	if [[ "${feedback_context_in_env}" == true ]]; then
		PLANNER_FEEDBACK_CONTEXT="${previous_feedback_context}"
		export PLANNER_FEEDBACK_CONTEXT
	else
		unset PLANNER_FEEDBACK_CONTEXT
	fi

	# Extract plan components
	if ! plan_outline="$(plan_json_to_outline "${plan_response}")"; then
		log "ERROR" "Unable to derive plan outline during replanning" || true
		return 1
	fi

	if ! allowed_tools="$(derive_allowed_tools_from_plan "${plan_response}")"; then
		log "ERROR" "Unable to derive tools during replanning" || true
		return 1
	fi

	if ! plan_entries="$(plan_json_to_entries "${plan_response}")"; then
		log "ERROR" "Unable to normalize plan entries during replanning" || true
		return 1
	fi

	# Execute new plan
	executor_loop "${user_query}" "${allowed_tools}" "${plan_entries}" "${plan_outline}"
}

evaluate_and_optionally_replan() {
	# Args:
	#   $1 - state prefix
	#   $2 - final answer text
	local state_name final_answer user_query history_text
	local evaluation_json evaluation_type reasoning output feedback_text errexit_was_set
	local history_pretty
	state_name="$1"
	final_answer="$2"

	# Fetch user query and history
	user_query="$(json_state_get_key "${state_name}" "user_query")"
	history_text="$(state_get_history_lines "${state_name}")"

	# Run final answer evaluation
	log "INFO" "Running final answer evaluation" || true

	# Always capture output; keep exit code separately.
	errexit_was_set=false
	if [[ $- == *e* ]]; then
		errexit_was_set=true
		set +e
	fi

	evaluation_json="$(evaluate_final_answer_against_query "${user_query}" "${final_answer}" "${history_text}")"

	if [[ "${errexit_was_set}" == true ]]; then
		set -e
	fi

	if [[ -z "${evaluation_json}" ]]; then
		log "WARN" "Evaluator returned empty response; outputting answer as-is" || true
	else
		evaluation_type="$(jq -r '.evaluation_type // empty' <<<"${evaluation_json}" 2>/dev/null)"
		reasoning="$(jq -r '.reasoning // empty' <<<"${evaluation_json}" 2>/dev/null)"
		output="$(jq -r '.output // empty' <<<"${evaluation_json}" 2>/dev/null)"

		log_pretty "INFO" "evaluation_result" "${evaluation_json}" || true

		case "${evaluation_type}" in
		PASS | REPHRASE)
			if [[ -n "${output}" ]]; then
				final_answer="${output}"
				json_state_set_key "${state_name}" "final_answer" "${final_answer}"
			fi
			log "INFO" "Final answer accepted by evaluator" || true
			;;
		REPLAN)
			log "WARN" "Evaluator requested replanning" || true

			json_state_set_key "${state_name}" "answer_validation_failed" "true" || true
			if [[ -n "${reasoning}" ]]; then
				json_state_set_key "${state_name}" "validation_failure_reason" "${reasoning}" || true
				log_pretty "WARN" "validation_failure_reason" "${reasoning}" || true
			else
				json_state_set_key "${state_name}" "validation_failure_reason" "Unknown reason" || true
			fi

			feedback_text="${output:-${reasoning:-Evaluator requested replanning without providing details.}}"
			if executor_replan_with_feedback "${state_name}" "${feedback_text}"; then
				return 0
			fi
			log "WARN" "Continuing without replanning after evaluator request" || true
			;;
		*)
			log "WARN" "Evaluator returned unexpected schema; outputting answer as-is" || true
			;;
		esac
	fi

	# Emit final answer regardless.
	history_pretty="$(format_tool_history "${history_text}")"
	log_pretty "INFO" "Final answer" "${final_answer}"

	if [[ -z "${history_pretty}" ]]; then
		log "INFO" "Execution summary" "No tool runs"
	else
		log_pretty "INFO" "Execution summary" "${history_pretty}"
	fi

	emit_boxed_summary \
		"${user_query}" \
		"$(json_state_get_key "${state_name}" "plan_outline")" \
		"${history_text}" \
		"${final_answer}"
}

export -f evaluate_and_optionally_replan
