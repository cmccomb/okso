#!/usr/bin/env bash
# shellcheck shell=bash
#
# Compatibility wrapper for the relocated executor helpers.
#
# The executor library now lives under src/lib/react. This shim keeps existing
# callers functional by sourcing the new entrypoint.
#
# Usage:
#   source "${BASH_SOURCE[0]%/react.sh}/react.sh"

PLANNING_REACT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REACT_LIB_DIR="${PLANNING_REACT_DIR}/../react"

# shellcheck source=../react/react.sh disable=SC1091
source "${REACT_LIB_DIR}/react.sh"
