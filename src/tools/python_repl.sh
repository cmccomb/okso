#!/usr/bin/env bash
# shellcheck shell=bash
#
# Restricted Python REPL tool using an isolated sandbox directory.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/python_repl.sh}/tools/python_repl.sh"
#
# Environment variables:
#   TOOL_ARGS (json): structured arguments containing the canonical text key with Python statements.
#   TOOL_QUERY (string): Python statements executed in the REPL session (deprecated; falls back when TOOL_ARGS is empty).
#
# Dependencies:
#   - bash 5+
#   - python 3+
#   - mktemp
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero when sandbox creation or interpreter startup fails.

# shellcheck source=../lib/core/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/python_repl.sh}/lib/core/logging.sh"
# shellcheck source=./registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/python_repl.sh}/registry.sh"

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
	# Resolves the Python input text from TOOL_ARGS or TOOL_QUERY (deprecated).
	local text_key query
	text_key="$(canonical_text_arg_key)"
	query=$(jq -er --arg key "${text_key}" 'if type == "object" then .[$key] // empty else empty end' <<<"${TOOL_ARGS:-{}}" 2>/dev/null || true)

	if [[ -z "${query}" ]]; then
		query=${TOOL_QUERY:-""}
	fi

	printf '%s' "${query}"
}

tool_python_repl() {
	local query sandbox_dir startup_file repl_input status # strings and status code
	query="$(python_repl_resolve_query)"

	sandbox_dir=$(python_repl_create_sandbox) || {
		log "ERROR" "Failed to create sandbox" "${query}" || true
		return 1
	}

	startup_file=$(python_repl_write_startup "${sandbox_dir}") || {
		log "ERROR" "Failed to write startup script" "${sandbox_dir}" || true
		rm -rf "${sandbox_dir}"
		return 1
	}

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
