#!/usr/bin/env bash
# shellcheck shell=bash
#
# Restricted Python REPL tool using an isolated sandbox directory.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/python_repl/index.sh}/tools/python_repl/index.sh"
#
# Environment variables:
#   TOOL_ARGS (JSON object): structured args including `input` with Python statements.
#
# Dependencies:
#   - bash 3.2+
#   - python 3+
#   - mktemp
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero when sandbox creation or interpreter startup fails.

# shellcheck source=../../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/python_repl/index.sh}/lib/core/logging.sh"
# shellcheck source=../../lib/dependency_guards/dependency_guards.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/python_repl/index.sh}/lib/dependency_guards/dependency_guards.sh"
# shellcheck source=../registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/python_repl/index.sh}/registry.sh"

python_repl_create_sandbox() {
	# Outputs the sandbox path.
	local sandbox_dir # string temporary directory path
	sandbox_dir=$(mktemp -d "${TMPDIR:-/tmp}/python_repl.XXXXXX") || return 1
	printf '%s\n' "${sandbox_dir}"
}

python_repl_write_startup() {
	# Arguments:
	#   $1 - sandbox directory (string)
	# Outputs the startup file path.
	local sandbox_dir startup_path # string
	sandbox_dir="$1"
	startup_path="${sandbox_dir}/startup.py"
	cat <<'PY' >"${startup_path}" || return 1
import builtins
import os
import pathlib
import sys

_SANDBOX = pathlib.Path(os.environ["PYTHON_REPL_SANDBOX"]).resolve()
_original_open = builtins.open


def _guarded_open(file, mode="r", buffering=-1, encoding=None, errors=None, newline=None, closefd=True, opener=None):
    path = pathlib.Path(file)
    if not path.is_absolute():
        path = (_SANDBOX / path).resolve()
    else:
        path = path.resolve()

    if any(flag in mode for flag in ("w", "a", "x", "+")):
        if _SANDBOX != path and _SANDBOX not in path.parents:
            raise PermissionError(f"File writes restricted to sandbox: {path}")

    return _original_open(path, mode, buffering, encoding, errors, newline, closefd, opener)


builtins.open = _guarded_open
os.chdir(_SANDBOX)
print(f"Python REPL sandbox: {_SANDBOX}")
sys.stdout.flush()
PY
	printf '%s\n' "${startup_path}"
}

python_repl_wrap_query() {
	# Arguments:
	#   $1 - user-supplied Python statements (string)
	# Outputs a wrapped script that captures exceptions with exit codes.
	local raw_query wrapped # strings
	raw_query="$1"
	wrapped=$'import sys\nimport traceback\ntry:\n'

	if [[ -z "${raw_query//[[:space:]]/}" ]]; then
		wrapped+=$'    pass\n'
	else
		while IFS= read -r line; do
			wrapped+="    ${line}"$'\n'
		done <<<"${raw_query}"
	fi

	wrapped+=$'except SystemExit as exc:\n    code = exc.code if isinstance(exc.code, int) else 1\n    sys.exit(code)\n'
	wrapped+=$'except BaseException:\n    traceback.print_exc()\n    sys.exit(1)\n'

	printf '%s' "${wrapped}"
}

python_repl_resolve_query() {
	# Resolves the Python input text from TOOL_ARGS.
	local args_json text_key jq_error_file jq_error query
	text_key="$(canonical_text_arg_key)"
	args_json="${TOOL_ARGS:-}"

	if [[ -z "${args_json}" ]]; then
		printf '%s' "${TOOL_QUERY:-""}"
		return 0
	fi

	jq_error_file=$(mktemp -t python_repl_jq.XXXXXX)
	if [[ -z "${jq_error_file}" ]]; then
		log "ERROR" "Failed to create temp file for jq stderr" "${args_json}"
		return 1
	fi

	if ! query=$(jq -er --arg key "${text_key}" '
 if type != "object" then error("args must be object") end
| if .[$key]? == null then error("missing ${key}") end
| if (.[$key] | type) != "string" then error("${key} must be string") end
| if (.[$key] | length) == 0 then error("${key} cannot be empty") end
| if ((del(.[$key]) | length) != 0) then error("unexpected properties") end
| .[$key]
' <<<"${args_json}" 2>"${jq_error_file}"); then
		jq_error=$(<"${jq_error_file}")
		rm -f "${jq_error_file}"
		log "ERROR" "Invalid TOOL_ARGS for python_repl" "${jq_error}"
		return 1
	fi

	rm -f "${jq_error_file}"
	printf '%s' "${query}"
}

tool_python_repl() {
	local query sandbox_dir startup_file repl_input status text_key create_status startup_status # strings and status code
	text_key="$(canonical_text_arg_key)"

	if ! require_python3_available "python_repl tool"; then
		log "ERROR" "python_repl requires python3" "TOOL_ARGS=${TOOL_ARGS}" >&2
		return 1
	fi

	if ! query=$(python_repl_resolve_query); then
		return 1
	fi

	if [[ -z "${query}" ]]; then
		log "ERROR" "Missing TOOL_ARGS.${text_key}" "${TOOL_ARGS}"
		return 1
	fi

	sandbox_dir=$(python_repl_create_sandbox)
	create_status=$?
	if [[ ${create_status} -ne 0 ]]; then
		log "ERROR" "Failed to create sandbox" "${query}"
		return "${create_status}"
	fi

	startup_file=$(python_repl_write_startup "${sandbox_dir}")
	startup_status=$?
	if [[ ${startup_status} -ne 0 ]]; then
		log "ERROR" "Failed to write startup script" "${sandbox_dir}"
		rm -rf "${sandbox_dir}"
		return "${startup_status}"
	fi

	repl_input=$(python_repl_wrap_query "${query}")
	repl_input+=$'\n\nexit()\n'

	PYTHONSTARTUP="${startup_file}" \
		PYTHON_REPL_SANDBOX="${sandbox_dir}" \
		PYTHONNOUSERSITE=1 \
		python3 -iq <<<"${repl_input}"
	status=$?
	rm -rf "${sandbox_dir}"
	return "${status}"
}

register_python_repl() {
	local args_schema

	args_schema=$(jq -nc --arg key "$(canonical_text_arg_key)" '{"type":"object","required":[$key],"properties":{($key):{"type":"string","minLength":1}},"additionalProperties":false}')
	register_tool \
		"python_repl" \
		"Execute Python statements in a temporary sandbox via python -i." \
		"python_repl 'python code to evaluate'" \
		"Writes are confined to an ephemeral sandbox directory." \
		tool_python_repl \
		"${args_schema}"
}
