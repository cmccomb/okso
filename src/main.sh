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
#   -y, --yes, --no-confirm
#                         Approve all tool runs without prompting.
#       --confirm         Always prompt before running tools.
#       --dry-run         Print the planned tool calls without running them.
#       --plan-only       Emit the planned calls as JSON and exit.
#   -m, --model VALUE     HF repo[:file] for llama.cpp download (default: Qwen/Qwen3-1.5B-Instruct-GGUF:qwen3-1.5b-instruct-q4_k_m.gguf).
#       --model-branch BRANCH  HF branch or tag for the model download.
#       --model-cache DIR      Directory that stores downloaded models (default: ~/.do/models).
#       --config FILE     Config file to load (default: ${XDG_CONFIG_HOME:-$HOME/.config}/do/config.env).
#   -v, --verbose         Increase log verbosity (JSON logs are always structured).
#   -q, --quiet           Silence informational logs.
#
# Environment:
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
DEFAULT_MODEL_FILE="qwen3-1.5b-instruct-q4_k_m.gguf"
CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/do"
CONFIG_FILE="${CONFIG_DIR}/config.env"
MODEL_SPEC="Qwen/Qwen3-1.5B-Instruct-GGUF:${DEFAULT_MODEL_FILE}"
MODEL_BRANCH="main"
MODEL_CACHE="${HOME}/.do/models"
MODEL_PATH=""
APPROVE_ALL=false
FORCE_CONFIRM=false
DRY_RUN=false
PLAN_ONLY=false
VERBOSITY=1
NOTES_DIR="${HOME}/.do"
LLAMA_AVAILABLE=false
IS_MACOS=false
COMMAND="run"
USER_QUERY=""

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
  -y, --yes, --no-confirm
                        Approve all tool runs without prompting.
      --confirm         Always prompt before running tools.
      --dry-run         Print the planned tool calls without running them.
      --plan-only       Emit the planned calls as JSON and exit (implies --dry-run).
  -m, --model VALUE     HF repo[:file] for llama.cpp (default: Qwen/Qwen3-1.5B-Instruct-GGUF:qwen3-1.5b-instruct-q4_k_m.gguf).
      --model-branch BRANCH  HF branch or tag (default: main).
      --model-cache DIR      Cache directory for GGUF downloads (default: ~/.do/models).
      --config FILE     Config file to load or create (default: ${XDG_CONFIG_HOME:-$HOME/.config}/do/config.env).
  -v, --verbose         Increase log verbosity (JSON logs are always structured).
  -q, --quiet           Silence informational logs.

The script orchestrates a llama.cpp-backed planner with a registry of
machine-checkable tools (MCP-style). Provide a natural language query after
"--" to trigger planning, ranking, and execution.

Use "./src/main.sh init" with the same options to write a config file without
running a query. The config file stores model defaults and approval behavior
for future runs.
USAGE
}

show_version() {
	printf 'do assistant %s\n' "${VERSION}"
}

json_escape() {
	# Arguments:
	#   $1 - raw string
	local raw escaped
	raw="$1"
	escaped="${raw//\\/\\\\}"
	escaped="${escaped//"/\\"/}"
	escaped="${escaped//$'\n'/\\n}"
	printf '%s' "${escaped}"
}

detect_config_file() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--config)
			if [[ $# -lt 2 ]]; then
				log "ERROR" "--config requires a path"
				exit 1
			fi
			CONFIG_FILE="$2"
			shift 2
			;;
		--config=*)
			CONFIG_FILE="${1#*=}"
			shift
			;;
		*)
			shift
			;;
		esac
	done
}

load_config() {
	if [[ -f "${CONFIG_FILE}" ]]; then
		# shellcheck source=/dev/null
		source "${CONFIG_FILE}"
	fi

	MODEL_SPEC=${MODEL_SPEC:-"Qwen/Qwen3-1.5B-Instruct-GGUF:${DEFAULT_MODEL_FILE}"}
	MODEL_BRANCH=${MODEL_BRANCH:-main}
	MODEL_CACHE=${MODEL_CACHE:-"${HOME}/.do/models"}
	VERBOSITY=${VERBOSITY:-1}
	APPROVE_ALL=${APPROVE_ALL:-false}
	FORCE_CONFIRM=${FORCE_CONFIRM:-false}

	if [[ -n "${DO_MODEL:-}" ]]; then
		MODEL_SPEC="${DO_MODEL}"
	fi
	if [[ -n "${DO_MODEL_BRANCH:-}" ]]; then
		MODEL_BRANCH="${DO_MODEL_BRANCH}"
	fi
	if [[ -n "${DO_MODEL_CACHE:-}" ]]; then
		MODEL_CACHE="${DO_MODEL_CACHE}"
	fi
	if [[ -n "${DO_SUPERVISED:-}" ]]; then
		case "${DO_SUPERVISED}" in
		false | False | FALSE | 0)
			APPROVE_ALL=true
			;;
		*)
			APPROVE_ALL=false
			;;
		esac
	fi
	if [[ -n "${DO_VERBOSITY:-}" ]]; then
		VERBOSITY="${DO_VERBOSITY}"
	fi
}

write_config_file() {
	mkdir -p "$(dirname "${CONFIG_FILE}")"
	cat >"${CONFIG_FILE}" <<EOF
MODEL_SPEC="${MODEL_SPEC}"
MODEL_BRANCH="${MODEL_BRANCH}"
MODEL_CACHE="${MODEL_CACHE}"
VERBOSITY=${VERBOSITY}
APPROVE_ALL=${APPROVE_ALL}
FORCE_CONFIRM=${FORCE_CONFIRM}
EOF
	printf 'Wrote config to %s\n' "${CONFIG_FILE}"
}

parse_model_spec() {
	# Arguments:
	#   $1 - model spec repo[:file]
	#   $2 - default file fallback
	local spec default_file repo file
	spec="$1"
	default_file="$2"

	if [[ "${spec}" == *:* ]]; then
		repo="${spec%%:*}"
		file="${spec#*:}"
	else
		repo="${spec}"
		file="${default_file}"
	fi

	printf '%s\n%s\n' "${repo}" "${file}"
}

normalize_approval_flags() {
	case "${APPROVE_ALL}" in
	true | True | TRUE | 1)
		APPROVE_ALL=true
		;;
	false | False | FALSE | 0)
		APPROVE_ALL=false
		;;
	*)
		log "WARN" "Invalid approval flag; defaulting to prompts" "${APPROVE_ALL}"
		APPROVE_ALL=false
		;;
	esac

	case "${FORCE_CONFIRM}" in
	true | True | TRUE | 1)
		FORCE_CONFIRM=true
		;;
	false | False | FALSE | 0)
		FORCE_CONFIRM=false
		;;
	*)
		log "WARN" "Invalid confirm flag; defaulting to prompts" "${FORCE_CONFIRM}"
		FORCE_CONFIRM=false
		;;
	esac
}

resolve_model_path() {
	# Derives the cached GGUF path from the HF model spec and validates presence.
	local model_parts model_repo model_file
	mapfile -t model_parts < <(parse_model_spec "${MODEL_SPEC}" "${DEFAULT_MODEL_FILE}")
	model_repo="${model_parts[0]}"
	model_file="${model_parts[1]}"
	MODEL_PATH="${MODEL_CACHE%/}/${model_file}"

	if [[ ! -f "${MODEL_PATH}" ]]; then
		log "ERROR" "Model is missing" "Download via scripts/install --model ${model_repo}:${model_file} --model-branch ${MODEL_BRANCH} --model-cache ${MODEL_CACHE}"
		exit 1
	fi
}

parse_args() {
	local positional
	positional=()

	while [[ $# -gt 0 ]]; do
		case "$1" in
		init | configure)
			COMMAND="init"
			shift
			;;
		-h | --help)
			show_help
			exit 0
			;;
		-V | --version)
			show_version
			exit 0
			;;
		-y | --yes | --no-confirm)
			APPROVE_ALL=true
			FORCE_CONFIRM=false
			shift
			;;
		--confirm)
			FORCE_CONFIRM=true
			APPROVE_ALL=false
			shift
			;;
		--dry-run)
			DRY_RUN=true
			shift
			;;
		--plan-only)
			PLAN_ONLY=true
			DRY_RUN=true
			shift
			;;
		-m | --model)
			if [[ $# -lt 2 ]]; then
				log "ERROR" "--model requires an HF repo[:file] value"
				exit 1
			fi
			MODEL_SPEC="$2"
			shift 2
			;;
		--model-branch)
			if [[ $# -lt 2 ]]; then
				log "ERROR" "--model-branch requires a value"
				exit 1
			fi
			MODEL_BRANCH="$2"
			shift 2
			;;
		--model-cache)
			if [[ $# -lt 2 ]]; then
				log "ERROR" "--model-cache requires a directory"
				exit 1
			fi
			MODEL_CACHE="$2"
			shift 2
			;;
		--config)
			if [[ $# -lt 2 ]]; then
				log "ERROR" "--config requires a path"
				exit 1
			fi
			CONFIG_FILE="$2"
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

	if [[ "${COMMAND}" == "run" && -z "${USER_QUERY:-}" ]]; then
		log "ERROR" "A user query is required. See --help for usage."
		exit 1
	fi
}

init_environment() {
	normalize_approval_flags
	resolve_model_path
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

build_ranking_prompt() {
	local user_query prompt tool
	user_query="$1"
	prompt="You are selecting tools to execute for a request. Respond with only the tools needed as lines in the format: tool=<name> score=<0-5> reason=<short justification>. Do not invent tools.\nRequest: ${user_query}\nAvailable tools:"

	for tool in "${TOOLS[@]}"; do
		prompt+=$(
			printf '\n- name=%s desc=%s safety=%s command=%s' \
				"${tool}" "${TOOL_DESCRIPTION[${tool}]}" "${TOOL_SAFETY[${tool}]}" "${TOOL_COMMAND[${tool}]}"
		)
	done

	printf '%s\n' "${prompt}"
}

parse_llama_ranking() {
	local raw_line tool score raw
	raw="$1"
	local results
	declare -A best_scores=()
	results=()

	while IFS= read -r raw_line; do
		if [[ "${raw_line}" =~ tool[=:\ ]*([a-zA-Z0-9_-]+)[[:space:]]+score[=:\ ]*([0-5]) ]]; then
			tool="${BASH_REMATCH[1]}"
			score="${BASH_REMATCH[2]}"
			if [[ -n "${TOOL_DESCRIPTION[${tool}]:-}" ]]; then
				if [[ -z "${best_scores[${tool}]:-}" || ${score} -gt ${best_scores[${tool}]} ]]; then
					best_scores[${tool}]="${score}"
				fi
			fi
		fi
	done <<<"${raw}"

	for tool in "${!best_scores[@]}"; do
		results+=("${best_scores[${tool}]}:${tool}")
	done

	if [[ ${#results[@]} -eq 0 ]]; then
		return 1
	fi

	printf '%s\n' "${results[@]}" | sort -r -n -t ':' -k1,1 | head -n 3
}

heuristic_rank_tools() {
	local user_query tool desc score
	user_query="$1"
	local scores
	scores=()

	for tool in "${TOOLS[@]}"; do
		desc="${TOOL_DESCRIPTION[${tool}]}"
		score=1
		if [[ "${user_query,,}" == *"${tool,,}"* ]]; then
			score=5
		elif [[ "${desc,,}" == *"${user_query,,}"* ]]; then
			score=4
		elif printf '%s' "${desc}" | grep -iq "${user_query}"; then
			score=3
		elif [[ "${TOOL_COMMAND[${tool}]}" == *"${user_query}"* ]]; then
			score=2
		fi
		scores+=("${score}:${tool}")
	done

	printf '%s\n' "${scores[@]}" | sort -r -n -t ':' -k1,1 | head -n 3
}

rank_tools() {
	local user_query prompt raw parsed
	user_query="$1"
	prompt="$(build_ranking_prompt "${user_query}")"

	if [[ "${LLAMA_AVAILABLE}" == true ]]; then
		raw="$(${LLAMA_BIN} -m "${MODEL_PATH}" -p "${prompt}" 2>/dev/null || true)"
		parsed="$(parse_llama_ranking "${raw}" || true)"
	fi

	if [[ -z "${parsed:-""}" ]]; then
		parsed="$(heuristic_rank_tools "${user_query}")"
	fi

	printf '%s\n' "${parsed}"
}

generate_tool_prompt() {
	local user_query ranked entry score tool prompt
	user_query="$1"
	ranked="$2"
	prompt="User request: ${user_query}. Suggested tools:"
	while IFS= read -r entry; do
		score="${entry%%:*}"
		tool="${entry##*:}"
		prompt+=$(
			printf ' %s(score=%s,desc=%s,safety=%s,cmd=%s),' \
				"${tool}" "${score}" "${TOOL_DESCRIPTION[${tool}]}" "${TOOL_SAFETY[${tool}]}" "${TOOL_COMMAND[${tool}]}"
		)
	done <<<"${ranked}"
	printf '%s\n' "${prompt%,}"
}

emit_plan_json() {
	local ranked entry score tool first description command safety
	ranked="$1"
	first=true

	printf '['
	while IFS= read -r entry; do
		[[ -z "${entry}" ]] && continue
		score="${entry%%:*}"
		tool="${entry##*:}"
		description="$(json_escape "${TOOL_DESCRIPTION[${tool}]}")"
		command="$(json_escape "${TOOL_COMMAND[${tool}]}")"
		safety="$(json_escape "${TOOL_SAFETY[${tool}]}")"
		if [[ "${first}" != true ]]; then
			printf ','
		fi
		printf '{"tool":"%s","score":%s,"command":"%s","description":"%s","safety":"%s"}' \
			"$(json_escape "${tool}")" "${score:-0}" "${command}" "${description}" "${safety}"
		first=false
	done <<<"${ranked}"
	printf ']\n'
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
	local tool_name
	tool_name="$1"
	if ! should_prompt_for_tool; then
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
		return 1
	fi

	if [[ "${DRY_RUN}" == true || "${PLAN_ONLY}" == true ]]; then
		log "INFO" "Skipping execution in preview mode" "${tool_name}"
		return 0
	fi

	TOOL_QUERY="${USER_QUERY}" ${handler}
}

collect_plan() {
	local ranked plan_prompt raw_plan
	ranked="$1"
	plan_prompt="Plan a concise sequence of tool uses to satisfy: ${USER_QUERY}. Candidates: ${ranked}."
	if [[ "${LLAMA_AVAILABLE}" == true ]]; then
		raw_plan="$(${LLAMA_BIN} -m "${MODEL_PATH}" -p "${plan_prompt}" 2>/dev/null || true)"
	else
		raw_plan="Use top-ranked tools sequentially: ${ranked}."
	fi
	printf '%s\n' "${raw_plan}"
}

planner_executor_loop() {
	local plan ranked entry tool summary plan_json
	ranked="$1"
	plan="$(collect_plan "${ranked}")"
	plan_json="$(emit_plan_json "${ranked}")"
	log "INFO" "Generated plan" "${plan}"

	if [[ "${PLAN_ONLY}" == true ]]; then
		printf '%s\n' "${plan_json}"
		return 0
	fi

	if [[ "${DRY_RUN}" == true ]]; then
		printf 'Dry run: planned tool calls (no execution).\n'
		printf '%s\n' "${plan_json}"
		return 0
	fi

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
	local ranked_tools
	detect_config_file "$@"
	load_config
	parse_args "$@"

	normalize_approval_flags

	if [[ "${COMMAND}" == "init" ]]; then
		write_config_file
		return 0
	fi

	init_environment
	initialize_tools
	log "DEBUG" "Starting tool selection" "${USER_QUERY}"
	ranked_tools="$(rank_tools "${USER_QUERY}")"
	printf '%s\n' "$(generate_tool_prompt "${USER_QUERY}" "${ranked_tools}")"
	planner_executor_loop "${ranked_tools}"
}

main "$@"
