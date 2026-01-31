#!/usr/bin/env bash
# shellcheck shell=bash
#
# File search tool backed by ripgrep-all (rga).
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/files/file_search.sh}/tools/files/file_search.sh"
#
# Environment variables:
#   TOOL_ARGS (JSON object): structured args with required `query` and `paths`.
#
# Dependencies:
#   - bash 3.2+
#   - rga (ripgrep-all)
#   - jq
#   - mktemp
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Non-zero on validation errors or missing dependencies.

FILES_TOOLS_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC_ROOT=$(cd -- "${FILES_TOOLS_DIR}/../.." && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${SRC_ROOT}/lib/core/logging.sh"
# shellcheck source=src/tools/registry.sh
source "${SRC_ROOT}/tools/registry.sh"

file_search_parse_args() {
	# Parses TOOL_ARGS JSON for file_search.
	# Returns a normalized JSON object.
	local args_json err
	args_json="${TOOL_ARGS:-}" || true

	if ! err=$(jq -cer '
                if (type != "object") then error("args must be object") end
                | .query = (.query // .input)
                | if (.query? == null) then error("missing query") end
                | if (.query | type) != "string" or (.query | length) == 0 then error("query must be non-empty string") end
                | if (.paths? == null) then error("missing paths") end
                | if (.paths | type) != "array" or (.paths | length) == 0 then error("paths must be array") end
                | if ([.paths[] | select(type != "string" or length == 0)] | length) > 0 then error("paths must be non-empty strings") end
                | if (.case_sensitive? != null and (.case_sensitive | type) != "boolean") then error("case_sensitive must be boolean") end
                | if (.max_results? != null) then
                        if (.max_results | type) != "number" or (.max_results | floor) != .max_results then error("max_results must be integer") end
                        | if (.max_results < 1 or .max_results > 200) then error("max_results must be between 1 and 200") end
                else
                        .max_results = 50
                end
                | if (.context_lines? != null) then
                        if (.context_lines | type) != "number" or (.context_lines | floor) != .context_lines then error("context_lines must be integer") end
                        | if (.context_lines < 0 or .context_lines > 10) then error("context_lines must be between 0 and 10") end
                else
                        .context_lines = 2
                end
                | if ((del(.query, .input, .paths, .case_sensitive, .max_results, .context_lines) | length) != 0) then error("unexpected properties") end
                | {query: .query, paths: .paths, case_sensitive: (.case_sensitive // false), max_results: .max_results, context_lines: .context_lines}
        ' <<<"${args_json}" 2>&1); then
		log "ERROR" "Invalid file_search arguments" "${err}" >&2
		return 1
	fi
	printf '%s' "${err}"
}

file_search_build_command() {
	# Builds the rga command array.
	# Arguments:
	#   $1 - query
	#   $2 - case_sensitive (true/false)
	#   $3 - max_results
	#   $4 - context_lines
	#   $@ - paths
	local query case_sensitive max_results context_lines
	query="$1"
	case_sensitive="$2"
	max_results="$3"
	context_lines="$4"
	shift 4

	local -a cmd
	cmd=("rga" "--json" "--line-number" "--max-count" "${max_results}")
	if [[ "${case_sensitive}" != "true" ]]; then
		cmd+=("--ignore-case")
	fi
	if [[ "${context_lines}" -gt 0 ]]; then
		cmd+=("--context" "${context_lines}")
	fi
	cmd+=("${query}")
	for path in "$@"; do
		cmd+=("${path}")
	done

	printf '%s\n' "${cmd[@]}"
}

tool_file_search() {
	local parsed_args query case_sensitive max_results context_lines
	local -a search_paths
	local -a cmd
	local tmp_dir raw_path status match_payload result_json

	if ! parsed_args=$(file_search_parse_args); then
		return 1
	fi

	query=$(jq -r '.query' <<<"${parsed_args}")
	case_sensitive=$(jq -r '.case_sensitive' <<<"${parsed_args}")
	max_results=$(jq -r '.max_results' <<<"${parsed_args}")
	context_lines=$(jq -r '.context_lines' <<<"${parsed_args}")

	search_paths=()
	while IFS= read -r path_item; do
		search_paths+=("${path_item}")
	done < <(jq -r '.paths[]' <<<"${parsed_args}")

	if ! command -v rga >/dev/null 2>&1; then
		log "ERROR" "Missing dependency for file_search" "rga" >&2
		return 1
	fi

	tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/file_search.XXXXXX") || return 1
	raw_path="${tmp_dir}/results.jsonl"

	cmd=()
	while IFS= read -r cmd_part; do
		cmd+=("${cmd_part}")
	done < <(file_search_build_command "${query}" "${case_sensitive}" "${max_results}" "${context_lines}" "${search_paths[@]}")

	"${cmd[@]}" >"${raw_path}"
	status=$?
	if [[ ${status} -ne 0 && ${status} -ne 1 ]]; then
		log "ERROR" "file_search failed" "status=${status}" >&2
		return 1
	fi

	match_payload=$(jq -s --argjson max "${max_results}" '
                map(select(.type == "match")
                    | {
                        path: (.data.path.text // ""),
                        line_number: (.data.line_number // null),
                        snippet: (.data.lines.text // "" | rtrimstr("\n"))
                      })
                | .[:$max]
        ' "${raw_path}")

	result_json=$(jq -nc --argjson matches "${match_payload}" --arg result_path "${raw_path}" '{matches: $matches, result_path: $result_path}')
	printf '%s' "${result_json}"
}

register_file_search() {
	local args_schema

	args_schema=$(
		jq -c . <<'JSON'
{
  "type": "object",
  "required": ["query", "paths"],
  "properties": {
    "query": {
      "type": "string",
      "minLength": 1,
      "maxLength": 500
    },
    "paths": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "string",
        "minLength": 1
      }
    },
    "case_sensitive": {
      "type": "boolean"
    },
    "max_results": {
      "type": "integer",
      "minimum": 1,
      "maximum": 200
    },
    "context_lines": {
      "type": "integer",
      "minimum": 0,
      "maximum": 10
    }
  }
}
JSON
	)

	register_tool \
		"file_search" \
		"Search files and documents with ripgrep-all (rga), returning structured match snippets and an artifact path for raw results." \
		"Reads local files; no external access. Ensure queries and paths are scoped to the intended workspace." \
		tool_file_search \
		"${args_schema}"
}
