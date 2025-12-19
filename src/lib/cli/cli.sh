#!/usr/bin/env bash
# shellcheck shell=bash
#
# CLI-facing helpers for the okso assistant.
#
# Usage:
#   source "${BASH_SOURCE[0]%/cli.sh}/cli.sh"
#
# Environment variables:
#   COMMAND (string): operational mode, defaults to run.
#   USER_QUERY (string): captured user input after options parsing.
#
# Dependencies:
#   - bash 5+
#   - gum (optional, for styled help output)
#
# Exit codes:
#   0 for help/version responses; 1 for argument errors.

CLI_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=../core/logging.sh disable=SC1091
source "${CLI_LIB_DIR}/../core/logging.sh"

build_usage_text() {
	local default_model_spec default_model_branch entrypoint_display default_planner_spec default_planner_branch default_react_spec default_react_branch
	default_model_spec="${DEFAULT_MODEL_SPEC_BASE:-bartowski/Qwen_Qwen3-1.7B-GGUF:Qwen_Qwen3-1.7B-Q4_K_M.gguf}"
	default_model_branch="${DEFAULT_MODEL_BRANCH_BASE:-main}"
	default_planner_spec="${DEFAULT_PLANNER_MODEL_SPEC_BASE:-bartowski/Qwen_Qwen3-8B-GGUF:Qwen_Qwen3-8B-Q4_K_M.gguf}"
	default_planner_branch="${DEFAULT_PLANNER_MODEL_BRANCH_BASE:-main}"
	default_react_spec="${DEFAULT_REACT_MODEL_SPEC_BASE:-${default_model_spec}}"
	default_react_branch="${DEFAULT_REACT_MODEL_BRANCH_BASE:-${default_model_branch}}"
	entrypoint_display="${OKSO_ENTRYPOINT:-./src/bin/okso}"

	cat <<USAGE
Usage: ${entrypoint_display} [OPTIONS] -- "user query"

Options:
  -h, --help            Show help text.
  -V, --version         Show version information.
  -y, --yes, --no-confirm
                        Approve all tool runs without prompting.
      --confirm         Always prompt before running tools.
      --dry-run         Print the planned tool calls without running them.
      --plan-only       Emit the planned calls as JSON and exit (implies --dry-run).
  -m, --model VALUE     HF repo[:file] used for both planner and ReAct models when specific flags are not set (default: ${default_model_spec}).
      --model-branch BRANCH
                        HF branch or tag for the shared model download (default: ${default_model_branch}).
      --planner-model VALUE
                        HF repo[:file] for planning llama.cpp calls (default: ${default_planner_spec}).
      --planner-model-branch BRANCH
                        HF branch or tag for the planning model download (default: ${default_planner_branch}).
      --react-model VALUE
                        HF repo[:file] for ReAct llama.cpp calls (default: ${default_react_spec}).
      --react-model-branch BRANCH
                        HF branch or tag for the ReAct model download (default: ${default_react_branch}).
      --config FILE     Config file to load or create (default: ${XDG_CONFIG_HOME:-$HOME/.config}/okso/config.env).
  -v, --verbose         Increase log verbosity (JSON logs are always structured).
  -q, --quiet           Silence informational logs.

The script orchestrates a llama.cpp-backed planner with a registry of
machine-checkable tools. Provide a natural language query after
"--" to trigger planning, ranking, and execution.

Use "${entrypoint_display} init" with the same options to write a config file without
running a query. The config file stores model defaults and approval behavior
for future runs.
USAGE
}

render_usage() {
	local usage_text
	usage_text="$(build_usage_text)"

	if command -v gum >/dev/null 2>&1; then
		# gum formatting keeps help text readable when available but the
		# plain fallback ensures portability.
		printf '%s\n' "${usage_text}" | gum format
		return
	fi

	printf '%s\n' "${usage_text}"
}

show_help() {
	render_usage
}

show_version() {
	printf 'okso assistant %s\n' "${VERSION}"
}

# shellcheck disable=SC2034
parse_args() {
	local positional
	positional=()
	local planner_model_spec_set react_model_spec_set planner_model_branch_set react_model_branch_set
	planner_model_spec_set=false
	react_model_spec_set=false
	planner_model_branch_set=false
	react_model_branch_set=false

	while [[ $# -gt 0 ]]; do
		case "$1" in
		init | configure)
			# Accept both verbs for parity with hosted setup flows.
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
			# plan-only always implies dry-run so we avoid running tools.
			PLAN_ONLY=true
			DRY_RUN=true
			shift
			;;
		-m | --model)
			if [[ $# -lt 2 ]]; then
				die "cli" "usage" "--model requires an HF repo[:file] value"
			fi
			if [[ "${planner_model_spec_set}" != true ]]; then
				PLANNER_MODEL_SPEC="$2"
			fi
			if [[ "${react_model_spec_set}" != true ]]; then
				REACT_MODEL_SPEC="$2"
			fi
			shift 2
			;;
		--model-branch)
			if [[ $# -lt 2 ]]; then
				die "cli" "usage" "--model-branch requires a branch or tag"
			fi
			if [[ "${planner_model_branch_set}" != true ]]; then
				PLANNER_MODEL_BRANCH="$2"
			fi
			if [[ "${react_model_branch_set}" != true ]]; then
				REACT_MODEL_BRANCH="$2"
			fi
			shift 2
			;;
		--planner-model)
			if [[ $# -lt 2 ]]; then
				die "cli" "usage" "--planner-model requires an HF repo[:file] value"
			fi
			PLANNER_MODEL_SPEC="$2"
			planner_model_spec_set=true
			shift 2
			;;
		--planner-model-branch)
			if [[ $# -lt 2 ]]; then
				die "cli" "usage" "--planner-model-branch requires a branch or tag"
			fi
			PLANNER_MODEL_BRANCH="$2"
			planner_model_branch_set=true
			shift 2
			;;
		--react-model)
			if [[ $# -lt 2 ]]; then
				die "cli" "usage" "--react-model requires an HF repo[:file] value"
			fi
			REACT_MODEL_SPEC="$2"
			react_model_spec_set=true
			shift 2
			;;
		--react-model-branch)
			if [[ $# -lt 2 ]]; then
				die "cli" "usage" "--react-model-branch requires a branch or tag"
			fi
			REACT_MODEL_BRANCH="$2"
			react_model_branch_set=true
			shift 2
			;;
		--config)
			if [[ $# -lt 2 ]]; then
				die "cli" "usage" "--config requires a path"
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
			die "cli" "usage" "Unknown option: ${1}"
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
		die "cli" "usage" "A user query is required. See --help for usage."
	fi
}
