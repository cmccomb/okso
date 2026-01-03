#!/usr/bin/env bash
# shellcheck shell=bash
#
# Aggregator for Apple Reminders tools.
#
# Usage:
#   source "${BASH_SOURCE[0]%/reminders/index.sh}/reminders/index.sh"
#
# Environment variables:
#   REMINDERS_LIST (string): target list within Apple Reminders.
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#
# Dependencies:
#   - bash 3.2+
#   - logging helpers from logging.sh
#   - register_tool utilities from tools/registry.sh
#
# Exit codes:
#   Functions emit errors via log and return non-zero when misused.

# shellcheck source=src/tools/reminders/common.sh
source "${BASH_SOURCE[0]%/index.sh}/common.sh"
# shellcheck source=src/tools/reminders/create.sh
source "${BASH_SOURCE[0]%/index.sh}/create.sh"
# shellcheck source=src/tools/reminders/list.sh
source "${BASH_SOURCE[0]%/index.sh}/list.sh"
# shellcheck source=src/tools/reminders/complete.sh
source "${BASH_SOURCE[0]%/index.sh}/complete.sh"

register_reminders_suite() {
	register_reminders_create
	register_reminders_list
	register_reminders_complete
}
