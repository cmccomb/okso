#!/usr/bin/env bash
# shellcheck shell=bash
#
# Web tool suite aggregator, providing registration for web_search and web_fetch.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/web/index.sh}/tools/web/index.sh"
#
# Dependencies:
#   - bash 3.2+
#   - logging helpers from logging.sh
#   - register_tool utilities from tools/registry.sh

WEB_TOOLS_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC_ROOT=$(cd -- "${WEB_TOOLS_DIR}/../.." && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${SRC_ROOT}/lib/core/logging.sh"
# shellcheck source=src/tools/registry.sh
source "${SRC_ROOT}/tools/registry.sh"

# shellcheck source=src/tools/web/web_search.sh
source "${WEB_TOOLS_DIR}/web_search.sh"
# shellcheck source=src/tools/web/web_fetch.sh
source "${WEB_TOOLS_DIR}/web_fetch.sh"

register_web_suite() {
	register_web_search
	register_web_fetch
}
