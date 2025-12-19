#!/usr/bin/env bash
# shellcheck shell=bash
#
# Web tool suite aggregator, providing registration for web_search and web_fetch.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/web/index.sh}/tools/web/index.sh"
#
# Dependencies:
#   - bash 5+
#   - logging helpers from logging.sh
#   - register_tool utilities from tools/registry.sh

WEB_TOOLS_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC_ROOT=$(cd -- "${WEB_TOOLS_DIR}/../.." && pwd)

# shellcheck source=../../lib/logging.sh disable=SC1091
source "${SRC_ROOT}/lib/logging.sh"
# shellcheck source=../registry.sh disable=SC1091
source "${SRC_ROOT}/tools/registry.sh"

# shellcheck source=./web_search.sh disable=SC1091
source "${WEB_TOOLS_DIR}/web_search.sh"
# shellcheck source=./web_fetch.sh disable=SC1091
source "${WEB_TOOLS_DIR}/web_fetch.sh"

register_web_suite() {
        register_web_search
        register_web_fetch
}
