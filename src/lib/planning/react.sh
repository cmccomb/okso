#!/usr/bin/env bash
# shellcheck shell=bash
#
# ReAct execution loop for the okso assistant.
#
# Usage:
#   source "${BASH_SOURCE[0]%/react.sh}/react.sh"
#
# Environment variables:
#   MAX_STEPS (int): maximum number of ReAct turns; default: 6.
#   CANONICAL_TEXT_ARG_KEY (string): key for single-string tool arguments; default: "input".
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   None directly; functions return status of operations.

PLANNING_REACT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./context_budget.sh disable=SC1091
source "${PLANNING_REACT_DIR}/context_budget.sh"
#

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
                        last_action: null
                }')"
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

format_tool_args() {
	# Formats tool arguments into a JSON object.
	# Arguments:
	#   $1 - tool name (string)
	#   $2 - primary payload string (string)
	# Returns:
	#   A JSON string representing the tool arguments.
	local tool payload text_key
	tool="$1"
	payload="$2"
	text_key="${CANONICAL_TEXT_ARG_KEY:-input}"
	case "${tool}" in
	terminal)
		read -r -a terminal_tokens <<<"${payload}"
		if ((${#terminal_tokens[@]} == 0)); then
			terminal_tokens=("status")
		fi
		jq -nc --arg command "${terminal_tokens[0]}" --argjson args "$(printf '%s\n' "${terminal_tokens[@]:1}" | jq -Rcs 'split("\n") | map(select(length > 0))')" '{command:$command,args:$args}'
		;;
	python_repl)
		jq -nc --arg code "${payload}" '{code:$code}'
		;;
	notes_search | calendar_search | mail_search)
		jq -nc --arg key "${text_key}" --arg value "${payload}" '{($key):$value}'
		;;
	web_search)
		jq -nc --arg query "${payload}" '{query:$query}'
		;;
	clipboard_copy)
		jq -nc --arg text "${payload}" '{text:$text}'
		;;
	clipboard_paste | notes_list | reminders_list | calendar_list | mail_list_inbox | mail_list_unread)
		jq -nc '{}'
		;;
	notes_create | notes_append)
		local title body
		title=${payload%%$'\n'*}
		body=${payload#"${title}"}
		body=${body#$'\n'}
		jq -nc --arg title "${title}" --arg body "${body}" '{title:$title,body:$body}'
		;;
	notes_read)
		jq -nc --arg title "${payload}" '{title:$title}'
		;;
	reminders_create)
		local title notes time
		title=${payload%%$'\n'*}
		notes=${payload#"${title}"}
		notes=${notes#$'\n'}
		time=""
		jq -nc --arg title "${title}" --arg time "${time}" --arg notes "${notes}" '{title:$title,time:$time,notes:$notes}'
		;;
	reminders_complete)
		jq -nc --arg title "${payload}" '{title:$title}'
		;;
	calendar_create)
		local title start_time location
		title=${payload%%$'\n'*}
		start_time=${payload#"${title}"}
		start_time=${start_time#$'\n'}
		location=${start_time#*$'\n'}
		start_time=${start_time%%$'\n'*}
		jq -nc --arg title "${title}" --arg start_time "${start_time}" --arg location "${location}" '{title:$title,start_time:$start_time,location:$location}'
		;;
	mail_draft | mail_send)
		jq -nc --arg envelope "${payload}" '{envelope:$envelope}'
		;;
	applescript)
		jq -nc --arg key "${text_key}" --arg value "${payload}" '{($key):$value}'
		;;
	final_answer)
		jq -nc --arg key "${text_key}" --arg value "${payload}" '{($key):$value}'
		;;
	*)
		jq -nc --arg key "${text_key}" --arg value "${payload}" '{($key):$value}'
		;;
	esac
}

extract_tool_query() {
	# Arguments:
	#   $1 - tool name
	#   $2 - args JSON
	# Returns a human-readable summary derived from structured args.
	local tool args_json text_key
	tool="$1"
	args_json="$2"
	text_key="${CANONICAL_TEXT_ARG_KEY:-input}"
	case "${tool}" in
	terminal)
		jq -r '(.command // "") as $cmd | ($cmd + " " + ((.args // []) | map(tostring) | join(" ")))|rtrimstr(" ")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	notes_create | notes_append)
		jq -r '[(.title // ""), (.body // "")] | map(select(length>0)) | join("\n")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	reminders_create)
		jq -r '[(.title // ""), (.time // ""), (.notes // "")] | map(select(length>0)) | join("\n")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	notes_read | reminders_complete)
		jq -r '(.title // "")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	calendar_create)
		jq -r '[(.title // ""), (.start_time // ""), (.location // "")] | map(select(length>0)) | join("\n")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	python_repl)
		jq -r '(.code // "")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	notes_search | calendar_search | mail_search)
		jq -r --arg key "${text_key}" '.[$key] // ""' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	web_search)
		jq -r '.query // ""' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	clipboard_copy)
		jq -r '(.text // "")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	mail_draft | mail_send)
		jq -r '(.envelope // "")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	applescript)
		jq -r --arg key "${text_key}" '.[$key] // ""' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	final_answer)
		jq -r --arg key "${text_key}" '.[$key] // ""' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	clipboard_paste | notes_list | reminders_list | calendar_list | mail_list_inbox | mail_list_unread)
		printf ''
		;;
	*)
		jq -r --arg key "${text_key}" '.[$key] // .query // ""' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	esac
}

format_action_context() {
	# Arguments:
	#   $1 - thought text
	#   $2 - tool name
	#   $3 - args JSON
	local thought tool args_json args_pretty
	thought="$1"
	tool="$2"
	args_json="$3"
	args_pretty="$(jq -c '.' <<<"${args_json}" 2>/dev/null || printf '%s' "${args_json}")"
	printf 'Thought: %s\nTool: %s\nArgs: %s' "${thought}" "${tool}" "${args_pretty}"
}

build_react_action_schema() {
	# Arguments:
	#   $1 - newline-delimited allowed tools (optional)
	local allowed_tools registry_json
	allowed_tools="$1"

	if [[ -z "$(tool_names)" ]] && declare -F initialize_tools >/dev/null 2>&1; then
		initialize_tools >/dev/null 2>&1 || true
	fi
	registry_json="$(tool_registry_json)"

	python3 - "${allowed_tools}" "${registry_json}" "${CANONICAL_TEXT_ARG_KEY:-input}" <<'PY'
import json
import sys
import tempfile

allowed_raw = sys.argv[1]
registry = json.loads(sys.argv[2] or "{}")
text_key = sys.argv[3] if len(sys.argv) > 3 else "input"

fallback_schema = {
    "type": "object",
    "properties": {text_key: {"type": "string"}},
    "additionalProperties": {"type": "string"},
}

all_names = registry.get("names", [])
registry_map = registry.get("registry", {})

if allowed_raw.strip():
    allowed = [line.strip() for line in allowed_raw.splitlines() if line.strip()]
else:
    allowed = all_names

args_by_tool = {}
tool_enum = []

for name in allowed:
    info = registry_map.get(name, {})
    schema = info.get("args_schema") if isinstance(info, dict) else None
    has_defined_schema = isinstance(schema, dict)
    if not has_defined_schema:
        schema = fallback_schema

    normalized = {"type": "object"}
    normalized.update(schema)
    if has_defined_schema:
        normalized.setdefault("additionalProperties", False)
    else:
        normalized.setdefault("additionalProperties", {"type": "string"})

    args_by_tool[name] = normalized
    tool_enum.append(name)

if not tool_enum:
    sys.stderr.write("No tools available for react schema\n")
    sys.exit(1)

schema_doc = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "title": "ReactAction",
    "description": "ReAct tool call constrained to the provided allowed tools.",
    "type": "object",
    "additionalProperties": False,
    "required": ["thought", "tool", "args"],
    "properties": {
        "thought": {"type": "string", "minLength": 1},
        "tool": {"type": "string", "enum": tool_enum},
        "args": {"type": "object"},
    },
    "$defs": {"args_by_tool": args_by_tool},
    "oneOf": [
        {
            "properties": {
                "tool": {"const": name},
                "args": {"$ref": f"#/$defs/args_by_tool/{name}"},
            },
            "required": ["tool", "args"],
        }
        for name in tool_enum
    ],
}

tmp_file = tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".schema.json", encoding="utf-8")
json.dump(schema_doc, tmp_file)
tmp_file.close()
print(tmp_file.name)
PY
}

validate_react_action() {
	# Arguments:
	#   $1 - raw action JSON string
	#   $2 - schema path
	local raw_action schema_path action_json schema_json allowed_tools tool tool_schema properties_json additional_properties
	local err_log required_args thought_trimmed
	raw_action="$1"
	schema_path="$2"

	err_log=$(mktemp)

	if ! action_json=$(jq -ce '.' <<<"${raw_action}" 2>"${err_log}"); then
		printf 'Invalid JSON: %s\n' "$(<"${err_log}")" >&2
		rm -f "${err_log}"
		return 1
	fi

	if ! schema_json=$(jq -ce '.' "${schema_path}" 2>"${err_log}"); then
		printf 'Schema load failed: %s\n' "$(<"${err_log}")" >&2
		rm -f "${err_log}"
		return 1
	fi

	rm -f "${err_log}"

	for key in thought tool args; do
		if ! jq -e --arg key "${key}" 'has($key)' <<<"${action_json}" >/dev/null; then
			printf 'Missing field: %s\n' "${key}" >&2
			return 1
		fi
	done

	local unexpected
	unexpected=$(jq -er 'keys_unsorted | map(select(. != "thought" and . != "tool" and . != "args")) | first? // empty' <<<"${action_json}" 2>/dev/null || true)
	if [[ -n "${unexpected}" ]]; then
		printf 'Unexpected field: %s\n' "${unexpected}" >&2
		return 1
	fi

	if ! jq -e '.thought | type == "string" and (gsub("^\\s+|\\s+$"; "") | length > 0)' <<<"${action_json}" >/dev/null; then
		printf 'thought must be a non-empty string\n' >&2
		return 1
	fi

	if ! jq -e '.tool | type == "string"' <<<"${action_json}" >/dev/null; then
		printf 'tool must be a string\n' >&2
		return 1
	fi

	tool=$(jq -r '.tool' <<<"${action_json}")
	allowed_tools=$(jq -cr '.properties.tool.enum // []' <<<"${schema_json}")
	if ! jq -e --arg tool "${tool}" --argjson allowed "${allowed_tools}" '$allowed | index($tool)' <<<"null" >/dev/null; then
		printf 'Unsupported tool: %s\n' "${tool}" >&2
		return 1
	fi

	if ! jq -e '.args | type == "object"' <<<"${action_json}" >/dev/null; then
		printf 'args must be an object\n' >&2
		return 1
	fi

	tool_schema=$(jq -c --arg tool "${tool}" '."$defs".args_by_tool[$tool]' <<<"${schema_json}")
	if [[ -z "${tool_schema}" || "${tool_schema}" == "null" ]]; then
		printf 'No schema for tool: %s\n' "${tool}" >&2
		return 1
	fi

	properties_json=$(jq -c 'if (.properties | type == "object") then .properties else {} end' <<<"${tool_schema}")
	required_args=$(jq -r '(.required // [])[]?' <<<"${tool_schema}")
	additional_properties=$(jq -c 'if .additionalProperties == null then false else .additionalProperties end' <<<"${tool_schema}")

	local required
	for required in ${required_args}; do
		if ! jq -e --arg key "${required}" '.args | has($key)' <<<"${action_json}" >/dev/null; then
			printf 'Missing arg: %s\n' "${required}" >&2
			return 1
		fi
	done

	_react_enforce_arg_type() {
		# Validates an argument value against a schema fragment using jq types.
		# Arguments:
		#   $1 - argument key (string)
		#   $2 - argument JSON value (string)
		#   $3 - schema JSON string
		local arg_key value_json schema_fragment expected_type min_length item_type enum_values const_value
		arg_key="$1"
		value_json="$2"
		schema_fragment="$3"

		expected_type=$(jq -r '.type // empty' <<<"${schema_fragment}")
		if [[ -z "${expected_type}" ]]; then
			return 0
		fi

		case "${expected_type}" in
		string)
			enum_values=$(jq -c '.enum // empty' <<<"${schema_fragment}")
			const_value=$(jq -c '.const // empty' <<<"${schema_fragment}")
			if ! jq -e 'type == "string"' <<<"${value_json}" >/dev/null; then
				printf 'Arg %s must be a string\n' "${arg_key}" >&2
				return 1
			fi
			min_length=$(jq -r '.minLength // 0' <<<"${schema_fragment}")
			if [[ "${min_length}" -gt 0 ]] && [[ -z "$(jq -r 'gsub("^\\s+|\\s+$"; "")' <<<"${value_json}")" ]]; then
				printf 'Arg %s cannot be empty\n' "${arg_key}" >&2
				return 1
			fi
			if [[ -n "${const_value}" && "${const_value}" != "null" ]]; then
				if ! jq -e --argjson const "${const_value}" --argjson val "${value_json}" '$const == $val' <<<"null" >/dev/null; then
					printf 'Arg %s must equal %s\n' "${arg_key}" "${const_value}" >&2
					return 1
				fi
			fi
			if [[ -n "${enum_values}" && "${enum_values}" != "null" ]]; then
				if ! jq -e --argjson enum "${enum_values}" --argjson val "${value_json}" '$enum | index($val)' <<<"null" >/dev/null; then
					printf 'Arg %s must be one of: %s\n' "${arg_key}" "${enum_values}" >&2
					return 1
				fi
			fi
			;;
		object)
			if ! jq -e 'type == "object"' <<<"${value_json}" >/dev/null; then
				printf 'Arg %s must be a object\n' "${arg_key}" >&2
				return 1
			fi
			;;
		array)
			if ! jq -e 'type == "array"' <<<"${value_json}" >/dev/null; then
				printf 'Arg %s must be a array\n' "${arg_key}" >&2
				return 1
			fi
			item_type=$(jq -r '.items.type // empty' <<<"${schema_fragment}")
			if [[ "${item_type}" == "string" ]] && ! jq -e 'all(.[]?; type == "string")' <<<"${value_json}" >/dev/null; then
				printf 'Arg %s items must be strings\n' "${arg_key}" >&2
				return 1
			fi
			;;
		boolean)
			if ! jq -e 'type == "boolean"' <<<"${value_json}" >/dev/null; then
				printf 'Arg %s must be a boolean\n' "${arg_key}" >&2
				return 1
			fi
			;;
		number)
			if ! jq -e 'type == "number"' <<<"${value_json}" >/dev/null; then
				printf 'Arg %s must be a number\n' "${arg_key}" >&2
				return 1
			fi
			;;
		integer)
			if ! jq -e '(type == "number") and (.|floor == .)' <<<"${value_json}" >/dev/null; then
				printf 'Arg %s must be a integer\n' "${arg_key}" >&2
				return 1
			fi
			;;
		esac

		return 0
	}

	local arg_key arg_value prop_schema
	for arg_key in $(jq -r '.args | keys_unsorted[]' <<<"${action_json}"); do
		arg_value=$(jq -c --arg key "${arg_key}" '.args[$key]' <<<"${action_json}")
		prop_schema=$(jq -c --arg key "${arg_key}" --argjson props "${properties_json}" '$props[$key]' <<<"null")

		if [[ -n "${prop_schema}" && "${prop_schema}" != "null" ]]; then
			if ! _react_enforce_arg_type "${arg_key}" "${arg_value}" "${prop_schema}"; then
				return 1
			fi
			continue
		fi

		if [[ "${additional_properties}" == "false" ]]; then
			printf 'Unexpected arg: %s\n' "${arg_key}" >&2
			return 1
		fi

		if [[ "${additional_properties}" != "false" && "${additional_properties}" != "null" ]]; then
			if ! _react_enforce_arg_type "${arg_key}" "${arg_value}" "${additional_properties}"; then
				return 1
			fi
		fi
	done

	thought_trimmed=$(jq -r '.thought | gsub("^\\s+|\\s+$"; "")' <<<"${action_json}")

	jq -c --arg thought "${thought_trimmed}" '.thought = $thought' <<<"${action_json}"
}

select_next_action() {
	# Arguments:
	#   $1 - state prefix
	#   $2 - (optional) name of variable to receive JSON action output
	local state_name output_name react_prompt plan_index planned_entry tool query next_action_payload allowed_tool_descriptions allowed_tool_lines args_json allowed_tools react_schema_path react_schema_text invoke_llama thought plan_step_guidance planned_thought planned_args_json
	state_name="$1"
	output_name="${2:-}"

	plan_index="$(state_get "${state_name}" "plan_index")"
	plan_index=${plan_index:-0}
	planned_entry=$(printf '%s\n' "$(state_get "${state_name}" "plan_entries")" | sed -n "$((plan_index + 1))p")
	tool=""
	planned_thought="Following planned step"
	planned_args_json="{}"
	local plan_step_available=false
	if [[ -n "${planned_entry}" ]]; then
		tool="$(printf '%s' "${planned_entry}" | jq -r '.tool // empty' 2>/dev/null || printf '')"
		planned_thought="$(printf '%s' "${planned_entry}" | jq -r '.thought // "Following planned step"' 2>/dev/null || printf '')"
		planned_args_json="$(printf '%s' "${planned_entry}" | jq -c '.args // {}' 2>/dev/null || printf '{}')"
		plan_step_available=true

		plan_step_guidance="$(
			jq -rn \
				--arg step "$((plan_index + 1))" \
				--arg tool "${tool:-}" \
				--arg thought "${planned_thought}" \
				--argjson args "${planned_args_json}" \
				'"Step \($step) suggested by the planner:\n- tool: \($tool // "(unspecified)")\n- thought: \($thought // "")\n- args: \($args|@json)"'
		)"
	else
		plan_step_guidance="Planner provided no additional steps; choose the best next action."
	fi

	invoke_llama=false
	if [[ "${USE_REACT_LLAMA:-false}" == true && "${LLAMA_AVAILABLE}" == true ]]; then
		invoke_llama=true
	fi
	if [[ "${tool}" == "react_fallback" && "${LLAMA_AVAILABLE}" == true ]]; then
		invoke_llama=true
	fi

	allowed_tools="$(state_get "${state_name}" "allowed_tools")"
	if [[ -z "${allowed_tools}" ]]; then
		allowed_tools="$(tool_names)"
	fi

	if [[ "${tool}" == "react_fallback" ]]; then
		allowed_tools="$(tool_names)"
	fi

	if [[ -n "${allowed_tools}" ]] && ! grep -Fxq "final_answer" <<<"${allowed_tools}"; then
		allowed_tools+=$'\nfinal_answer'
	fi

	allowed_tools="$(printf '%s\n' "${allowed_tools}" | sed '/^react_fallback$/d' | awk '!seen[$0]++')"

	if [[ -z "${plan_step_guidance}" ]]; then
		plan_step_guidance="Planner provided no additional steps; choose the best next action."
	fi

	if [[ "${invoke_llama}" == true ]]; then
		allowed_tool_lines="$(format_tool_descriptions "${allowed_tools}" format_tool_example_line)"
		allowed_tool_descriptions="Available tools:"
		if [[ -n "${allowed_tool_lines}" ]]; then
			allowed_tool_descriptions+=$'\n'"${allowed_tool_lines}"
		fi

		local raw_action validated_action validation_error_file corrective_prompt
		react_schema_path="$(build_react_action_schema "${allowed_tools}")" || return 1
		react_schema_text="$(cat "${react_schema_path}")" || return 1
		local history
		history="$(format_tool_history "$(state_get_history_lines "${state_name}")")"

		react_prompt="$(
			build_react_prompt \
				"$(state_get "${state_name}" "user_query")" \
				"${allowed_tool_descriptions}" \
				"$(state_get "${state_name}" "plan_outline")" \
				"${history}" \
				"${react_schema_text}" \
				"${plan_step_guidance}"
		)"
		local summarized_history
		summarized_history="$(apply_prompt_context_budget "${react_prompt}" "${history}" 256 "react_history")"
		if [[ "${summarized_history}" != "${history}" ]]; then
			history="${summarized_history}"
			react_prompt="$(
				build_react_prompt \
					"$(state_get "${state_name}" "user_query")" \
					"${allowed_tool_descriptions}" \
					"$(state_get "${state_name}" "plan_outline")" \
					"${history}" \
					"${react_schema_text}" \
					"${plan_step_guidance}"
			)"
		fi
		validation_error_file="$(mktemp)"

		raw_action="$(llama_infer "${react_prompt}" "" 256 "${react_schema_text}" "${REACT_MODEL_REPO}" "${REACT_MODEL_FILE}")"
		if ! validated_action=$(validate_react_action "${raw_action}" "${react_schema_path}" 2>"${validation_error_file}"); then
			corrective_prompt="${react_prompt}"$'\n'"The previous response was invalid: $(cat "${validation_error_file}"). Respond with a valid JSON action that follows the schema."
			raw_action="$(llama_infer "${corrective_prompt}" "" 256 "${react_schema_text}" "${REACT_MODEL_REPO}" "${REACT_MODEL_FILE}")"

			if ! validated_action=$(validate_react_action "${raw_action}" "${react_schema_path}" 2>"${validation_error_file}"); then
				log "ERROR" "Invalid action output from llama" "$(cat "${validation_error_file}")"
				rm -f "${validation_error_file}"
				return 1
			fi
		fi

		rm -f "${validation_error_file}"
		rm -f "${react_schema_path}"

		if [[ -n "${output_name}" ]]; then
			printf -v "${output_name}" '%s' "${validated_action}"
		else
			printf '%s\n' "${validated_action}"
		fi

		if [[ "${plan_step_available}" == true ]]; then
			state_increment "${state_name}" "plan_index" 1 >/dev/null
		fi

		return
	fi

	if [[ -n "${planned_entry}" && "${tool}" != "react_fallback" ]]; then
		tool="$(printf '%s' "${planned_entry}" | jq -r '.tool // empty' 2>/dev/null || printf '')"
		thought="${planned_thought}"
		args_json="${planned_args_json}"
		next_action_payload="$(jq -nc --arg thought "${thought}" --arg tool "${tool}" --argjson args "${args_json}" '{thought:$thought, tool:$tool, args:$args}')"
		state_increment "${state_name}" "plan_index" 1 >/dev/null
	else
		local final_query history_formatted
		history_formatted="$(format_tool_history "$(state_get_history_lines "${state_name}")")"
		final_query="$(respond_text "$(state_get "${state_name}" "user_query")" 512 "${history_formatted}")"
		args_json="$(format_tool_args "final_answer" "${final_query}")"
		next_action_payload="$(jq -nc --arg thought "Providing final answer" --arg tool "final_answer" --argjson args "${args_json}" '{thought:$thought, tool:$tool, args:$args}')"
	fi

	if [[ -n "${output_name}" ]]; then
		printf -v "${output_name}" '%s' "${next_action_payload}"
	else
		printf '%s\n' "${next_action_payload}"
	fi
}
validate_tool_permission() {
	# Arguments:
	#   $1 - state prefix
	#   $2 - tool name to validate
	local state_name
	local tool
	state_name="$1"
	tool="$2"
	if grep -Fxq "${tool}" <<<"$(state_get "${state_name}" "allowed_tools")"; then
		return 0
	fi

	record_history "${state_name}" "$(printf 'Tool %s not permitted.' "${tool}")"
	return 1
}

execute_tool_action() {
	# Arguments:
	#   $1 - tool name
	#   $2 - tool query
	#   $3 - human-readable context (optional)
	#   $4 - structured args JSON (optional)
	local tool query context args_json
	tool="$1"
	query="$2"
	context="$3"
	args_json="$4"
	execute_tool_with_query "${tool}" "${query}" "${context}" "${args_json}" || true
}

record_tool_execution() {
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

finalize_react_result() {
	# Arguments:
	#   $1 - state prefix
	local state_name history_formatted final_answer observation
	state_name="$1"
	observation="$(state_get "${state_name}" "final_answer")"
	if [[ -z "${observation}" ]]; then
		log "ERROR" "Final answer missing; generating fallback" "${state_name}"
		history_formatted="$(format_tool_history "$(state_get_history_lines "${state_name}")")"
		final_answer="$(respond_text "$(state_get "${state_name}" "user_query")" 1000 "${history_formatted}")"
		state_set "${state_name}" "final_answer" "${final_answer}"
	else
		if jq -e '.output != null and .exit_code != null' <<<"${observation}" >/dev/null 2>&1; then
			final_answer=$(jq -r '.output' <<<"${observation}")
		else
			final_answer="${observation}"
		fi
	fi

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

react_loop() {
	local user_query allowed_tools plan_entries plan_outline action_json tool query observation current_step thought args_json action_context
	local state_prefix
	user_query="$1"
	allowed_tools="$2"
	plan_entries="$3"
	plan_outline="$4"

	state_prefix="react_state"
	initialize_react_state "${state_prefix}" "${user_query}" "${allowed_tools}" "${plan_entries}" "${plan_outline}"
	action_json=""

	while (($(state_get "${state_prefix}" "step") < $(state_get "${state_prefix}" "max_steps"))); do
		current_step=$(($(state_get "${state_prefix}" "step") + 1))

		select_next_action "${state_prefix}" action_json
		tool="$(printf '%s' "${action_json}" | jq -r '.tool // empty' 2>/dev/null || true)"
		thought="$(printf '%s' "${action_json}" | jq -r '.thought // empty' 2>/dev/null || true)"
		args_json="$(printf '%s' "${action_json}" | jq -c '.args // {}' 2>/dev/null || printf '{}')"

		# Duplicate action detection
		local last_action
		last_action="$(state_get "${state_prefix}" "last_action")"
		if [[ "${last_action}" != "null" ]]; then
			local last_tool last_args
			last_tool="$(printf '%s' "${last_action}" | jq -r '.tool // empty')"
			last_args="$(printf '%s' "${last_action}" | jq -c '.args // {}')"
			if [[ "${tool}" == "${last_tool}" && "${args_json}" == "${last_args}" && "${tool}" != "final_answer" ]]; then
				log "WARN" "Duplicate action detected" "${tool}"
				observation="Duplicate action detected. Please try a different approach or call final_answer if you are stuck."
				record_tool_execution "${state_prefix}" "${tool}" "${thought} (REPEATED)" "${args_json}" "${observation}" "${current_step}"
				state_set "${state_prefix}" "step" "${current_step}"
				continue
			fi
		fi
		state_set_json_document "${state_prefix}" "$(state_get_json_document "${state_prefix}" | jq -c --argjson action "${action_json}" '.last_action = $action')"

		query="$(extract_tool_query "${tool}" "${args_json}")"
		action_context="$(format_action_context "${thought}" "${tool}" "${args_json}")"

		if ! validate_tool_permission "${state_prefix}" "${tool}"; then
			state_set "${state_prefix}" "step" "${current_step}"
			continue
		fi

		observation="$(execute_tool_action "${tool}" "${query}" "${action_context}" "${args_json}")"
		record_tool_execution "${state_prefix}" "${tool}" "${thought}" "${args_json}" "${observation}" "${current_step}"

		# Check for failure and consider falling back to LLM if following a plan
		local exit_code
		exit_code=$(printf '%s' "${observation}" | jq -r '.exit_code // 0' 2>/dev/null || echo 0)
		if ((exit_code != 0)); then
			local plan_entries
			plan_entries="$(state_get "${state_prefix}" "plan_entries")"
			if [[ -n "${plan_entries}" && "${LLAMA_AVAILABLE}" == true ]]; then
				log "INFO" "Tool failed during planned execution; falling back to LLM" "${tool}"
				# Clear remaining plan entries to force LLM selection in next step
				state_set "${state_prefix}" "plan_entries" ""
			fi
		fi

		state_set "${state_prefix}" "step" "${current_step}"
		if [[ "${tool}" == "final_answer" ]]; then
			state_set "${state_prefix}" "final_answer" "${observation}"
			break
		fi
	done

	finalize_react_result "${state_prefix}"
}
