#!/usr/bin/env bash
# shellcheck shell=bash
#
# File edit tool for literal text replacement in local files.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/files/file_edit.sh}/tools/files/file_edit.sh"
#
# Environment variables:
#   TOOL_ARGS (JSON object): structured args with required `path`, `old_text`, and `new_text`.
#
# Dependencies:
#   - bash 3.2+
#   - jq
#   - perl
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Non-zero on validation errors, filesystem errors, missing dependencies, or ambiguous matches.

FILES_TOOLS_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC_ROOT=$(cd -- "${FILES_TOOLS_DIR}/../.." && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${SRC_ROOT}/lib/core/logging.sh"
# shellcheck source=src/tools/registry.sh
source "${SRC_ROOT}/tools/registry.sh"

file_edit_parse_args() {
	# Parses TOOL_ARGS JSON for file_edit.
	# Returns a normalized JSON object.
	local args_json parsed
	args_json="${TOOL_ARGS:-}" || true

	if ! parsed=$(jq -cer '
                if (type != "object") then error("args must be object") end
                | .path = (.path // .input)
                | if (.path? == null) then error("missing path") end
                | if (.path | type) != "string" or (.path | length) == 0 then error("path must be non-empty string") end
                | if (.old_text? == null) then error("missing old_text") end
                | if (.old_text | type) != "string" or (.old_text | length) == 0 then error("old_text must be non-empty string") end
                | if (.new_text? == null) then error("missing new_text") end
                | if (.new_text | type) != "string" then error("new_text must be string") end
                | if (.replace_all? != null and (.replace_all | type) != "boolean") then error("replace_all must be boolean") end
                | if (.occurrence? != null) then
                        if (.occurrence | type) != "number" or (.occurrence | floor) != .occurrence then error("occurrence must be integer") end
                        | if (.occurrence < 1) then error("occurrence must be >= 1") else . end
                else
                        .
                end
                | if ((.replace_all // false) == true and .occurrence? != null) then error("replace_all and occurrence cannot be combined") end
                | if ((del(.path, .input, .old_text, .new_text, .replace_all, .occurrence) | length) != 0) then error("unexpected properties") end
                | {
                        path: .path,
                        old_text: .old_text,
                        new_text: .new_text,
                        replace_all: (.replace_all // false),
                        occurrence: (if .occurrence? != null then .occurrence else null end)
                  }
        ' <<<"${args_json}" 2>&1); then
		log "ERROR" "Invalid file_edit arguments" "${parsed}" >&2
		return 1
	fi

	printf '%s' "${parsed}"
}

file_edit_count_occurrences() {
	# Arguments:
	#   $1 - file path
	#   $2 - old_text path
	local file_path old_text_path
	file_path="$1"
	old_text_path="$2"

	perl -e '
                use strict;
                use warnings;

                sub read_file {
                        my ($path) = @_;
                        open my $fh, "<", $path or die "unable to open ${path}: $!";
                        binmode $fh;
                        local $/;
                        my $content = <$fh>;
                        close $fh;
                        return defined $content ? $content : q{};
                }

                my ($file_path, $old_path) = @ARGV;
                my $content = read_file($file_path);
                my $old = read_file($old_path);

                my $count = 0;
                my $position = 0;
                my $old_length = length($old);

                while (1) {
                        my $index = index($content, $old, $position);
                        last if $index < 0;
                        $count++;
                        $position = $index + $old_length;
                }

                print $count;
        ' "${file_path}" "${old_text_path}"
}

file_edit_render_output() {
	# Arguments:
	#   $1 - file path
	#   $2 - old_text path
	#   $3 - new_text path
	#   $4 - replace_all flag (true/false)
	#   $5 - occurrence (string; empty when unset)
	#   $6 - output path
	local file_path old_text_path new_text_path replace_all occurrence output_path
	file_path="$1"
	old_text_path="$2"
	new_text_path="$3"
	replace_all="$4"
	occurrence="$5"
	output_path="$6"

	perl -e '
                use strict;
                use warnings;

                sub read_file {
                        my ($path) = @_;
                        open my $fh, "<", $path or die "unable to open ${path}: $!";
                        binmode $fh;
                        local $/;
                        my $content = <$fh>;
                        close $fh;
                        return defined $content ? $content : q{};
                }

                my ($file_path, $old_path, $new_path, $replace_all, $occurrence, $output_path) = @ARGV;

                my $content = read_file($file_path);
                my $old = read_file($old_path);
                my $new = read_file($new_path);

                my $result = q{};
                my $position = 0;
                my $match_index = 0;
                my $old_length = length($old);
                my $occurrence_target = ($occurrence ne q{}) ? int($occurrence) : 0;

                while (1) {
                        my $index = index($content, $old, $position);
                        last if $index < 0;
                        $match_index++;

                        my $replace_this = 0;
                        if ($replace_all eq "true") {
                                $replace_this = 1;
                        } elsif ($occurrence_target > 0) {
                                $replace_this = ($match_index == $occurrence_target) ? 1 : 0;
                        } else {
                                $replace_this = ($match_index == 1) ? 1 : 0;
                        }

                        if ($replace_this) {
                                $result .= substr($content, $position, $index - $position);
                                $result .= $new;
                        } else {
                                $result .= substr($content, $position, $index - $position + $old_length);
                        }

                        $position = $index + $old_length;
                }

                $result .= substr($content, $position);

                open my $out, ">", $output_path or die "unable to open ${output_path}: $!";
                binmode $out;
                print {$out} $result;
                close $out;
        ' "${file_path}" "${old_text_path}" "${new_text_path}" "${replace_all}" "${occurrence}" "${output_path}"
}

tool_file_edit() {
	local parsed_args path replace_all occurrence match_count replacements file_size
	local old_text_path new_text_path rendered_path old_size

	if ! parsed_args=$(file_edit_parse_args); then
		return 1
	fi

	path=$(jq -r '.path' <<<"${parsed_args}")
	replace_all=$(jq -r '.replace_all' <<<"${parsed_args}")
	occurrence=$(jq -r 'if .occurrence == null then "" else (.occurrence | tostring) end' <<<"${parsed_args}")

	if ! command -v perl >/dev/null 2>&1; then
		log "ERROR" "Missing dependency for file_edit" "perl" >&2
		return 1
	fi

	if [[ ! -f "${path}" ]]; then
		log "ERROR" "file_edit path not found" "${path}" >&2
		return 1
	fi

	old_text_path=$(mktemp "${TMPDIR:-/tmp}/file_edit.old.XXXXXX") || return 1
	new_text_path=$(mktemp "${TMPDIR:-/tmp}/file_edit.new.XXXXXX") || {
		rm -f "${old_text_path}"
		return 1
	}
	rendered_path=$(mktemp "${TMPDIR:-/tmp}/file_edit.rendered.XXXXXX") || {
		rm -f "${old_text_path}" "${new_text_path}"
		return 1
	}

	if ! jq -j '.old_text' <<<"${parsed_args}" >"${old_text_path}"; then
		rm -f "${old_text_path}" "${new_text_path}" "${rendered_path}"
		log "ERROR" "file_edit failed to render old_text payload" "${path}" >&2
		return 1
	fi

	if ! jq -j '.new_text' <<<"${parsed_args}" >"${new_text_path}"; then
		rm -f "${old_text_path}" "${new_text_path}" "${rendered_path}"
		log "ERROR" "file_edit failed to render new_text payload" "${path}" >&2
		return 1
	fi

	old_size=$(wc -c <"${old_text_path}" | tr -d '[:space:]')
	if [[ "${old_size}" == "0" ]]; then
		rm -f "${old_text_path}" "${new_text_path}" "${rendered_path}"
		log "ERROR" "file_edit old_text must be non-empty" "${path}" >&2
		return 1
	fi

	if ! match_count=$(file_edit_count_occurrences "${path}" "${old_text_path}"); then
		rm -f "${old_text_path}" "${new_text_path}" "${rendered_path}"
		log "ERROR" "file_edit failed while counting matches" "${path}" >&2
		return 1
	fi

	if ((match_count == 0)); then
		rm -f "${old_text_path}" "${new_text_path}" "${rendered_path}"
		log "ERROR" "file_edit old_text not found" "${path}" >&2
		return 1
	fi

	if [[ "${replace_all}" == "true" ]]; then
		replacements="${match_count}"
	elif [[ -n "${occurrence}" ]]; then
		if ((occurrence > match_count)); then
			rm -f "${old_text_path}" "${new_text_path}" "${rendered_path}"
			log "ERROR" "file_edit occurrence exceeds match count" "${path}" >&2
			return 1
		fi
		replacements=1
	else
		if ((match_count != 1)); then
			rm -f "${old_text_path}" "${new_text_path}" "${rendered_path}"
			log "ERROR" "file_edit is ambiguous; set occurrence or replace_all" "${path}" >&2
			return 1
		fi
		replacements=1
	fi

	if ! file_edit_render_output "${path}" "${old_text_path}" "${new_text_path}" "${replace_all}" "${occurrence}" "${rendered_path}"; then
		rm -f "${old_text_path}" "${new_text_path}" "${rendered_path}"
		log "ERROR" "file_edit failed while applying replacement" "${path}" >&2
		return 1
	fi

	if cmp -s "${path}" "${rendered_path}"; then
		rm -f "${old_text_path}" "${new_text_path}" "${rendered_path}"
		log "ERROR" "file_edit produced no changes" "${path}" >&2
		return 1
	fi

	if ! cat "${rendered_path}" >"${path}"; then
		rm -f "${old_text_path}" "${new_text_path}" "${rendered_path}"
		log "ERROR" "file_edit failed to write output" "${path}" >&2
		return 1
	fi

	file_size=$(wc -c <"${path}" | tr -d '[:space:]')
	rm -f "${old_text_path}" "${new_text_path}" "${rendered_path}"

	jq -nc \
		--arg path "${path}" \
		--argjson replacements "${replacements}" \
		--argjson total_matches "${match_count}" \
		--argjson file_size "${file_size}" \
		'{
                path: $path,
                replacements: $replacements,
                total_matches: $total_matches,
                file_size: $file_size
        }'
}

register_file_edit() {
	local args_schema

	args_schema=$(
		jq -c . <<'JSON'
{
  "type": "object",
  "required": ["path", "old_text", "new_text"],
  "properties": {
    "path": {
      "type": "string",
      "minLength": 1
    },
    "old_text": {
      "type": "string",
      "minLength": 1
    },
    "new_text": {
      "type": "string"
    },
    "replace_all": {
      "type": "boolean"
    },
    "occurrence": {
      "type": "integer",
      "minimum": 1
    }
  }
}
JSON
	)

	register_tool \
		"file_edit" \
		"Edit an existing file by replacing literal text with optional occurrence controls." \
		tool_file_edit \
		"${args_schema}"
}
