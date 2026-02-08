#!/usr/bin/env bash
# shellcheck shell=bash
# Run the full Bats test suite.
# Usage: bash ./scripts/ci/run-bats.sh

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "${ROOT_DIR}"

bats --verbose-run \
	tests/core/*.sh \
	tests/executor/*.sh \
	tests/install/*.sh \
	tests/lib/*.sh \
	tests/planner/*.sh \
	tests/planning/*.sh \
	tests/runtime/*.sh \
	tests/tools/*.sh
