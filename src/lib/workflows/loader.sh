#!/usr/bin/env bash
# shellcheck shell=bash
#
# Workflow loader and expander for okso plans.
#
# Usage:
#   source "${BASH_SOURCE[0]%/loader.sh}/loader.sh"
#
# Environment variables:
#   WORKFLOWS_DIR (string): override workflows directory; defaults to repo_root/workflows.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#   - ruby (for YAML parsing)
#   - logging helpers from logging.sh
#
# Exit codes:
#   Functions return non-zero on invalid workflow specs or missing workflows.

WORKFLOWS_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKFLOWS_REPO_ROOT=$(cd -- "${WORKFLOWS_LIB_DIR}/../../.." && pwd)
WORKFLOWS_DIR_DEFAULT="${WORKFLOWS_REPO_ROOT}/workflows"
WORKFLOWS_DIR="${WORKFLOWS_DIR:-${WORKFLOWS_DIR_DEFAULT}}"

# shellcheck source=src/lib/core/logging.sh
source "${WORKFLOWS_LIB_DIR}/../core/logging.sh"

WORKFLOW_REGISTRY_JSON='{"names":[],"registry":{}}'
WORKFLOW_SPECS_JSON='{}'
WORKFLOWS_LOADED=false
WORKFLOWS_LOADED_DIR=""

workflows_reset_registry() {
	WORKFLOW_REGISTRY_JSON='{"names":[],"registry":{}}'
	WORKFLOW_SPECS_JSON='{}'
	WORKFLOWS_LOADED=false
	WORKFLOWS_LOADED_DIR=""
}

workflows_registry_json() {
	printf '%s' "${WORKFLOW_REGISTRY_JSON}"
}

workflow_names() {
	jq -r '.names[]?' <<<"$(workflows_registry_json)"
}

workflow_spec_json() {
	local name
	name="$1"
	jq -c --arg name "${name}" '.[$name] // empty' <<<"${WORKFLOW_SPECS_JSON}"
}

workflow_parameters_schema() {
	# Arguments:
	#   $1 - workflow spec JSON (object)
	# Returns:
	#   JSON schema for parameters
	local spec
	spec="$1"

	jq -c '
		.parameters
		// {"type":"object","properties":{},"additionalProperties":false}
	' <<<"${spec}"
}

workflow_register_spec() {
	# Arguments:
	#   $1 - workflow spec JSON (object)
	local spec name description parameters
	spec="$1"

	name=$(jq -r '.name // empty' <<<"${spec}")
	description=$(jq -r '.description // ""' <<<"${spec}")
	parameters=$(workflow_parameters_schema "${spec}")

	if jq -e --arg name "${name}" '.registry[$name] != null' <<<"${WORKFLOW_REGISTRY_JSON}" >/dev/null 2>&1; then
		log "ERROR" "Duplicate workflow name" "${name}" >&2
		return 1
	fi

	WORKFLOW_REGISTRY_JSON=$(jq -c \
		--arg name "${name}" \
		--arg description "${description}" \
		--argjson parameters "${parameters}" \
		'(.names //= [])
		| (.registry //= {})
		| .names += [$name]
		| .registry[$name] = {description:$description, parameters:$parameters}' <<<"${WORKFLOW_REGISTRY_JSON}")

	WORKFLOW_SPECS_JSON=$(jq -c \
		--arg name "${name}" \
		--argjson spec "${spec}" \
		'.[$name] = $spec' <<<"${WORKFLOW_SPECS_JSON}")
}

workflow_parse_json_file() {
	# Arguments:
	#   $1 - path to JSON spec (string)
	# Returns:
	#   parsed JSON on stdout
	local file
	file="$1"

	jq -c '.' "${file}"
}

workflow_parse_yaml_file() {
	# Arguments:
	#   $1 - path to YAML spec (string)
	# Returns:
	#   parsed JSON on stdout
	local file
	file="$1"

	ruby -rjson -ryaml -e 'data = YAML.safe_load(File.read(ARGV[0]), permitted_classes: [], permitted_symbols: [], aliases: false); puts JSON.generate(data)' "${file}"
}

workflow_parse_file() {
	# Arguments:
	#   $1 - workflow file path (string)
	# Returns:
	#   parsed JSON on stdout
	local file
	file="$1"

	case "${file}" in
		*.json)
			workflow_parse_json_file "${file}"
			;;
		*.yaml | *.yml)
			workflow_parse_yaml_file "${file}"
			;;
		*)
			return 1
			;;
	esac
}

workflow_validate_spec() {
	# Arguments:
	#   $1 - workflow spec JSON (object)
	local spec
	spec="$1"

	if ! jq -e '
		(type == "object")
		and (.name | type == "string" and length > 0)
		and (.name | test("^[a-z0-9_]+$"))
		and (.description | type == "string")
		and (.steps | type == "array" and length > 0)
		and (all(.steps[]; (type == "object")
			and (.tool | type == "string" and length > 0)
			and ((.args | type == "object") or (.args == null))
			and (.thought | type == "string")))
		and ((.parameters | type == "object") or (.parameters == null))
		and ((.parameters | has("type") | not) or (.parameters.type == "object"))
	' <<<"${spec}" >/dev/null 2>&1; then
		return 1
	fi
}

workflow_normalize_spec() {
	# Arguments:
	#   $1 - workflow spec JSON (object)
	# Returns:
	#   normalized JSON on stdout
	local spec
	spec="$1"

	jq -c '
		.parameters = (.parameters // {"type":"object","properties":{},"additionalProperties":false})
		| .steps = (.steps
			| map(.args = (.args // {}) | .thought = (.thought // "")))
	' <<<"${spec}"
}

workflows_list_files() {
	# Returns:
	#   null-delimited list of workflow files
	if [[ ! -d "${WORKFLOWS_DIR}" ]]; then
		return 0
	fi

	find "${WORKFLOWS_DIR}" -maxdepth 1 -type f \( -name '*.json' -o -name '*.yaml' -o -name '*.yml' \) -print0
}

workflows_load_specs() {
	# Loads workflow specs into the registry.
	# Returns:
	#   None; returns non-zero on failure.
	local file spec normalized

	if [[ "${WORKFLOWS_LOADED}" == true && "${WORKFLOWS_LOADED_DIR}" == "${WORKFLOWS_DIR}" ]]; then
		return 0
	fi

	workflows_reset_registry

	if [[ ! -d "${WORKFLOWS_DIR}" ]]; then
		WORKFLOWS_LOADED=true
		WORKFLOWS_LOADED_DIR="${WORKFLOWS_DIR}"
		return 0
	fi

	while IFS= read -r -d '' file; do
		if ! spec=$(workflow_parse_file "${file}"); then
			log "ERROR" "Failed to parse workflow" "${file}" >&2
			return 1
		fi

		if ! workflow_validate_spec "${spec}"; then
			log "ERROR" "Invalid workflow spec" "${file}" >&2
			return 1
		fi

		normalized=$(workflow_normalize_spec "${spec}")
		if ! workflow_register_spec "${normalized}"; then
			log "ERROR" "Failed to register workflow" "${file}" >&2
			return 1
		fi
	done < <(workflows_list_files)

	WORKFLOWS_LOADED=true
	WORKFLOWS_LOADED_DIR="${WORKFLOWS_DIR}"
	return 0
}

workflow_render_steps() {
	# Arguments:
	#   $1 - workflow spec JSON (object)
	#   $2 - workflow args JSON (object)
	# Returns:
	#   expanded step array JSON on stdout
	local spec args
	spec="$1"
	args="$2"

	if ! jq -e 'type == "object"' <<<"${args}" >/dev/null 2>&1; then
		log "ERROR" "Workflow invocation args must be an object" "${args}" >&2
		return 1
	fi

	jq -c --argjson args "${args}" '
		def walk(f):
			. as $in
			| if type == "object" then
				reduce keys[] as $key ({}; . + {($key): ($in[$key] | walk(f))}) | f
			  elif type == "array" then
				map(walk(f)) | f
			  else
				f
			  end;

		def render($vars):
			walk(
				if type == "string" then
					reduce ($vars | keys[]) as $key (.;
						gsub("\\{\\{" + $key + "\\}\\}"; ($vars[$key] | tostring)))
				else
					.
				end
			);

		.steps
		| map({
			tool: .tool,
			args: ((.args // {}) | render($args)),
			thought: ((.thought // "") | render($args))
		})
	' <<<"${spec}"
}

expand_workflow_plan() {
	# Expands workflow tools into concrete plan steps.
	# Arguments:
	#   $1 - plan JSON array (array)
	# Returns:
	#   expanded plan JSON array on stdout
	local plan_json expanded entry tool workflow_name spec args expanded_steps
	plan_json="$1"
	expanded='[]'

	if ! workflows_load_specs; then
		return 1
	fi

	while IFS= read -r entry; do
		tool=$(jq -r '.tool // empty' <<<"${entry}")
		if [[ "${tool}" == workflow_* ]]; then
			workflow_name="${tool#workflow_}"
			spec=$(workflow_spec_json "${workflow_name}")
			if [[ -z "${spec}" ]]; then
				log "ERROR" "Unknown workflow" "${workflow_name}" >&2
				return 1
			fi
			args=$(jq -c '.args // {}' <<<"${entry}")
			if ! expanded_steps=$(workflow_render_steps "${spec}" "${args}"); then
				return 1
			fi
			expanded=$(jq -c --argjson current "${expanded}" --argjson steps "${expanded_steps}" '$current + $steps' <<<"${expanded}")
		else
			expanded=$(jq -c --argjson current "${expanded}" --argjson step "${entry}" '$current + [$step]' <<<"${expanded}")
		fi
	done < <(jq -c '.[]' <<<"${plan_json}")

	printf '%s' "${expanded}"
}

workflow_pseudo_handler() {
	log "ERROR" "Workflow tools must be expanded before execution" "workflow_invoked_without_expansion" >&2
	return 1
}

register_workflow_tools() {
	# Registers workflow pseudo-tools in the tool registry.
	# Returns:
	#   None; returns non-zero on failure.
	local name description parameters tool_name

	if ! workflows_load_specs; then
		return 1
	fi

	while IFS= read -r name; do
		[[ -z "${name}" ]] && continue
		description=$(jq -r --arg name "${name}" '.registry[$name].description // ""' <<<"${WORKFLOW_REGISTRY_JSON}")
		parameters=$(jq -c --arg name "${name}" '.registry[$name].parameters // {"type":"object"}' <<<"${WORKFLOW_REGISTRY_JSON}")
		tool_name="workflow_${name}"
		register_tool "${tool_name}" "Workflow: ${description}" "workflow_pseudo_handler" "${parameters}"
	done < <(workflow_names)
}

export -f workflows_registry_json workflow_names workflow_spec_json workflows_load_specs
export -f expand_workflow_plan register_workflow_tools
