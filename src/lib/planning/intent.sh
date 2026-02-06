#!/usr/bin/env bash
# shellcheck shell=bash
#
# Compatibility shim for the intent helpers.
#
# Usage:
#   source "${BASH_SOURCE[0]%/planning/intent.sh}/planning/intent.sh"

PLANNING_INTENT_SHIM_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=src/lib/intent/intent.sh
source "${PLANNING_INTENT_SHIM_DIR}/../intent/intent.sh"
