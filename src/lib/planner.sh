#!/usr/bin/env bash
# shellcheck shell=bash
#
# Planning and execution helpers for the okso assistant CLI.
#
# Usage:
#   source "${BASH_SOURCE[0]%/planner.sh}/planner.sh"
#
# Environment variables:
#   USER_QUERY (string): user-provided request for planning.
#   LLAMA_BIN (string): llama.cpp binary path.
#   MODEL_REPO (string): Hugging Face repository name.
#   MODEL_FILE (string): model file within the repository.
#   TOOLS (array): optional array of tool names available to the planner.
#   PLAN_ONLY, DRY_RUN (bool): control execution and preview behaviour.
#   APPROVE_ALL, FORCE_CONFIRM (bool): confirmation toggles.
#   VERBOSITY (int): log level.
#
# Dependencies:
#   - bash 3+
#   - optional llama.cpp binary
#   - jq
#   - gum (for interactive approvals; falls back to POSIX prompts)
#
# Exit codes:
#   Functions return non-zero on misuse; fatal errors logged by caller.

LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./errors.sh disable=SC1091
source "${LIB_DIR}/errors.sh"
# shellcheck source=./logging.sh disable=SC1091
source "${LIB_DIR}/logging.sh"
# shellcheck source=./tools.sh disable=SC1091
source "${LIB_DIR}/tools.sh"
# shellcheck source=./respond.sh disable=SC1091
source "${LIB_DIR}/respond.sh"
# shellcheck source=./prompts.sh disable=SC1091
source "${LIB_DIR}/prompts.sh"
# shellcheck source=./grammar.sh disable=SC1091
source "${LIB_DIR}/grammar.sh"
# shellcheck source=./state.sh disable=SC1091
source "${LIB_DIR}/state.sh"
# shellcheck source=./llama_client.sh disable=SC1091
source "${LIB_DIR}/llama_client.sh"
# shellcheck source=./formatting.sh disable=SC1091
source "${LIB_DIR}/formatting.sh"

lowercase() {
	# Arguments:
	#   $1 - input string
	printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

# Normalize noisy planner output into a clean PlannerPlan JSON array of objects.
# Reads from stdin, writes clean JSON array to stdout.
normalize_planner_plan() {
	local raw plan_candidate fallback_json normalized

	raw="$(cat)"
	plan_candidate="$(jq -ec '.' <<<"${raw}" 2>/dev/null || true)"

	fallback_json=$(printf '%s' "$raw" |
		sed -E 's/^[[:space:]]*[0-9]+[.)][[:space:]]*//' |
		sed -E 's/^[[:space:]-]+//' |
		sed '/^[[:space:]]*$/d' |
		jq -Rsc 'split("\n") | map(select(length > 0)) | map({tool:"react_fallback",thought:.,args:{}})') || fallback_json=""

	if [[ -n "${plan_candidate:-}" ]] && jq -e 'type == "array"' <<<"${plan_candidate}" >/dev/null 2>&1; then
		normalized=$(jq -ec '
                        map(select(type=="object"))
                        | map({tool: (.tool // ""), args: (.args // {}), thought: (.thought // "")})
                        | map(select((.tool | type) == "string" and (.tool | length) > 0))
                        ' <<<"${plan_candidate}" 2>/dev/null || true)
		if [[ -n "${normalized}" && "${normalized}" != "[]" ]]; then
			printf '%s' "$normalized" | jq -c '.'
			return 0
		fi

		log "ERROR" "normalize_planner_plan: invalid structured plan" "${plan_candidate}" >&2
		return 1
	fi

	if [[ -z "${plan_candidate:-}" && -n "${fallback_json}" && "${fallback_json}" != "[]" ]]; then
		log "INFO" "normalize_planner_plan: derived plan from fallback outline" "${fallback_json}" >&2
		printf '%s' "$fallback_json" | jq -c '.'
		return 0
	fi

	log "ERROR" "normalize_planner_plan: no JSON array found in planner output" "" >&2
	return 1
}

append_final_answer_step() {
	# Ensures the plan includes a final step with the final_answer tool.
	# Arguments:
	#   $1 - plan JSON array (string)
	local plan_json has_final updated_plan
	plan_json="${1:-[]}"

	plan_clean="$(printf '%s' "$plan_json" | normalize_planner_plan)" || return 1

	has_final="$(jq -r 'map((.tool // "") | ascii_downcase == "final_answer") | any' <<<"${plan_clean}" 2>/dev/null || echo false)"
	if [[ "${has_final}" == "true" ]]; then
		printf '%s' "${plan_clean}"
		return 0
	fi

	updated_plan="$(jq -c '. + [{tool:"final_answer",thought:"Summarize the result for the user.",args:{}}]' <<<"${plan_clean}" 2>/dev/null || printf '%s' "${plan_json}")"
	printf '%s' "${updated_plan}"
}

plan_json_to_outline() {
	# Converts a JSON array of plan steps into a numbered outline string.
	# Arguments:
	#   $1 - plan JSON array (string)
	local plan_json
	plan_json="${1:-[]}"

	plan_clean="$(printf '%s' "$plan_json" | normalize_planner_plan)" || return 1
	if [[ -z "${plan_clean}" ]]; then
		return 1
	fi

	jq -r 'to_entries | map("\(.key + 1). " + (if (.value.thought // "") != "" then (.value.thought // "") else "Use " + (.value.tool // "unknown") end)) | join("\n")' <<<"${plan_clean}"
}

generate_plan_json() {
	# Arguments:
	#   $1 - user query (string)
	local user_query
	local -a planner_tools=()
	user_query="$1"

	local tools_decl
	if tools_decl=$(declare -p TOOLS 2>/dev/null) && grep -q 'declare -a' <<<"${tools_decl}"; then
		planner_tools=("${TOOLS[@]}")
	else
		planner_tools=()
		while IFS= read -r tool_name; do
			[[ -z "${tool_name}" ]] && continue
			planner_tools+=("${tool_name}")
		done < <(tool_names)
	fi

	if [[ "${LLAMA_AVAILABLE}" != true ]]; then
		log "WARN" "Using static plan because llama is unavailable" "LLAMA_AVAILABLE=${LLAMA_AVAILABLE}" >&2
		printf '%s' '[{"tool":"final_answer","args":{},"thought":"Respond directly to the user request."}]'
		return 0
	fi

	local prompt raw_plan planner_grammar_path plan_json
	local tool_lines
	if ((${#planner_tools[@]} > 0)); then
		tool_lines="$(format_tool_descriptions "$(printf '%s\n' "${planner_tools[@]}")" format_tool_summary_line)"
	else
		tool_lines=""
	fi
	planner_grammar_path="$(grammar_path planner_plan)"

	prompt="$(build_planner_prompt "${user_query}" "${tool_lines}")"
	log "DEBUG" "Generated planner prompt" "${prompt}" >&2
	raw_plan="$(llama_infer "${prompt}" '' 512 "${planner_grammar_path}")" || raw_plan="[]"
	plan_json="$(append_final_answer_step "${raw_plan}")" || plan_json="${raw_plan}"
	printf '%s' "${plan_json}"
}

generate_plan_outline() {
	# Arguments:
	#   $1 - user query (string)
	local plan_json
	plan_json="$(generate_plan_json "$1")"
	plan_json_to_outline "${plan_json}"
}

tool_query_deriver() {
	# Arguments:
	#   $1 - tool name (string)
	case "$1" in
	terminal)
		printf '%s' "derive_terminal_query"
		;;
	reminders_create)
		printf '%s' "derive_reminders_create_query"
		;;
	reminders_list)
		printf '%s' "derive_reminders_list_query"
		;;
	notes_create)
		printf '%s' "derive_notes_create_query"
		;;
	notes_append)
		printf '%s' "derive_notes_append_query"
		;;
	notes_search)
		printf '%s' "derive_notes_search_query"
		;;
	notes_read)
		printf '%s' "derive_notes_read_query"
		;;
	notes_list)
		printf '%s' "derive_notes_list_query"
		;;
	*)
		printf '%s' "derive_default_tool_query"
		;;
	esac
}

derive_default_tool_query() {
	# Arguments:
	#   $1 - user query (string)
	printf '%s\n' "$1"
}

derive_tool_query() {
	# Arguments:
	#   $1 - tool name (string)
	#   $2 - user query (string)
	local tool_name user_query handler
	tool_name="$1"
	user_query="$2"
	handler="$(tool_query_deriver "${tool_name}")"

	"${handler}" "${user_query}"
}

emit_plan_json() {
	local plan_entries
	plan_entries="$1"

	if [[ -z "${plan_entries}" ]]; then
		printf '[]'
		return 0
	fi

	printf '%s\n' "${plan_entries}" |
		sed '/^[[:space:]]*$/d' |
		jq -sc 'map(select(type=="object"))'
}

derive_allowed_tools_from_plan() {
	# Arguments:
	#   $1 - plan JSON array (string)
	local plan_json tool seen allow_all
	plan_json="${1:-[]}"
	allow_all=false

	if jq -e 'map((.tool // "") == "react_fallback") | any' <<<"${plan_json}" >/dev/null 2>&1; then
		allow_all=true
	fi

	if [[ "${allow_all}" == true ]]; then
		tool_names
		return 0
	fi

	seen=""
	local -a required=()
	while IFS= read -r tool; do
		[[ -z "${tool}" ]] && continue
		if grep -Fxq "${tool}" <<<"${seen}"; then
			continue
		fi
		required+=("${tool}")
		seen+="${tool}"$'\n'
	done < <(jq -r '.[] | .tool // empty' <<<"${plan_json}" 2>/dev/null || true)

	if ! grep -Fxq "final_answer" <<<"${seen}"; then
		required+=("final_answer")
	fi

	printf '%s\n' "${required[@]}"
}

plan_json_to_entries() {
	local plan_json
	plan_json="$1"
	printf '%s' "${plan_json}" | jq -cr '.[]'
}

should_prompt_for_tool() {
	if [[ "${PLAN_ONLY}" == true || "${DRY_RUN}" == true ]]; then
		return 1
	fi
	if [[ "${FORCE_CONFIRM}" == true ]]; then
		return 0
	fi
	if [[ "${APPROVE_ALL}" == true ]]; then
		return 1
	fi

	return 0
}

confirm_tool() {
	local tool_name context
	tool_name="$1"
	context="$2"
	if ! should_prompt_for_tool; then
		return 0
	fi

	local prompt
	prompt="Execute tool \"${tool_name}\"?"
	if [[ -n "${context}" ]]; then
		prompt+=$'\n'"${context}"
	fi
	if command -v gum >/dev/null 2>&1; then
		if ! gum confirm --affirmative "Run" --negative "Skip" "${prompt}"; then
			log "WARN" "Tool execution declined" "${tool_name}"
			printf '[%s skipped]\n' "${tool_name}"
			return 1
		fi
		return 0
	fi

	printf '%s [y/N]: ' "${prompt}" >&2
	read -r reply
	if [[ "${reply}" != "y" && "${reply}" != "Y" ]]; then
		log "WARN" "Tool execution declined" "${tool_name}"
		printf '[%s skipped]\n' "${tool_name}"
		return 1
	fi
	return 0
}

execute_tool_with_query() {
	# Arguments:
	#   $1 - tool name
	#   $2 - tool query (legacy string)
	#   $3 - human-readable context
	#   $4 - structured args JSON
	local tool_name tool_query context handler output status tool_args_json
	tool_name="$1"
	tool_query="$2"
	context="$3"
	tool_args_json="$4"
	handler="$(tool_handler "${tool_name}")"

	local requires_confirmation
	requires_confirmation=false
	if [[ "${tool_name}" != "final_answer" ]] && should_prompt_for_tool; then
		requires_confirmation=true
	fi

	if [[ -z "${handler}" ]]; then
		log "ERROR" "No handler registered for tool" "${tool_name}" >&2
		return 1
	fi

	if [[ "${tool_name}" != "final_answer" ]]; then
		if [[ "${requires_confirmation}" == true ]]; then
			log "INFO" "Requesting tool confirmation" "$(printf 'tool=%s query=%s' "${tool_name}" "${tool_query}")" >&2
		fi

		if ! confirm_tool "${tool_name}" "${context}"; then
			printf 'Declined %s\n' "${tool_name}"
			return 0
		fi
	fi

	if [[ "${DRY_RUN}" == true || "${PLAN_ONLY}" == true ]]; then
		log "INFO" "Skipping execution in preview mode" "${tool_name}" >&2
		return 0
	fi

	local stdout_file stderr_file stderr_output
	stdout_file="$(mktemp)"
	stderr_file="$(mktemp)"

	TOOL_QUERY="${tool_query}" TOOL_ARGS="${tool_args_json}" ${handler} >"${stdout_file}" 2>"${stderr_file}"
	status=$?
	output="$(cat "${stdout_file}")"
	stderr_output="$(cat "${stderr_file}")"

	rm -f "${stdout_file}" "${stderr_file}"

	if [[ -n "${stderr_output}" ]]; then
		log "INFO" "Tool emitted stderr" "$(printf 'tool=%s stderr=%s' "${tool_name}" "${stderr_output}")" >&2
	fi
	if ((status != 0)); then
		log "WARN" "Tool reported non-zero exit" "${tool_name}" >&2
	fi
	printf '%s\n' "${output}"
	return 0
}

initialize_react_state() {
	# Arguments:
	#   $1 - state prefix to populate
	#   $2 - user query
	#   $3 - allowed tools (newline delimited)
	#   $4 - ranked plan entries
	#   $5 - plan outline text
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
                        final_answer: ""
                }')"
}

record_history() {
	# Arguments:
	#   $1 - state prefix
	#   $2 - formatted history entry
	local entry
	entry="$2"
	state_append_history "$1" "${entry}"
}

format_tool_args() {
	# Arguments:
	#   $1 - tool name
	#   $2 - primary payload string
	# Returns JSON describing structured args for the tool.
	local tool payload
	tool="$1"
	payload="$2"
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
	file_search | notes_search | calendar_search | mail_search)
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
		jq -nc --arg script "${payload}" '{script:$script}'
		;;
	feedback | final_answer)
		jq -nc --arg message "${payload}" '{message:$message}'
		;;
	*)
		jq -nc --arg message "${payload}" '{message:$message}'
		;;
	esac
}

extract_tool_query() {
	# Arguments:
	#   $1 - tool name
	#   $2 - args JSON
	# Returns a human-readable summary derived from structured args.
	local tool args_json
	tool="$1"
	args_json="$2"
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
	file_search | notes_search | calendar_search | mail_search)
		jq -r '(.query // "")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	clipboard_copy)
		jq -r '(.text // "")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	mail_draft | mail_send)
		jq -r '(.envelope // "")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	applescript)
		jq -r '(.script // "")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	feedback | final_answer)
		jq -r '(.message // "")' <<<"${args_json}" 2>/dev/null || printf ''
		;;
	clipboard_paste | notes_list | reminders_list | calendar_list | mail_list_inbox | mail_list_unread)
		printf ''
		;;
	*)
		jq -r '(.message // .query // "")' <<<"${args_json}" 2>/dev/null || printf ''
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

build_react_action_grammar() {
	# Arguments:
	#   $1 - newline-delimited allowed tools (optional)
	local allowed_tools registry_json
	allowed_tools="$1"

	if [[ -z "$(tool_names)" ]] && declare -F initialize_tools >/dev/null 2>&1; then
		initialize_tools >/dev/null 2>&1 || true
	fi
	registry_json="$(tool_registry_json)"

	python3 - "${allowed_tools}" "${registry_json}" <<'PY'
import json
import sys
import tempfile

allowed_raw = sys.argv[1]
registry = json.loads(sys.argv[2] or "{}")

fallback_schema = {
    "type": "object",
    "properties": {"message": {"type": "string"}},
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
    "allOf": [
        {
            "if": {"properties": {"tool": {"const": name}}, "required": ["tool"]},
            "then": {"properties": {"args": tool_schema}},
        }
        for name, tool_schema in args_by_tool.items()
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
	local raw_action schema_path
	raw_action="$1"
	schema_path="$2"

	python3 - "$raw_action" "$schema_path" <<'PY'
import json
import sys
from pathlib import Path

raw = sys.argv[1]
schema_path = Path(sys.argv[2])

try:
    action = json.loads(raw)
except Exception as exc:  # noqa: BLE001
    print(f"Invalid JSON: {exc}", file=sys.stderr)
    sys.exit(1)

try:
    schema = json.loads(schema_path.read_text())
except Exception as exc:  # noqa: BLE001
    print(f"Schema load failed: {exc}", file=sys.stderr)
    sys.exit(1)

required_keys = ("thought", "tool", "args")
for key in required_keys:
    if key not in action:
        print(f"Missing field: {key}", file=sys.stderr)
        sys.exit(1)

for key in action:
    if key not in required_keys:
        print(f"Unexpected field: {key}", file=sys.stderr)
        sys.exit(1)

thought = action.get("thought")
if not isinstance(thought, str) or not thought.strip():
    print("thought must be a non-empty string", file=sys.stderr)
    sys.exit(1)

tool = action.get("tool")
if not isinstance(tool, str):
    print("tool must be a string", file=sys.stderr)
    sys.exit(1)

allowed_tools = schema.get("properties", {}).get("tool", {}).get("enum", [])
if tool not in allowed_tools:
    print(f"Unsupported tool: {tool}", file=sys.stderr)
    sys.exit(1)

args = action.get("args")
if not isinstance(args, dict):
    print("args must be an object", file=sys.stderr)
    sys.exit(1)

tool_schemas = schema.get("$defs", {}).get("args_by_tool", {})
tool_schema = tool_schemas.get(tool)
if tool_schema is None:
    print(f"No schema for tool: {tool}", file=sys.stderr)
    sys.exit(1)

properties = tool_schema.get("properties", {})
if not isinstance(properties, dict):
    properties = {}
required_args = tool_schema.get("required", [])
additional_properties = tool_schema.get("additionalProperties")
if additional_properties is None:
    additional_properties = False

TYPE_MAP = {
    "string": str,
    "object": dict,
    "array": list,
    "boolean": bool,
    "number": (int, float),
    "integer": int,
}

def enforce_type(key: str, value, schema: dict) -> None:
    expected_type = schema.get("type")
    python_type = TYPE_MAP.get(expected_type)

    if python_type is not None and not isinstance(value, python_type):
        print(f"Arg {key} must be a {expected_type}", file=sys.stderr)
        sys.exit(1)

    if expected_type == "string":
        min_length = schema.get("minLength", 0)
        if min_length > 0 and isinstance(value, str) and not value.strip():
            print(f"Arg {key} cannot be empty", file=sys.stderr)
            sys.exit(1)

    if expected_type == "array":
        item_schema = schema.get("items", {})
        item_type = item_schema.get("type")
        if item_type == "string" and any(not isinstance(item, str) for item in value):
            print(f"Arg {key} items must be strings", file=sys.stderr)
            sys.exit(1)

for key in required_args:
    if key not in args:
        print(f"Missing arg: {key}", file=sys.stderr)
        sys.exit(1)

for key, value in args.items():
    if key in properties:
        enforce_type(key, value, properties.get(key, {}))
        continue

    if additional_properties is False:
        print(f"Unexpected arg: {key}", file=sys.stderr)
        sys.exit(1)

    if isinstance(additional_properties, dict):
        enforce_type(key, value, additional_properties)

print(json.dumps({
    "thought": thought.strip(),
    "tool": tool,
    "args": args,
}, separators=(",", ":")))
PY
}

select_next_action() {
	# Arguments:
	#   $1 - state prefix
	#   $2 - (optional) name of variable to receive JSON action output
	local state_name output_name react_prompt plan_index planned_entry tool query next_action_payload allowed_tool_descriptions allowed_tool_lines args_json allowed_tools react_grammar_path react_grammar_text invoke_llama thought
	state_name="$1"
	output_name="${2:-}"

	plan_index="$(state_get "${state_name}" "plan_index")"
	plan_index=${plan_index:-0}
	planned_entry=$(printf '%s\n' "$(state_get "${state_name}" "plan_entries")" | sed -n "$((plan_index + 1))p")
	tool=""
	if [[ -n "${planned_entry}" ]]; then
		tool="$(printf '%s' "${planned_entry}" | jq -r '.tool // empty' 2>/dev/null || printf '')"
	fi

	invoke_llama=false
	if [[ "${USE_REACT_LLAMA:-false}" == true && "${LLAMA_AVAILABLE}" == true ]]; then
		invoke_llama=true
	fi
	if [[ "${tool}" == "react_fallback" && "${LLAMA_AVAILABLE}" == true ]]; then
		invoke_llama=true
		state_increment "${state_name}" "plan_index" 1 >/dev/null
	fi

	if [[ "${invoke_llama}" == true ]]; then
		allowed_tools="$(state_get "${state_name}" "allowed_tools")"
		allowed_tool_lines="$(format_tool_descriptions "${allowed_tools}" format_tool_example_line)"
		allowed_tool_descriptions="Available tools:"
		if [[ -n "${allowed_tool_lines}" ]]; then
			allowed_tool_descriptions+=$'\n'"${allowed_tool_lines}"
		fi

		local raw_action validated_action validation_error_file corrective_prompt
		react_grammar_path="$(build_react_action_grammar "${allowed_tools}")" || return 1
		react_grammar_text="$(cat "${react_grammar_path}")" || return 1
		react_prompt="$(
			build_react_prompt \
				"$(state_get "${state_name}" "user_query")" \
				"${allowed_tool_descriptions}" \
				"$(state_get "${state_name}" "plan_outline")" \
				"$(state_get "${state_name}" "history")" \
				"${react_grammar_text}"
		)"
		validation_error_file="$(mktemp)"

		raw_action="$(llama_infer "${react_prompt}" "" 256 "${react_grammar_path}")"
		if ! validated_action=$(validate_react_action "${raw_action}" "${react_grammar_path}" 2>"${validation_error_file}"); then
			corrective_prompt="${react_prompt}"$'\n'"The previous response was invalid: $(cat "${validation_error_file}"). Respond with a valid JSON action that follows the schema."
			raw_action="$(llama_infer "${corrective_prompt}" "" 256 "${react_grammar_path}")"

			if ! validated_action=$(validate_react_action "${raw_action}" "${react_grammar_path}" 2>"${validation_error_file}"); then
				log "ERROR" "Invalid action output from llama" "$(cat "${validation_error_file}")"
				rm -f "${validation_error_file}"
				return 1
			fi
		fi

		rm -f "${validation_error_file}"
		rm -f "${react_grammar_path}"

		if [[ -n "${output_name}" ]]; then
			printf -v "${output_name}" '%s' "${validated_action}"
		else
			printf '%s\n' "${validated_action}"
		fi

		return
	fi

	if [[ -n "${planned_entry}" ]]; then
		state_increment "${state_name}" "plan_index" 1 >/dev/null
		tool="$(printf '%s' "${planned_entry}" | jq -r '.tool // empty' 2>/dev/null || printf '')"
		thought="$(printf '%s' "${planned_entry}" | jq -r '.thought // "Following planned step"' 2>/dev/null || printf '')"
		args_json="$(printf '%s' "${planned_entry}" | jq -c '.args // {}' 2>/dev/null || printf '{}')"
		next_action_payload="$(jq -nc --arg thought "${thought}" --arg tool "${tool}" --argjson args "${args_json}" '{thought:$thought, tool:$tool, args:$args}')"
	else
		local final_query
		final_query="$(respond_text "$(state_get "${state_name}" "user_query") $(state_get "${state_name}" "history")" 512)"
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

print(json.dumps({
    "step": step,
    "thought": thought,
    "action": {"tool": tool, "args": args},
    "observation": observation,
}, separators=(",", ":")))
PY
	)
	record_history "${state_name}" "${entry}"
	log "INFO" "Recorded tool execution" "$(printf 'step=%s tool=%s' "${step_index}" "${tool}")"
}

finalize_react_result() {
	# Arguments:
	#   $1 - state prefix
	local state_name
	state_name="$1"
	if [[ -z "$(state_get "${state_name}" "final_answer")" ]]; then
		log "ERROR" "Final answer missing; generating fallback" "${state_name}"
		state_set "${state_name}" "final_answer" "$(respond_text "$(state_get "${state_name}" "user_query") $(state_get "${state_name}" "history")" 1000)"
	fi

	log_pretty "INFO" "Final answer" "$(state_get "${state_name}" "final_answer")"
	if [[ -z "$(state_get "${state_name}" "history")" ]]; then
		log "INFO" "Execution summary" "No tool runs"
	else
		log_pretty "INFO" "Execution summary" "$(state_get "${state_name}" "history")"
	fi

	emit_boxed_summary \
		"$(state_get "${state_name}" "user_query")" \
		"$(state_get "${state_name}" "plan_outline")" \
		"$(state_get "${state_name}" "history")" \
		"$(state_get "${state_name}" "final_answer")"
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
		query="$(extract_tool_query "${tool}" "${args_json}")"
		action_context="$(format_action_context "${thought}" "${tool}" "${args_json}")"

		if ! validate_tool_permission "${state_prefix}" "${tool}"; then
			state_set "${state_prefix}" "step" "${current_step}"
			continue
		fi

		observation="$(execute_tool_action "${tool}" "${query}" "${action_context}" "${args_json}")"
		record_tool_execution "${state_prefix}" "${tool}" "${thought}" "${args_json}" "${observation}" "${current_step}"

		state_set "${state_prefix}" "step" "${current_step}"
		if [[ "${tool}" == "final_answer" ]]; then
			state_set "${state_prefix}" "final_answer" "${observation}"
			break
		fi
	done

	finalize_react_result "${state_prefix}"
}
