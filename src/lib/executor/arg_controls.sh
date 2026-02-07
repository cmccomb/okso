#!/usr/bin/env bash
# shellcheck shell=bash
#
# Planner argument-control and executor infill helpers.
#
# Usage:
#   source "${BASH_SOURCE[0]%/arg_controls.sh}/arg_controls.sh"
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   Functions return non-zero on validation or execution failures.

EXECUTOR_ARG_CONTROLS_DIR=${EXECUTOR_ARG_CONTROLS_DIR:-$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)}

# shellcheck source=src/lib/core/logging.sh
source "${EXECUTOR_ARG_CONTROLS_DIR}/../core/logging.sh"
# shellcheck source=src/lib/llm/llama_client.sh
source "${EXECUTOR_ARG_CONTROLS_DIR}/../llm/llama_client.sh"
# shellcheck source=src/lib/llm/context_budget.sh
source "${EXECUTOR_ARG_CONTROLS_DIR}/../llm/context_budget.sh"
# shellcheck source=src/lib/llm/templates.sh
source "${EXECUTOR_ARG_CONTROLS_DIR}/../llm/templates.sh"
# shellcheck source=src/lib/executor/history.sh
source "${EXECUTOR_ARG_CONTROLS_DIR}/history.sh"
# shellcheck source=src/tools/registry.sh
source "${EXECUTOR_ARG_CONTROLS_DIR}/../../tools/registry.sh"

normalize_args_json() {
	# Normalizes argument JSON into canonical form.
	# Arguments:
	#   $1 - args JSON string
	# Returns:
	#   Canonical JSON string with sorted keys.
	local args_json normalized
	args_json="$1"

	if [[ -z "${args_json}" ]]; then
		args_json="{}"
	fi

	normalized="$(jq -cS '.' <<<"${args_json}" 2>/dev/null || printf '{}')"
	printf '%s' "${normalized}"
}

build_prompt_safe_history() {
	# Builds a prompt-safe history string for LLM arg fill.
	# Arguments:
	#   $1 - history text (newline-delimited JSON entries)
	# Returns:
	#   Summarized history text (string)
	local history_text summarized
	history_text="$1"

	if [[ -z "${history_text}" ]]; then
		printf '%s' "${history_text}"
		return 0
	fi

	summarized="$(summarize_executor_history "${history_text}")"
	printf '%s' "${summarized}"
}

apply_plan_arg_controls() {
	# Applies planner-provided arg values and infers context-controlled fields from empty seeds.
	# Arguments:
	#   $1 - tool name
	#   $2 - executor args JSON
	#   $3 - planner plan entry JSON (optional)
	#   $4 - user query text (unused; kept for API stability)
	#   $5 - serialized history text (unused; kept for API stability)
	local tool args_json plan_entry_json user_query history_text args_obj plan_args jq_filter fill_marker_json
	tool="$1"
	args_json="$2"
	plan_entry_json="$3"
	user_query="$4"
	history_text="$5"
	fill_marker_json='{"__fill__":true}'

	args_obj="$(jq -ce 'if type=="object" then . else {} end' <<<"${args_json}" 2>/dev/null || printf '{}')"
	plan_args="$(jq -ce '.args // {} | if type=="object" then . else {} end' <<<"${plan_entry_json}" 2>/dev/null || printf '{}')"

	# Merge planner args into executor args while tracking placeholders that must
	# be filled from context and preserving string literals as hint seeds.
	jq_filter=$(
		cat <<'JQ'
$planned as $p
| reduce ($p|to_entries[]) as $item (
    {args:$args, context:[], seeds:{}};
    .args[$item.key] = $item.value
    | if ($item.value == $fill_marker or $item.value == null or $item.value == "") then
        (.context += [$item.key])
      else
        (if ($item.value | type) == "string" then .seeds[$item.key] = $item.value else . end)
      end
  )
| . as $state
| $state.args
| (if ($state.context|length>0) then .+{__context_controlled:$state.context} else . end)
| (if ($state.seeds|length>0) then .+{__context_seeds:$state.seeds} else . end)
JQ
	)

	jq -c -n --argjson args "${args_obj}" --argjson planned "${plan_args}" --argjson fill_marker "${fill_marker_json}" "${jq_filter}" 2>/dev/null
}

fill_missing_args_with_llm() {
	# Fills planner-marked context arguments via a single LLM round-trip when possible.
	# Arguments:
	#   $1 - tool name
	#   $2 - args JSON
	#   $3 - user query
	#   $4 - plan outline
	#   $5 - planner thought
	#   $6 - history text
	#   $7 - JSON array of context-controlled fields
	# Returns:
	#   JSON string with filled args, or original args if LLM unavailable or fails.
	local tool args_json user_query plan_outline planner_thought schema prompt response context_fields_json
	local history_text prompt_raw prompt_safe_history max_completion_tokens
	local had_llama_temperature llama_temperature_backup
	tool="$1"
	args_json="$2"
	user_query="$3"
	plan_outline="$4"
	planner_thought="$5"
	history_text="$6"
	context_fields_json="$7"
	schema="$(jq -c '.' <<<"$(tool_args_schema "${tool}")" 2>/dev/null || printf '{}')"
	max_completion_tokens=256

	if [[ "${LLAMA_AVAILABLE:-false}" != true ]]; then
		log "WARN" "LLM unavailable; context args remain unchanged" "${tool}" || true
		printf '%s' "${args_json}"
		return 0
	fi

	render_executor_prompt() {
		local history_payload rendered
		history_payload="$1"

		if ! rendered="$(render_prompt_template "executor" \
			tool "${tool}" \
			user_query "${user_query}" \
			plan_outline "${plan_outline}" \
			planner_thought "${planner_thought}" \
			args_json "${args_json}" \
			args_schema "${schema}" \
			context_fields "${context_fields_json}" \
			history_text "${history_payload}")"; then
			return 1
		fi

		printf '%s' "${rendered}"
	}

	if ! prompt_raw="$(render_executor_prompt "${history_text}")"; then
		log "WARN" "Failed to render executor prompt" "${tool}" || true
		printf '%s' "${args_json}"
		return 0
	fi

	# Summarize only history, then re-render the full prompt to keep template
	# structure stable after context shortening.
	prompt_safe_history="$(apply_prompt_context_budget "${prompt_raw}" "${history_text}" "${max_completion_tokens}" "executor_history")"

	if ! prompt="$(render_executor_prompt "${prompt_safe_history}")"; then
		log "WARN" "Failed to render executor prompt" "${tool}" || true
		printf '%s' "${args_json}"
		return 0
	fi

	log_pretty "INFO" "prompt" "${prompt}"

	had_llama_temperature=false
	if [[ "${LLAMA_TEMPERATURE+x}" == "x" ]]; then
		had_llama_temperature=true
		llama_temperature_backup="${LLAMA_TEMPERATURE}"
	fi
	# Force deterministic infill and restore caller temperature afterwards.
	LLAMA_TEMPERATURE=0
	export LLAMA_TEMPERATURE

	if ! response="$(llama_infer "${prompt}" "" "${max_completion_tokens}" "${schema}" "${EXECUTOR_MODEL_REPO:-}" "${EXECUTOR_MODEL_FILE:-}")"; then
		if [[ "${had_llama_temperature}" == true ]]; then
			LLAMA_TEMPERATURE="${llama_temperature_backup}"
			export LLAMA_TEMPERATURE
		else
			unset LLAMA_TEMPERATURE
		fi
		log "ERROR" "llama_infer failed during arg fill" "${tool}" || true
		return 1
	fi

	if [[ "${had_llama_temperature}" == true ]]; then
		LLAMA_TEMPERATURE="${llama_temperature_backup}"
		export LLAMA_TEMPERATURE
	else
		unset LLAMA_TEMPERATURE
	fi

	if ! response_json="$(jq -ce 'if type == "object" then . else empty end' <<<"${response}" 2>/dev/null)"; then
		log "ERROR" "Invalid llama response for arg fill" "tool=${tool} response=${response}" || true
		return 1
	fi

	printf '%s' "${response_json}"
	return 0
}

extract_context_controls() {
	# Extracts context metadata and cleaned args from a resolved args JSON blob.
	# Arguments:
	#   $1 - resolved args JSON
	# Returns:
	#   JSON object with keys: args, context_fields, context_seed_lines
	local resolved_json
	resolved_json="$1"

	jq -ce '
                def ensure_array(x): if (x|type) == "array" then x else [] end;
                def ensure_object(x): if (x|type) == "object" then x else {} end;

                {
                        args: (. | del(.__context_controlled) | del(.__context_seeds)),
                        context_fields: ensure_array(.__context_controlled),
                        context_seed_lines: (ensure_object(.__context_seeds) | to_entries | map("\(.key): \(.value)"))
                }
        ' <<<"${resolved_json}"
}

infer_missing_required_context_fields() {
	# Infers missing required fields from tool schema when planner omitted them.
	# Arguments:
	#   $1 - tool name
	#   $2 - args JSON
	# Returns:
	#   JSON array of field names that should be LLM-filled.
	local tool resolved_args schema
	tool="$1"
	resolved_args="$2"
	if [[ -z "${resolved_args}" ]]; then
		resolved_args='{}'
	fi
	schema="$(jq -c '.' <<<"$(tool_args_schema "${tool}")" 2>/dev/null || printf '{}')"

	jq -cn \
		--argjson args "${resolved_args}" \
		--argjson schema "${schema}" '
                def is_missing(v):
                        (v == null)
                        or (v == "")
                        or ((v | type) == "object" and (v.__fill__ // false) == true);

                def missing_from_required(req; a):
                        [ req[] | select(type == "string" and length > 0) | select(is_missing(a[.])) ];

                def select_missing_union_fields(branches; a):
                        if (branches | type) != "array" then
                                []
                        else
                                (branches
                                        | map(select(type == "object"))
                                        | map({required: (.required // [])})
                                        | map(select((.required | type) == "array" and (.required | length) > 0))
                                        | map({missing: missing_from_required(.required; a)})
                                ) as $prepared
                                | if ($prepared | length) == 0 then
                                        []
                                  elif any($prepared[]; (.missing | length) == 0) then
                                        # At least one union branch is already satisfied, so no union-driven infill is required.
                                        []
                                  else
                                        # Otherwise pick the branch with the fewest missing fields to minimize speculative filling.
                                        ($prepared | sort_by(.missing | length) | .[0].missing)
                                  end
                        end;

                (
                        missing_from_required(($schema.required // []); $args)
                        + select_missing_union_fields(($schema.anyOf // []); $args)
                        + select_missing_union_fields(($schema.oneOf // []); $args)
                )
                | map(select(type == "string" and length > 0))
                | unique
        ' 2>/dev/null || printf '[]'
}

resolve_action_args() {
	# Applies planner controls, fills context fields, and normalizes the final JSON.
	# Arguments:
	#   $1 - tool name
	#   $2 - args JSON
	#   $3 - planner plan entry JSON
	#   $4 - user query
	#   $5 - serialized history text
	#   $6 - plan outline
	#   $7 - planner thought
	local tool args_json plan_entry_json user_query history_text plan_outline planner_thought
	local resolved_args context_fields_json context_seed_lines history_for_prompt context_metadata inferred_context_fields_json
	tool="$1"
	args_json="$2"
	plan_entry_json="$3"
	user_query="$4"
	history_text="$5"
	plan_outline="$6"
	planner_thought="$7"

	resolved_args="$(apply_plan_arg_controls "${tool}" "${args_json}" "${plan_entry_json}" "${user_query}" "${history_text}")"

	if ! context_metadata="$(extract_context_controls "${resolved_args}")"; then
		printf 'Invalid args JSON after planner controls\n' >&2
		return 1
	fi

	context_fields_json="$(jq -c '.context_fields' <<<"${context_metadata}")"
	context_seed_lines="$(jq -r '.context_seed_lines[]?' <<<"${context_metadata}")"
	resolved_args="$(jq -c '.args' <<<"${context_metadata}")"

	inferred_context_fields_json="$(infer_missing_required_context_fields "${tool}" "${resolved_args}")"
	# Union explicit planner placeholders with inferred schema-required gaps.
	context_fields_json="$(
		jq -cn \
			--argjson explicit "${context_fields_json}" \
			--argjson inferred "${inferred_context_fields_json}" \
			'[($explicit // []), ($inferred // [])] | add | map(select(type == "string" and length > 0)) | unique'
	)"
	if [[ "${context_fields_json}" == "[]" ]]; then
		normalize_args_json "${resolved_args}"
		return 0
	fi

	history_for_prompt="${history_text}"
	history_for_prompt="$(build_prompt_safe_history "${history_for_prompt}")"
	if [[ -n "${context_seed_lines}" ]]; then
		# Seeds are appended in plain text so the model can reuse planner literals during fill.
		history_for_prompt+=$'\n'
		history_for_prompt+="Context arg seeds:"
		history_for_prompt+=$'\n'
		history_for_prompt+="${context_seed_lines}"
	fi

	if ! resolved_args="$(fill_missing_args_with_llm "${tool}" "${resolved_args}" "${user_query}" "${plan_outline}" "${planner_thought}" "${history_for_prompt}" "${context_fields_json}")"; then
		printf 'Context argument infill failed\n' >&2
		return 1
	fi

	normalize_args_json "${resolved_args}"
}

export -f normalize_args_json
export -f build_prompt_safe_history
export -f apply_plan_arg_controls
export -f fill_missing_args_with_llm
export -f extract_context_controls
export -f infer_missing_required_context_fields
export -f resolve_action_args
