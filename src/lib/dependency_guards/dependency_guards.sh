#!/usr/bin/env bash
# shellcheck shell=bash
#
# Guard helpers for common platform and dependency requirements.
#
# Usage:
#   source "${BASH_SOURCE[0]%/dependency_guards.sh}/dependency_guards.sh"
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

DEPENDENCY_GUARDS_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=../core/logging.sh disable=SC1091
source "${DEPENDENCY_GUARDS_LIB_DIR}/../core/logging.sh"
