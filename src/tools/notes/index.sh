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
#   - bash 5+
#   - logging helpers from logging.sh
#   - register_tool utilities from tools/registry.sh
#
# Exit codes:
#   Functions emit errors via log and return non-zero when misused.

# shellcheck source=./common.sh disable=SC1091
source "${BASH_SOURCE[0]%/index.sh}/common.sh"
# shellcheck source=./create.sh disable=SC1091
source "${BASH_SOURCE[0]%/index.sh}/create.sh"
# shellcheck source=./append.sh disable=SC1091
source "${BASH_SOURCE[0]%/index.sh}/append.sh"
# shellcheck source=./list.sh disable=SC1091
source "${BASH_SOURCE[0]%/index.sh}/list.sh"
# shellcheck source=./search.sh disable=SC1091
source "${BASH_SOURCE[0]%/index.sh}/search.sh"
# shellcheck source=./read.sh disable=SC1091
source "${BASH_SOURCE[0]%/index.sh}/read.sh"

register_notes_suite() {
	register_notes_create
	register_notes_append
	register_notes_list
	register_notes_search
	register_notes_read
}
