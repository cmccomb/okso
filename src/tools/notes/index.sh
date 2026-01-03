#!/usr/bin/env bash
# shellcheck shell=bash
#
# Aggregator for Apple Notes tools.
#
# Usage:
#   source "${BASH_SOURCE[0]%/notes/index.sh}/notes/index.sh"
#
# Environment variables:
#   NOTES_FOLDER (string): target folder within Apple Notes.
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#
# Dependencies:
#   - bash 3.2+
#   - logging helpers from logging.sh
#   - register_tool utilities from tools/registry.sh
#
# Exit codes:
#   Functions emit errors via log and return non-zero when misused.

# shellcheck source=src/tools/notes/common.sh
source "${BASH_SOURCE[0]%/index.sh}/common.sh"
# shellcheck source=src/tools/notes/create.sh
source "${BASH_SOURCE[0]%/index.sh}/create.sh"
# shellcheck source=src/tools/notes/append.sh
source "${BASH_SOURCE[0]%/index.sh}/append.sh"
# shellcheck source=src/tools/notes/list.sh
source "${BASH_SOURCE[0]%/index.sh}/list.sh"
# shellcheck source=src/tools/notes/search.sh
source "${BASH_SOURCE[0]%/index.sh}/search.sh"
# shellcheck source=src/tools/notes/read.sh
source "${BASH_SOURCE[0]%/index.sh}/read.sh"

register_notes_suite() {
	register_notes_create
	register_notes_append
	register_notes_list
	register_notes_search
	register_notes_read
}
