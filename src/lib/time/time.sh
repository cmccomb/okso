#!/usr/bin/env bash
# shellcheck shell=bash
#
# Local and UTC time helpers for prompt rendering.
#
# Usage:
#   source "${BASH_SOURCE[0]%/time.sh}/time.sh"
#
# Dependencies:
#   - bash 3.2+
#   - date (BSD date on macOS; GNU date also works)
#
# Exit codes:
#   Functions print derived values and return 0 on success.

# --- Local time (system timezone) ---

current_date_local() {
	date '+%Y-%m-%d'
}

current_time_local() {
	date '+%H:%M:%S'
}

current_weekday_local() {
	date '+%A'
}

# --- Exports ---

export -f current_date_local
export -f current_time_local
export -f current_weekday_local