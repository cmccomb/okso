#!/usr/bin/env bash
# shellcheck shell=bash
#
# Aggregator for Apple Calendar tools.
#
# Usage:
#   source "${BASH_SOURCE[0]%/calendar/index.sh}/calendar/index.sh"
#
# Environment variables:
#   CALENDAR_NAME (string): target calendar within Apple Calendar.
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#
# Dependencies:
#   - bash 3.2+
#   - logging helpers from logging.sh
#   - register_tool utilities from tools/registry.sh
#
# Exit codes:
#   Functions emit errors via log and return non-zero when misused.

# shellcheck source=src/tools/calendar/common.sh
source "${BASH_SOURCE[0]%/index.sh}/common.sh"
# shellcheck source=src/tools/calendar/create.sh
source "${BASH_SOURCE[0]%/index.sh}/create.sh"
# shellcheck source=src/tools/calendar/list.sh
source "${BASH_SOURCE[0]%/index.sh}/list.sh"
# shellcheck source=src/tools/calendar/search.sh
source "${BASH_SOURCE[0]%/index.sh}/search.sh"

register_calendar_suite() {
	register_calendar_create
	register_calendar_list
	register_calendar_search
}
