#!/usr/bin/env bash
# shellcheck shell=bash
#
# File read tool that paginates and normalizes content to Markdown.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/files/file_read.sh}/tools/files/file_read.sh"
#
# Environment variables:
#   TOOL_ARGS (JSON object): structured args with required `path`.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#   - mktemp
#   - file
#   - optional converters: pandoc, pdftotext, docx2txt
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Non-zero on validation errors, missing dependencies, or unsupported types.

FILES_TOOLS_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC_ROOT=$(cd -- "${FILES_TOOLS_DIR}/../.." && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${SRC_ROOT}/lib/core/logging.sh"
# shellcheck source=src/tools/registry.sh
source "${SRC_ROOT}/tools/registry.sh"

file_read_parse_args() {
	# Parses TOOL_ARGS JSON for file_read.
	# Returns a normalized JSON object.
	local args_json err
	args_json="${TOOL_ARGS:-}" || true

	if ! err=$(jq -cer '
                if (type != "object") then error("args must be object") end
                | .path = (.path // .input)
                | if (.path? == null) then error("missing path") end
                | if (.path | type) != "string" or (.path | length) == 0 then error("path must be non-empty string") end
                | if (.page? != null) then
                        if (.page | type) != "number" or (.page | floor) != .page then error("page must be integer") end
                        | if (.page < 1) then error("page must be >= 1") end
                else
                        .page = 1
                end
                | if (.page_size? != null) then
                        if (.page_size | type) != "number" or (.page_size | floor) != .page_size then error("page_size must be integer") end
                        | if (.page_size < 1 or .page_size > 2000) then error("page_size must be between 1 and 2000") end
                else
                        .page_size = 200
                end
                | if ((del(.path, .input, .page, .page_size) | length) != 0) then error("unexpected properties") end
                | {path: .path, page: .page, page_size: .page_size}
        ' <<<"${args_json}" 2>&1); then
		log "ERROR" "Invalid file_read arguments" "${err}" >&2
		return 1
	fi
	printf '%s' "${err}"
}

file_read_detect_mime() {
	# Arguments:
	#   $1 - path
	# Returns:
	#   mime type (string or empty)
	local path
	path="$1"
	if command -v file >/dev/null 2>&1; then
		file -b --mime-type "${path}" 2>/dev/null || true
	else
		printf '%s' ""
	fi
}

file_read_wrap_markdown() {
	# Arguments:
	#   $1 - input path
	#   $2 - output path
	#   $3 - fence language
	local input_path output_path fence
	input_path="$1"
	output_path="$2"
	fence="$3"

	printf '```%s\n' "${fence}" >"${output_path}"
	cat "${input_path}" >>"${output_path}"
	printf '\n```\n' >>"${output_path}"
}

file_read_wrap_markdown_content() {
	# Arguments:
	#   $1 - content
	#   $2 - fence language
	local content fence
	content="$1"
	fence="$2"

	# shellcheck disable=SC2016
	printf '```%s\n%s\n```\n' "${fence}" "${content}"
}

file_read_render_text_file() {
	# Arguments:
	#   $1 - input path
	#   $2 - output path
	local input_path output_path
	input_path="$1"
	output_path="$2"

	cat "${input_path}" >"${output_path}"
}

file_read_pandoc_render() {
	# Arguments:
	#   $1 - input path
	#   $2 - output path
	local input_path output_path
	input_path="$1"
	output_path="$2"

	if ! pandoc "${input_path}" -t "markdown" -o "${output_path}"; then
		log "ERROR" "pandoc failed to convert file" "${input_path}" >&2
		return 1
	fi
}

file_read_paginate() {
	# Arguments:
	#   $1 - rendered path
	#   $2 - page
	#   $3 - page_size
	# Returns:
	#   Outputs: total_pages (int) and page_content (string) via stdout with delimiter.
	local rendered_path page page_size total_lines total_pages start_line end_line page_content
	rendered_path="$1"
	page="$2"
	page_size="$3"

	total_lines=$(awk 'END {print NR}' "${rendered_path}")
	if [[ -z "${total_lines}" ]]; then
		total_lines=0
	fi

	if ((total_lines == 0)); then
		total_pages=1
	else
		total_pages=$(((total_lines + page_size - 1) / page_size))
	fi

	if ((page < 1 || page > total_pages)); then
		printf '%s\n' "ERROR:page out of range (${page}/${total_pages})"
		return 1
	fi

	start_line=$(((page - 1) * page_size + 1))
	end_line=$((page * page_size))
	page_content=$(sed -n "${start_line},${end_line}p" "${rendered_path}")

	printf '%s\n' "${total_pages}"
	printf '%s' "${page_content}"
}

tool_file_read() {
	local parsed_args path page page_size tmp_dir extracted_path rendered_path wrap_page
	local ext_lower mime type_hint payload_header page_result total_pages page_content
	local convert_status

	if ! parsed_args=$(file_read_parse_args); then
		return 1
	fi

	path=$(jq -r '.path' <<<"${parsed_args}")
	page=$(jq -r '.page' <<<"${parsed_args}")
	page_size=$(jq -r '.page_size' <<<"${parsed_args}")

	if [[ ! -f "${path}" ]]; then
		log "ERROR" "file_read path not found" "${path}" >&2
		return 1
	fi

	mime=$(file_read_detect_mime "${path}")
	ext_lower=$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')
	type_hint=""

	case "${ext_lower}" in
	md)
		type_hint="markdown"
		;;
	html | htm | xml)
		type_hint="markup"
		;;
	pdf)
		type_hint="pdf"
		;;
	docx)
		type_hint="docx"
		;;
	pptx)
		type_hint="pptx"
		;;
	xlsx)
		type_hint="xlsx"
		;;
	txt | log | csv | tsv | json | yml | yaml)
		type_hint="text"
		;;
	esac

	if [[ -z "${type_hint}" && "${mime}" == text/* ]]; then
		type_hint="text"
	fi

	tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/file_read.XXXXXX") || return 1
	extracted_path=""
	rendered_path="${tmp_dir}/rendered"
	wrap_page=false

	case "${type_hint}" in
	markdown)
		cat "${path}" >"${rendered_path}"
		;;
	markup)
		if ! command -v pandoc >/dev/null 2>&1; then
			log "ERROR" "Missing dependency for markup conversion" "pandoc" >&2
			return 1
		fi
		if ! file_read_pandoc_render "${path}" "${rendered_path}"; then
			return 1
		fi
		;;
	pdf)
		if ! command -v pdftotext >/dev/null 2>&1; then
			log "ERROR" "Missing dependency for PDF extraction" "pdftotext" >&2
			return 1
		fi
		extracted_path="${tmp_dir}/extracted.txt"
		pdftotext -layout "${path}" "${extracted_path}"
		file_read_render_text_file "${extracted_path}" "${rendered_path}"
		wrap_page=true
		;;
	docx)
		if command -v pandoc >/dev/null 2>&1; then
			if ! file_read_pandoc_render "${path}" "${rendered_path}"; then
				return 1
			fi
		else
			if ! command -v docx2txt >/dev/null 2>&1; then
				log "ERROR" "Missing dependency for DOCX extraction" "pandoc or docx2txt" >&2
				return 1
			fi
			extracted_path="${tmp_dir}/extracted.txt"
			docx2txt "${path}" "${extracted_path}" >/dev/null 2>&1
			file_read_render_text_file "${extracted_path}" "${rendered_path}"
			wrap_page=true
		fi
		;;
	pptx)
		if ! command -v pandoc >/dev/null 2>&1; then
			log "ERROR" "Missing dependency for PPTX extraction" "pandoc" >&2
			return 1
		fi
		if ! file_read_pandoc_render "${path}" "${rendered_path}"; then
			return 1
		fi
		;;
	xlsx)
		log "ERROR" "XLSX files are not supported" "Export to CSV before running file_read." >&2
		return 1
		;;
	text)
		file_read_render_text_file "${path}" "${rendered_path}"
		wrap_page=true
		;;
	*)
		log "ERROR" "Unsupported file type" "${path}" >&2
		return 1
		;;
	esac

	page_result=$(file_read_paginate "${rendered_path}" "${page}" "${page_size}")
	convert_status=$?
	if [[ ${convert_status} -ne 0 ]]; then
		log "ERROR" "file_read pagination error" "${page_result}" >&2
		return 1
	fi

	total_pages=$(printf '%s\n' "${page_result}" | head -n1)
	page_content=$(printf '%s\n' "${page_result}" | tail -n +2)

	if [[ "${wrap_page}" == "true" ]]; then
		page_content=$(file_read_wrap_markdown_content "${page_content}" "text")
	fi

	payload_header="# $(basename "${path}")\n\n_Page ${page} of ${total_pages}_\n\n"

	jq -nc \
		--arg path "${path}" \
		--argjson page "${page}" \
		--argjson total_pages "${total_pages}" \
		--arg content "${payload_header}${page_content}" \
		--arg mime "${mime}" \
		--arg extracted "${extracted_path}" \
		--arg rendered "${rendered_path}" \
		'{
                path: $path,
                page: $page,
                total_pages: $total_pages,
                content_markdown: $content,
                mime: (if ($mime | length) > 0 then $mime else null end),
                artifact_paths: {
                        extracted_text: (if ($extracted | length) > 0 then $extracted else null end),
                        rendered_markdown: (if ($rendered | length) > 0 then $rendered else null end)
                } | with_entries(select(.value != null))
        } | with_entries(select(.value != null))'
}

register_file_read() {
	local args_schema

	args_schema=$(
		jq -c . <<'JSON'
{
  "type": "object",
  "required": ["path"],
  "properties": {
    "path": {
      "type": "string",
      "minLength": 1
    },
    "page": {
      "type": "integer",
      "minimum": 1
    },
    "page_size": {
      "type": "integer",
      "minimum": 1,
      "maximum": 2000
    }
  }
}
JSON
	)

	register_tool \
		"file_read" \
		"Read local files with pagination and Markdown normalization. Supports text, PDFs, and common Office document formats when dependencies are installed." \
		tool_file_read \
		"${args_schema}"
}
