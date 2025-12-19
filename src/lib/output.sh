#!/usr/bin/env bash
# shellcheck shell=bash
#
# User output helpers that keep stdout reserved for user-facing responses and
# diagnostics routed through logging helpers on stderr.
#
# Usage:
#   source "${BASH_SOURCE[0]%/output.sh}/output.sh"
#
# Environment variables:
#   None.
#
# Dependencies:
#   - bash 5+
#
# Exit codes:
#   Functions return 0 on success.

# Emits a message to stdout without an automatic trailing newline.
# Arguments:
#   $1 - message (string)
user_output() {
        local message
        message="$1"
        printf '%s' "${message}"
}

# Emits a message followed by a newline to stdout.
# Arguments:
#   $1 - message (string)
user_output_line() {
        local message
        message="$1"
        printf '%s\n' "${message}"
}

# Emits each provided argument as a separate line to stdout.
# Arguments:
#   $@ - messages (string array)
user_output_lines() {
        local line
        for line in "$@"; do
                user_output_line "${line}"
        done
}
