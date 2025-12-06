#!/usr/bin/env bash
#
# Entrypoint for the local MCP-inspired assistant harness.
#
# Usage:
#   ./src/main.sh [OPTIONS] -- "user query"
#
# Options:
#   -h, --help            Show help text.
#   -V, --version         Show version information.
#   -s, --supervised      Require confirmation before running tools (default).
#   -u, --unsupervised    Run tools without confirmations.
#   -m, --model PATH      Path to llama.cpp model (default: $DO_MODEL_PATH or ./models/llama.gguf).
#   -v, --verbose         Increase log verbosity (JSON logs are always structured).
#   -q, --quiet           Silence informational logs.
#
# Environment:
#   DO_MODEL_PATH   Optional override for the model path.
#   DO_SUPERVISED   Set to "false" to default to unsupervised mode.
#   DO_VERBOSITY    0 (quiet), 1 (info), 2 (debug). Overrides -v/-q when set.
#   LLAMA_BIN       llama.cpp binary (default: llama).
#
# Dependencies:
#   - bash 5+
#   - Optional: llama.cpp binary available on PATH for real scoring.
#   - Optional: fd, rg for faster search tooling.
#
# Exit codes:
#   0 on success, non-zero on argument or runtime errors.
#
set -euo pipefail

VERSION="0.1.0"
LLAMA_BIN=${LLAMA_BIN:-llama}
MODEL_PATH=${DO_MODEL_PATH:-"./models/llama.gguf"}
SUPERVISED=${DO_SUPERVISED:-true}
VERBOSITY=${DO_VERBOSITY:-1}
NOTES_DIR="${HOME}/.do"
LLAMA_AVAILABLE=false
IS_MACOS=false

# shellcheck disable=SC2034 # Readability for associative maps below.
declare -A TOOL_DESCRIPTION=()
# shellcheck disable=SC2034
declare -A TOOL_COMMAND=()
# shellcheck disable=SC2034
declare -A TOOL_SAFETY=()
# shellcheck disable=SC2034
declare -A TOOL_HANDLER=()
TOOLS=()

log() {
	# Arguments:
	#   $1 - level (string)
	#   $2 - message (string)
	#   $3 - detail (string, optional)
	local level message detail timestamp should_emit
	level="$1"
	message="$2"
	detail=${3:-""}
	timestamp="$(date -Iseconds)"
	should_emit=1

	case "${level}" in
	DEBUG)
		[[ ${VERBOSITY} -lt 2 ]] && should_emit=0
		;;
	INFO)
		[[ ${VERBOSITY} -lt 1 ]] && should_emit=0
		;;
	ERROR | WARN) ;;
	*)
		level="INFO"
		[[ ${VERBOSITY} -lt 1 ]] && should_emit=0
		;;
	esac

	if [[ ${should_emit} -eq 1 ]]; then
		printf '{"time":"%s","level":"%s","message":"%s","detail":"%s"}\n' \
			"${timestamp}" "${level}" "${message}" "${detail}"
	fi
}

show_help() {
	cat <<'USAGE'
Usage: ./src/main.sh [OPTIONS] -- "user query"

Options:
  -h, --help            Show help text.
  -V, --version         Show version information.
  -s, --supervised      Require confirmation before running tools (default).
  -u, --unsupervised    Run tools without confirmations.
  -m, --model PATH      Path to llama.cpp model (default: $DO_MODEL_PATH or ./models/llama.gguf).
  -v, --verbose         Increase log verbosity (JSON logs are always structured).
  -q, --quiet           Silence informational logs.

The script orchestrates a llama.cpp-backed planner with a registry of
machine-checkable tools (MCP-style). Provide a natural language query after
"--" to trigger planning, ranking, and execution.
USAGE
}

show_version() {
	printf 'do assistant %s\n' "${VERSION}"
}

normalize_supervised_flag() {
	case "${SUPERVISED}" in
	true | True | TRUE | 1)
		SUPERVISED=true
		;;
	false | False | FALSE | 0)
		SUPERVISED=false
		;;
	*)
		log "WARN" "Invalid DO_SUPERVISED value; defaulting to supervised" "${SUPERVISED}"
		SUPERVISED=true
		;;
	esac
}

parse_args() {
	local positional
	positional=()

	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			show_help
			exit 0
			;;
		-V | --version)
			show_version
			exit 0
			;;
		-s | --supervised)
			SUPERVISED=true
			shift
			;;
		-u | --unsupervised)
			SUPERVISED=false
			shift
			;;
		-m | --model)
			if [[ $# -lt 2 ]]; then
				log "ERROR" "--model requires a path"
				exit 1
			fi
			MODEL_PATH="$2"
			shift 2
			;;
		-v | --verbose)
			VERBOSITY=2
			shift
			;;
		-q | --quiet)
			VERBOSITY=0
			shift
			;;
		--)
			shift
			break
			;;
		-*)
			log "ERROR" "Unknown option" "$1"
			exit 1
			;;
		*)
			positional+=("$1")
			shift
			;;
		esac
	done

	if [[ ${#positional[@]} -gt 0 ]]; then
		USER_QUERY="${positional[*]}"
	else
		USER_QUERY="$*"
	fi

	if [[ -z "${USER_QUERY:-}" ]]; then
		log "ERROR" "A user query is required. See --help for usage."
		exit 1
	fi
}

init_environment() {
	normalize_supervised_flag
	if command -v uname >/dev/null 2>&1 && [[ "$(uname -s)" == "Darwin" ]]; then
		IS_MACOS=true
	fi

	if command -v "${LLAMA_BIN}" >/dev/null 2>&1; then
		LLAMA_AVAILABLE=true
	else
		log "WARN" "llama.cpp binary not found; using heuristic fallback" "${LLAMA_BIN}"
	fi

	mkdir -p "${NOTES_DIR}"
}

register_tool() {
	# Arguments:
	#   $1 - name
	#   $2 - description
	#   $3 - invocation command (string)
	#   $4 - safety notes
	#   $5 - handler function name
	if [[ $# -lt 5 ]]; then
		log "ERROR" "register_tool requires five arguments" "$*"
		return 1
	fi
	local name
	name="$1"
	TOOLS+=("${name}")
	TOOL_DESCRIPTION["${name}"]="$2"
	TOOL_COMMAND["${name}"]="$3"
	TOOL_SAFETY["${name}"]="$4"
	TOOL_HANDLER["${name}"]="${5:-}"
}

tool_os_nav() {
	log "INFO" "Running OS navigation" "Listing working directory"
	pwd
	ls -la
}

tool_file_search() {
	local query
	query=${TOOL_QUERY:-""}
	log "INFO" "Searching files" "${query}"

	if command -v fd >/dev/null 2>&1; then
		fd --hidden --color=never --max-depth 5 "${query:-.}" . || true
	else
		find . -maxdepth 5 -iname "*${query}*" || true
	fi

	if command -v rg >/dev/null 2>&1 && [[ -n "${query}" ]]; then
		rg --line-number --hidden --color=never "${query}" || true
	fi
}

tool_notes() {
	local query note_file
	query=${TOOL_QUERY:-""}
	note_file="${NOTES_DIR}/notes.txt"
	log "INFO" "Appending reminder" "${query}"
	printf '%s\t%s\n' "$(date -Iseconds)" "${query}" >>"${note_file}"
	printf 'Saved note to %s\n' "${note_file}"
}

tool_mail_stub() {
	local query
	query=${TOOL_QUERY:-""}
	log "INFO" "Mail stub invoked" "${query}"
	printf 'Mail delivery not configured. Draft preserved for review: %s\n' "${query}"
}

tool_applescript() {
	local query
	query=${TOOL_QUERY:-""}
	if [[ "${IS_MACOS}" != true ]]; then
		log "WARN" "AppleScript not available on this platform" "${query}"
		return 0
	fi

	if ! command -v osascript >/dev/null 2>&1; then
		log "WARN" "osascript missing; cannot execute AppleScript" "${query}"
		return 0
	fi

	log "INFO" "Executing AppleScript" "${query}"
	osascript -e "${query}"
}

initialize_tools() {
	register_tool \
		"os_nav" \
		"Inspect the current working directory contents." \
		"pwd && ls -la" \
		"Read-only visibility of local filesystem." \
		tool_os_nav

	register_tool \
		"file_search" \
		"Search project files by name and content using fd/rg." \
		"fd or find combined with ripgrep." \
		"May read many files; avoid leaking secrets." \
		tool_file_search

	register_tool \
		"notes" \
		"Persist reminders or notes under ~/.do for future runs." \
		"printf '<note>' >> ~/.do/notes.txt" \
		"Stores user-provided text locally; confirm contents." \
		tool_notes

	register_tool \
		"mail_stub" \
		"Prepare an email draft for later delivery." \
		"cat > /tmp/mcp_mail_draft.txt" \
		"Does not send mail; safe placeholder." \
		tool_mail_stub

	register_tool \
		"applescript" \
		"Execute AppleScript snippets on macOS." \
		"osascript -e '<script>'" \
		"Only available on macOS; disabled elsewhere." \
		tool_applescript
}

build_scoring_prompt() {
	local tool_name tool_desc user_query
	tool_name="$1"
	tool_desc="$2"
	user_query="$3"
	cat <<"PROMPT"
You are ranking a tool for a request. Return a single integer from 0-5
where 5 means the tool is ideal.
PROMPT
	printf 'Request: %s\nTool: %s\nDescription: %s\nScore: ' "${user_query}" "${tool_name}" "${tool_desc}"
}

score_tool_with_model() {
	local tool_name tool_desc user_query prompt score raw
	tool_name="$1"
	tool_desc="$2"
	user_query="$3"
	prompt="$(build_scoring_prompt "${tool_name}" "${tool_desc}" "${user_query}")"

	if [[ "${LLAMA_AVAILABLE}" == true ]]; then
		raw="$(${LLAMA_BIN} -m "${MODEL_PATH}" -p "${prompt}" 2>/dev/null || true)"
		score="$(printf '%s' "${raw}" | grep -Eo '[0-5]' | head -n1 || true)"
	else
		# Lightweight heuristic fallback: keyword overlap.
		score=0
		if [[ "${user_query}" == *"${tool_name}"* ]]; then
			score=4
		elif [[ "${tool_desc}" == *"${user_query}"* ]]; then
			score=3
		elif printf '%s' "${tool_desc}" | grep -iq "${user_query}"; then
			score=2
		fi
	fi

	if [[ -z "${score}" ]]; then
		score=1
	fi

	printf '%s' "${score}"
}

rank_tools() {
	local user_query tool score
	user_query="$1"
	local scores
	scores=()

	for tool in "${TOOLS[@]}"; do
		score="$(score_tool_with_model "${tool}" "${TOOL_DESCRIPTION[${tool}]}" "${user_query}")"
		scores+=("${score}:${tool}")
	done

	printf '%s\n' "${scores[@]}" | sort -r -n -t ':' -k1,1 | head -n 3
}

generate_tool_prompt() {
	local user_query ranked entry score tool prompt
	user_query="$1"
	ranked="$(rank_tools "${user_query}")"
	prompt="User request: ${user_query}. Suggested tools:"
	while IFS= read -r entry; do
		score="${entry%%:*}"
		tool="${entry##*:}"
		prompt+=$(printf ' %s(score=%s,desc=%s,safety=%s,cmd=%s),' \
			"${tool}" "${score}" "${TOOL_DESCRIPTION[${tool}]}" "${TOOL_SAFETY[${tool}]}" "${TOOL_COMMAND[${tool}]}")
	done <<<"${ranked}"
	printf '%s\n' "${prompt%,}"
}

confirm_tool() {
	local tool_name
	tool_name="$1"
	if [[ "${SUPERVISED}" != true ]]; then
		return 0
	fi

	printf 'Execute tool "%s"? [y/N]: ' "${tool_name}" >&2
	read -r reply
	if [[ "${reply}" != "y" && "${reply}" != "Y" ]]; then
		log "WARN" "Tool execution declined" "${tool_name}"
		return 1
	fi
	return 0
}

execute_tool() {
	local tool_name handler
	tool_name="$1"
	handler="${TOOL_HANDLER[${tool_name}]}"
	if [[ -z "${handler}" ]]; then
		log "ERROR" "No handler registered for tool" "${tool_name}"
		return 1
	fi

	if ! confirm_tool "${tool_name}"; then
		return 0
	fi

	TOOL_QUERY="${USER_QUERY}" ${handler}
}

collect_plan() {
	local ranked plan_prompt raw_plan
	ranked="$(rank_tools "${USER_QUERY}")"
	plan_prompt="Plan a concise sequence of tool uses to satisfy: ${USER_QUERY}. Candidates: ${ranked}."
	if [[ "${LLAMA_AVAILABLE}" == true ]]; then
		raw_plan="$(${LLAMA_BIN} -m "${MODEL_PATH}" -p "${plan_prompt}" 2>/dev/null || true)"
	else
		raw_plan="Use top-ranked tools sequentially: ${ranked}."
	fi
	printf '%s\n' "${raw_plan}"
}

planner_executor_loop() {
	local plan ranked entry tool summary
	ranked="$(rank_tools "${USER_QUERY}")"
	plan="$(collect_plan)"
	log "INFO" "Generated plan" "${plan}"

	summary=""
	while IFS= read -r entry; do
		tool="${entry##*:}"
		if execute_tool "${tool}"; then
			summary+=$(printf '[%s executed] ' "${tool}")
		else
			summary+=$(printf '[%s skipped] ' "${tool}")
		fi
	done <<<"${ranked}"

	log "INFO" "Execution summary" "${summary}"
	printf '%s\n' "${summary}"
}

main() {
	parse_args "$@"
	init_environment
	initialize_tools
	log "DEBUG" "Starting tool selection" "${USER_QUERY}"
	printf '%s\n' "$(generate_tool_prompt "${USER_QUERY}")"
	planner_executor_loop
}

main "$@"
