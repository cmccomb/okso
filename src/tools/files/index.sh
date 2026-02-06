#!/usr/bin/env bash
# shellcheck shell=bash
#
# File tool suite aggregator for local file operations.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/files/index.sh}/tools/files/index.sh"
#
# Dependencies:
#   - bash 3.2+
#   - logging helpers from logging.sh
#   - register_tool utilities from tools/registry.sh

FILES_TOOLS_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC_ROOT=$(cd -- "${FILES_TOOLS_DIR}/../.." && pwd)

# shellcheck source=src/lib/core/logging.sh
source "${SRC_ROOT}/lib/core/logging.sh"
# shellcheck source=src/tools/registry.sh
source "${SRC_ROOT}/tools/registry.sh"

# shellcheck source=src/tools/files/file_search.sh
source "${FILES_TOOLS_DIR}/file_search.sh"
# shellcheck source=src/tools/files/file_read.sh
source "${FILES_TOOLS_DIR}/file_read.sh"
# shellcheck source=src/tools/files/file_write.sh
source "${FILES_TOOLS_DIR}/file_write.sh"
# shellcheck source=src/tools/files/file_edit.sh
source "${FILES_TOOLS_DIR}/file_edit.sh"

register_file_suite() {
	register_file_search
	register_file_read
	register_file_write
	register_file_edit
}
