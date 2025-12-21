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

REACT_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=./schema.sh disable=SC1091
source "${REACT_LIB_DIR}/schema.sh"
# shellcheck source=./history.sh disable=SC1091
source "${REACT_LIB_DIR}/history.sh"
# shellcheck source=./loop.sh disable=SC1091
source "${REACT_LIB_DIR}/loop.sh"
