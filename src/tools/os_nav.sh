#!/usr/bin/env bash
# shellcheck shell=bash
#
# Operating-system navigation tool for listing the current directory.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/os_nav.sh}/tools/os_nav.sh"
#
# Environment variables:
#   None
#
# Dependencies:
#   - bash 5+
#   - coreutils (ls, pwd)
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero only when registration is misused.

# shellcheck source=../logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/os_nav.sh}/logging.sh"
# shellcheck source=./registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/os_nav.sh}/registry.sh"

tool_os_nav() {
	log "INFO" "Running OS navigation" "Listing working directory"
	pwd
	ls -la
}

register_os_nav() {
	register_tool \
		"os_nav" \
		"Inspect the current working directory contents." \
		"pwd && ls -la" \
		"Read-only visibility of local filesystem." \
		tool_os_nav
}
