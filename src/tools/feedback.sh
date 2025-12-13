#!/usr/bin/env bash
# shellcheck shell=bash
#
# Feedback collection tool that summarizes the current plan context and asks the
# user for a rating and comments.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/feedback.sh}/tools/feedback.sh"
#
# Environment variables:
#   TOOL_QUERY (string): JSON object with "plan_item" (string) and
#       "observations" (string) describing the current step and recent tool
#       output.
#   FEEDBACK_ENABLED (bool): when "false", skip prompts and return a skipped
#       status. Defaults to "true".
#   FEEDBACK_NONINTERACTIVE_INPUT (string): optional "<rating>|<comments>"
#       payload used in non-interactive environments (rating must be 1-5).
#   FEEDBACK_OUTPUT_PATH (string): optional file path for recording the feedback
#       JSON payload. Must reside in an allowlisted directory.
#
# Dependencies:
#   - bash 5+
#   - jq
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero when required context is missing, validation fails, or the
#   output path is not writable.

# shellcheck source=../lib/logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/feedback.sh}/lib/logging.sh"
# shellcheck source=./registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/feedback.sh}/registry.sh"

feedback_normalize_context() {
        # Parses TOOL_QUERY JSON into discrete variables.
        # Arguments: none. Reads TOOL_QUERY.
        local plan_item observations

        if [[ -z "${TOOL_QUERY:-}" ]]; then
                log "ERROR" "Feedback context missing" "TOOL_QUERY is empty" || true
                return 1
        fi

        if ! plan_item=$(jq -er '.plan_item' <<<"${TOOL_QUERY}" 2>/dev/null); then
                log "ERROR" "Feedback context requires plan_item" "${TOOL_QUERY}" || true
                return 1
        fi

        observations=$(jq -er '.observations' <<<"${TOOL_QUERY}" 2>/dev/null || true)
        observations="${observations:-}" # string observation summary

        printf '%s\n%s' "${plan_item}" "${observations}"
}

feedback_validate_output_path() {
        # Ensures the configured output path resides in the writable allowlist.
        # Arguments:
        #   $1 - target output path (string)
        local output_path parent_dir
        output_path="$1"

        if [[ -z "${output_path}" ]]; then
                return 0
        fi

        parent_dir="$(dirname -- "${output_path}")"
        if [[ "$(type -t tools_writable_directory_allowed)" != "function" ]]; then
                log "ERROR" "Writable directory checker unavailable" "${parent_dir}" || true
                return 1
        fi

        if ! tools_writable_directory_allowed "${parent_dir}"; then
                log "ERROR" "Feedback output path not allowlisted" "${output_path}" || true
                return 1
        fi

        if ! mkdir -p -- "${parent_dir}"; then
                log "ERROR" "Failed to prepare feedback directory" "${parent_dir}" || true
                return 1
        fi

        return 0
}

feedback_capture_input() {
        # Collects rating and comments from user or provided input.
        # Arguments:
        #   $1 - plan item description (string)
        #   $2 - observation summary (string)
        local plan_item observations provided rating_input comment_input
        plan_item="$1"
        observations="$2"

        if [[ -n "${FEEDBACK_NONINTERACTIVE_INPUT:-}" ]]; then
                provided="${FEEDBACK_NONINTERACTIVE_INPUT}"
                rating_input="${provided%%|*}"
                if [[ "${provided}" == *"|"* ]]; then
                        comment_input="${provided#*|}"
                else
                        comment_input=""
                fi
        else
                printf 'Current plan item:%s%s\n' $' ' "${plan_item}" >&2
                if [[ -n "${observations}" ]]; then
                        printf 'Recent tool results:%s%s\n' $' ' "${observations}" >&2
                fi
                read -r -p "Please rate this step (1-5): " rating_input || true
                read -r -p "Comments (optional): " comment_input || true
        fi

        if [[ -z "${rating_input}" || ! "${rating_input}" =~ ^[1-5]$ ]]; then
                log "ERROR" "Invalid feedback rating" "${rating_input:-empty}" || true
                return 1
        fi

        printf '%s\n%s' "${rating_input}" "${comment_input:-}"
}

feedback_persist_payload() {
        # Writes the feedback payload to the configured output path.
        # Arguments:
        #   $1 - serialized JSON payload (string)
        #   $2 - optional output path (string)
        local payload output_path
        payload="$1"
        output_path="$2"

        if [[ -z "${output_path}" ]]; then
                return 0
        fi

        if ! feedback_validate_output_path "${output_path}"; then
                return 1
        fi

        if ! printf '%s\n' "${payload}" >"${output_path}"; then
                log "ERROR" "Failed to write feedback payload" "${output_path}" || true
                return 1
        fi

        return 0
}

tool_feedback() {
        # Emits structured feedback after prompting the user.
        # Arguments: none. Reads TOOL_QUERY and optional environment overrides.
        local plan_item observations rating comment payload output_path

        if [[ "${FEEDBACK_ENABLED:-true}" != true ]]; then
                log "INFO" "Feedback skipped by opt-out" "FEEDBACK_ENABLED=${FEEDBACK_ENABLED}" || true
                printf '%s' '{"status":"skipped","reason":"disabled"}'
                return 0
        fi

        if ! mapfile -t context_parts < <(feedback_normalize_context); then
                return 1
        fi
        plan_item="${context_parts[0]}"
        observations="${context_parts[1]:-}"

        if ! mapfile -t feedback_parts < <(feedback_capture_input "${plan_item}" "${observations}"); then
                return 1
        fi
        rating="${feedback_parts[0]}"
        comment="${feedback_parts[1]:-}"

        payload="$(jq -c -n \
                --arg plan_item "${plan_item}" \
                --arg observations "${observations}" \
                --argjson rating "${rating}" \
                --arg comment "${comment}" \
                '{
                        status: "recorded",
                        plan_item: $plan_item,
                        observations: $observations,
                        rating: $rating,
                        comment: $comment
                }')"

        output_path="${FEEDBACK_OUTPUT_PATH:-}"
        if ! feedback_persist_payload "${payload}" "${output_path}"; then
                return 1
        fi

        printf '%s' "${payload}"
}

register_feedback() {
        register_tool \
                "feedback" \
                "Collect a 1-5 rating and optional comments for the current plan step." \
                "feedback <json context>" \
                "Prompts the user; respects FEEDBACK_ENABLED=false to skip interaction." \
                tool_feedback
}
