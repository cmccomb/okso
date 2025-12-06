#!/usr/bin/env bash
# shellcheck shell=bash
#
# Mail stub tool that captures a draft for later delivery.
#
# Usage:
#   source "${BASH_SOURCE[0]%/tools/mail_stub.sh}/tools/mail_stub.sh"
#
# Environment variables:
#   TOOL_QUERY (string): message body to preserve.
#
# Dependencies:
#   - bash 5+
#   - logging helpers from logging.sh
#   - register_tool from tools/registry.sh
#
# Exit codes:
#   Returns non-zero only when registration is misused.

# shellcheck source=../logging.sh disable=SC1091
source "${BASH_SOURCE[0]%/tools/mail_stub.sh}/logging.sh"
# shellcheck source=./registry.sh disable=SC1091
source "${BASH_SOURCE[0]%/mail_stub.sh}/registry.sh"

tool_mail_stub() {
	local query
	query=${TOOL_QUERY:-""}
	log "INFO" "Mail stub invoked" "${query}"
	printf 'Mail delivery not configured. Draft preserved for review: %s\n' "${query}"
}

register_mail_stub() {
	register_tool \
		"mail_stub" \
		"Prepare an email draft for later delivery." \
		"cat > /tmp/mcp_mail_draft.txt" \
		"Does not send mail; safe placeholder." \
		tool_mail_stub
}
