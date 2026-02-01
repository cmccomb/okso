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

# shellcheck source=src/lib/core/logging.sh
source "${BASH_SOURCE[0]%/tools/python_repl/index.sh}/lib/core/logging.sh"
# shellcheck source=src/tools/registry.sh
source "${BASH_SOURCE[0]%/python_repl/index.sh}/registry.sh"

python_repl_create_sandbox() {
	# Outputs the sandbox path.
	# Returns:
	#   Outputs the sandbox directory path (string).

	local sandbox_dir
	sandbox_dir=$(mktemp -d "${TMPDIR:-/tmp}/python_repl.XXXXXX") || return 1
	printf '%s\n' "${sandbox_dir}"
}

python_repl_sandbox_path_file() {
	# Outputs the sandbox path tracking file.
	# Returns:
	#   Outputs the sandbox path file (string).
	printf '%s\n' "${TMPDIR:-/tmp}/python_repl_sandbox_path"
}

python_repl_get_sandbox() {
	# Outputs the sandbox path, reusing an existing one if present.
	# Returns:
	#   Outputs the sandbox directory path (string).
	#   Exit code 0 on success, non-zero on failure.
	local sandbox_file existing_sandbox sandbox_dir

	# Check for existing sandbox
	sandbox_file="$(python_repl_sandbox_path_file)"

	# Reuse existing sandbox if valid
	if [[ -s "${sandbox_file}" ]]; then
		existing_sandbox="$(<"${sandbox_file}")"
		if [[ -d "${existing_sandbox}" ]]; then
			printf '%s\n' "${existing_sandbox}"
			return 0
		fi

		rm -f "${sandbox_file}"
	fi

	# Create new sandbox
	sandbox_dir=$(python_repl_create_sandbox)
	if [[ -z "${sandbox_dir}" ]]; then
		return 1
	fi

	# Track the new sandbox path
	if ! printf '%s' "${sandbox_dir}" >"${sandbox_file}"; then
		rm -rf "${sandbox_dir}"
		return 1
	fi

	printf '%s\n' "${sandbox_dir}"
}

python_repl_write_startup() {
	# Writes the Python REPL startup script enforcing sandboxed file access.
	# Arguments:
	#   $1 - sandbox directory (string)
	# Returns:
	#   Outputs the startup script path.
	local sandbox_dir startup_path
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
	#   $1 - user-supplied Python statements (string) (unused; kept for compatibility)
	# Outputs a wrapped script that captures exceptions with exit codes and persists state.
	cat <<'PY'
import builtins
import os
import pathlib
import pickle
import sys
import traceback

STARTUP_PATH = os.environ.get("PYTHON_REPL_STARTUP")
if STARTUP_PATH:
    with open(STARTUP_PATH, "r", encoding="utf-8") as startup_handle:
        startup_code = startup_handle.read()
    exec(compile(startup_code, STARTUP_PATH, "exec"), globals())

_SANDBOX = pathlib.Path(os.environ["PYTHON_REPL_SANDBOX"]).resolve()
_STATE_FILE = pathlib.Path(os.environ.get("PYTHON_REPL_STATE_FILE", _SANDBOX / ".python_state.pkl"))
IGNORED_STATE_KEYS = {"__builtins__", "__name__", "__package__", "__loader__", "__spec__", "__annotations__", "__cached__"}


def _load_state():
    state = {"__builtins__": builtins.__dict__}
    if _STATE_FILE.exists():
        try:
            with _STATE_FILE.open("rb") as handle:
                loaded = pickle.load(handle)
            if isinstance(loaded, dict):
                state.update(loaded)
        except Exception as exc:  # noqa: BLE001
            print(f"Failed to load previous Python REPL state: {exc}", file=sys.stderr)
    return state


def _save_state(state):
    persisted = {}
    for key, value in state.items():
        if key in IGNORED_STATE_KEYS:
            continue
        try:
            pickle.dumps(value)
        except Exception:  # noqa: BLE001
            continue
        persisted[key] = value

    try:
        with _STATE_FILE.open("wb") as handle:
            pickle.dump(persisted, handle)
    except Exception as exc:  # noqa: BLE001
        print(f"Failed to persist Python REPL state: {exc}", file=sys.stderr)


STATE = _load_state()
USER_CODE = os.environ.get("PYTHON_REPL_INPUT", "")
if not USER_CODE.strip():
    USER_CODE = "pass"

try:
    exec(compile(USER_CODE, "<input>", "exec"), STATE, STATE)
except SystemExit as exc:
    code = exc.code if isinstance(exc.code, int) else 1
    sys.exit(code)
except BaseException:  # noqa: BLE001
    traceback.print_exc()
    sys.exit(1)
else:
    _save_state(STATE)
PY
}

python_repl_resolve_query() {
	# Resolves the Python input text from TOOL_ARGS.
	# Returns:
	#   Outputs the Python statements (string).
	local args_json text_key jq_error_file jq_error query
	text_key="input"
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
	# Executes Python statements in an isolated REPL sandbox.
	# Returns:
	#   Exit code 0 on success, non-zero on failure.

	local query sandbox_dir startup_file repl_input status text_key create_status startup_status # strings and status code

	# Resolve input query
	text_key="input"

	# Get the Python statements to execute
	if ! query=$(python_repl_resolve_query); then
		return 1
	fi

	# Validate query presence
	if [[ -z "${query}" ]]; then
		log "ERROR" "Missing TOOL_ARGS.${text_key}" "${TOOL_ARGS}"
		return 1
	fi

	# Create or reuse sandbox
	sandbox_dir=$(python_repl_get_sandbox)
	create_status=$?
	if [[ ${create_status} -ne 0 ]]; then
		log "ERROR" "Failed to create sandbox" "${query}"
		return "${create_status}"
	fi

	# Write startup script
	startup_file=$(python_repl_write_startup "${sandbox_dir}")
	startup_status=$?
	if [[ ${startup_status} -ne 0 ]]; then
		log "ERROR" "Failed to write startup script" "${sandbox_dir}"
		rm -rf "${sandbox_dir}"
		return "${startup_status}"
	fi

	# Prepare REPL input
	repl_input=$(python_repl_wrap_query "${query}")
	repl_input+=$'\n\nexit()\n'

	PYTHON_REPL_STARTUP="${startup_file}" \
		PYTHON_REPL_SANDBOX="${sandbox_dir}" \
		PYTHON_REPL_STATE_FILE="${sandbox_dir}/.python_state.pkl" \
		PYTHON_REPL_INPUT="${query}" \
		PYTHONNOUSERSITE=1 \
		python3.12 -I <<<"${repl_input}"
	status=$?
	return "${status}"
}

register_python_repl() {
	# Registers the python_repl tool.
	# Returns:
	#   Exit code 0 on success, non-zero on failure.
	local args_schema

	# Define the arguments schema
	args_schema=$(
		cat <<'JSON'
{
  "type": "object",
  "required": ["input"],
  "properties": {
    "input": {
      "type": "string",
      "minLength": 1
    }
  }
}
JSON
	)
	register_tool \
		"python_repl" \
		"Execute Python statements in a temporary sandbox. However, you MUST use print statements to view outputs." \
		tool_python_repl \
		"${args_schema}"
}
