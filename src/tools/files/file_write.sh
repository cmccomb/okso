#!/usr/bin/env bash
# shellcheck shell=bash
#
# File write tool for creating, overwriting, and appending local text files.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/files/file_write.sh}/tools/files/file_write.sh"
#
# Environment variables:
#   TOOL_ARGS (JSON object): structured args with required `path` and `content`.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Non-zero on validation errors, filesystem errors, or unsupported paths.

FILES_TOOLS_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC_ROOT=$(cd -- "${FILES_TOOLS_DIR}/../.." && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${SRC_ROOT}/lib/core/logging.sh"
# shellcheck source=src/tools/registry.sh
source "${SRC_ROOT}/tools/registry.sh"

file_write_parse_args() {
	# Parses TOOL_ARGS JSON for file_write.
	# Returns a normalized JSON object.
	local args_json parsed
	args_json="${TOOL_ARGS:-}" || true

	if ! parsed=$(jq -cer '
                if (type != "object") then error("args must be object") end
                | .path = (.path // .input)
                | if (.path? == null) then error("missing path") end
                | if (.path | type) != "string" or (.path | length) == 0 then error("path must be non-empty string") end
                | if (.content? == null) then error("missing content") end
                | if (.content | type) != "string" then error("content must be string") end
                | if (.mode? != null) then
                        if (.mode | type) != "string" then error("mode must be string") end
                        | if ((.mode != "create") and (.mode != "overwrite") and (.mode != "append")) then
                                error("mode must be create, overwrite, or append")
                          else
                                .
                          end
                else
                        .
                end
                | if (.create_parents? != null and (.create_parents | type) != "boolean") then error("create_parents must be boolean") end
                | if ((del(.path, .input, .content, .mode, .create_parents) | length) != 0) then error("unexpected properties") end
                | {
                        path: .path,
                        content: .content,
                        mode: (.mode // "overwrite"),
                        create_parents: (.create_parents // false)
                  }
        ' <<<"${args_json}" 2>&1); then
		log "ERROR" "Invalid file_write arguments" "${parsed}" >&2
		return 1
	fi

	printf '%s' "${parsed}"
}

tool_file_write() {
	local parsed_args path mode create_parents parent existed created
	local content_bytes file_size content_path

	if ! parsed_args=$(file_write_parse_args); then
		return 1
	fi

	path=$(jq -r '.path' <<<"${parsed_args}")
	mode=$(jq -r '.mode' <<<"${parsed_args}")
	create_parents=$(jq -r '.create_parents' <<<"${parsed_args}")

	content_path=$(mktemp "${TMPDIR:-/tmp}/file_write.content.XXXXXX") || return 1
	if ! jq -j '.content' <<<"${parsed_args}" >"${content_path}"; then
		rm -f "${content_path}"
		log "ERROR" "file_write failed to render content payload" "${path}" >&2
		return 1
	fi

	if [[ -e "${path}" && ! -f "${path}" ]]; then
		rm -f "${content_path}"
		log "ERROR" "file_write path must be a regular file" "${path}" >&2
		return 1
	fi

	parent=$(dirname -- "${path}")
	if [[ ! -d "${parent}" ]]; then
		if [[ "${create_parents}" == "true" ]]; then
			if ! mkdir -p -- "${parent}"; then
				rm -f "${content_path}"
				log "ERROR" "file_write failed to create parent directories" "${parent}" >&2
				return 1
			fi
		else
			rm -f "${content_path}"
			log "ERROR" "file_write parent directory does not exist" "${parent}" >&2
			return 1
		fi
	fi

	existed="false"
	if [[ -f "${path}" ]]; then
		existed="true"
	fi

	case "${mode}" in
	create)
		if [[ "${existed}" == "true" ]]; then
			rm -f "${content_path}"
			log "ERROR" "file_write create mode requires a new file" "${path}" >&2
			return 1
		fi
		if ! cat "${content_path}" >"${path}"; then
			rm -f "${content_path}"
			log "ERROR" "file_write failed to create file" "${path}" >&2
			return 1
		fi
		;;
	overwrite)
		if ! cat "${content_path}" >"${path}"; then
			rm -f "${content_path}"
			log "ERROR" "file_write failed to overwrite file" "${path}" >&2
			return 1
		fi
		;;
	append)
		if ! cat "${content_path}" >>"${path}"; then
			rm -f "${content_path}"
			log "ERROR" "file_write failed to append file" "${path}" >&2
			return 1
		fi
		;;
	*)
		rm -f "${content_path}"
		log "ERROR" "file_write mode is invalid" "${mode}" >&2
		return 1
		;;
	esac

	created="false"
	if [[ "${existed}" != "true" ]]; then
		created="true"
	fi

	content_bytes=$(wc -c <"${content_path}" | tr -d '[:space:]')
	file_size=$(wc -c <"${path}" | tr -d '[:space:]')
	rm -f "${content_path}"

	jq -nc \
		--arg path "${path}" \
		--arg mode "${mode}" \
		--argjson created "${created}" \
		--argjson bytes_written "${content_bytes}" \
		--argjson file_size "${file_size}" \
		'{
                path: $path,
                mode: $mode,
                created: $created,
                bytes_written: $bytes_written,
                file_size: $file_size
        }'
}

register_file_write() {
	local args_schema

	args_schema=$(
		jq -c . <<'JSON'
{
  "type": "object",
  "required": ["path", "content"],
  "properties": {
    "path": {
      "type": "string",
      "minLength": 1
    },
    "content": {
      "type": "string"
    },
    "mode": {
      "type": "string",
      "enum": ["create", "overwrite", "append"]
    },
    "create_parents": {
      "type": "boolean"
    }
  }
}
JSON
	)

	register_tool \
		"file_write" \
		"Write text content to a local file by creating, overwriting, or appending." \
		tool_file_write \
		"${args_schema}"
}
