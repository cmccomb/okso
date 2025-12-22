#!/usr/bin/env bash
# shellcheck shell=bash
#
# Guard helpers for common platform and dependency requirements.
#
# Usage:
#   source "${BASH_SOURCE[0]%/guards.sh}/guards.sh"
#
# Environment variables:
#   LLAMA_AVAILABLE (bool): indicates whether llama.cpp is available for inference.
#   IS_MACOS (bool): signals whether the host is macOS.
#
# Dependencies:
#   - bash 3.2+
#   - logging helpers from logging.sh
#
# Exit codes:
#   Functions return non-zero when requirements are unmet.

GUARDS_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=../core/logging.sh disable=SC1091
source "${GUARDS_LIB_DIR}/../core/logging.sh"

require_llama_available() {
        # Ensures llama-backed features only run when llama.cpp is available.
        # Arguments:
        #   $1 - feature name for logging context (string; optional)
        local feature
        feature=${1:-"llama-backed functionality"}

        if [[ "${LLAMA_AVAILABLE:-}" == true ]]; then
                return 0
        fi

        log "ERROR" "llama.cpp is required for ${feature}" "LLAMA_AVAILABLE=${LLAMA_AVAILABLE:-}" || true
        return 1
}

require_macos_capable_terminal() {
        # Enforces macOS availability for macOS-specific terminal or automation tools.
        # Arguments:
        #   $1 - warning message when unsupported (string; optional)
        #   $2 - log severity when unsupported (string; optional; default WARN)
        local warning severity
        warning=${1:-"macOS-only functionality is unavailable on this platform"}
        severity=${2:-"WARN"}

        if [[ "${IS_MACOS:-}" == true ]]; then
                return 0
        fi

        log "${severity}" "${warning}" "IS_MACOS=${IS_MACOS:-}" || true
        return 1
}

export -f require_llama_available
export -f require_macos_capable_terminal
