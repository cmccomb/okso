#!/usr/bin/env bash
# shellcheck shell=bash
#
# Entry point for the ReAct execution loop. This file sources the modular
# React helpers responsible for schema validation, state handling, and the
# execution loop.
#
# Usage:
#   source "${BASH_SOURCE[0]%/react.sh}/react.sh"
#
# Environment variables:
#   MAX_STEPS (int): maximum number of ReAct turns; default: 6.
#   CANONICAL_TEXT_ARG_KEY (string): key for single-string tool arguments; default: "input".
#
# Dependencies:
#   - bash 3.2+
#   - jq
#
# Exit codes:
#   None directly; functions return status of operations.

PLANNING_REACT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLANNING_REACT_ROOT_DIR="${PLANNING_REACT_DIR}"

# shellcheck source=./react/schema.sh disable=SC1091
source "${PLANNING_REACT_DIR}/react/schema.sh"
# shellcheck source=./react/history.sh disable=SC1091
source "${PLANNING_REACT_DIR}/react/history.sh"
# shellcheck source=./react/loop.sh disable=SC1091
source "${PLANNING_REACT_DIR}/react/loop.sh"
