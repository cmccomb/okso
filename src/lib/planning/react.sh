#!/usr/bin/env bash
# shellcheck shell=bash
#
# Compatibility wrapper for the relocated executor helpers.
#
# The executor library now lives under src/lib/executor. This shim keeps existing
# callers functional by sourcing the new entrypoint.
#
# Usage:
#   source "${BASH_SOURCE[0]%/executor.sh}/executor.sh"

PLANNING_EXECUTOR_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EXECUTOR_LIB_DIR="${PLANNING_EXECUTOR_DIR}/../executor"

# shellcheck source=../executor/executor.sh disable=SC1091
source "${EXECUTOR_LIB_DIR}/executor.sh"
