#!/usr/bin/env bash
# shellcheck shell=bash
#
# Aggregator for Apple Mail tools.
#
# Usage:
#   source "${BASH_SOURCE[0]%/mail/index.sh}/mail/index.sh"
#
# Environment variables:
#   IS_MACOS (bool): indicates whether macOS-specific tooling should run.
#   MAIL_OSASCRIPT_BIN (string): override path for osascript; defaults to "osascript".
#   MAIL_INBOX_LIMIT (int): maximum results to return when listing inbox entries.
#
# Dependencies:
#   - bash 3.2+
#   - logging helpers from logging.sh
#   - register_tool utilities from tools/registry.sh
#
# Exit codes:
#   Functions emit errors via log and return non-zero when misused.

# shellcheck source=src/tools/mail/common.sh
source "${BASH_SOURCE[0]%/index.sh}/common.sh"
# shellcheck source=src/tools/mail/draft.sh
source "${BASH_SOURCE[0]%/index.sh}/draft.sh"
# shellcheck source=src/tools/mail/send.sh
source "${BASH_SOURCE[0]%/index.sh}/send.sh"
# shellcheck source=src/tools/mail/search.sh
source "${BASH_SOURCE[0]%/index.sh}/search.sh"
# shellcheck source=src/tools/mail/list_inbox.sh
source "${BASH_SOURCE[0]%/index.sh}/list_inbox.sh"
# shellcheck source=src/tools/mail/list_unread.sh
source "${BASH_SOURCE[0]%/index.sh}/list_unread.sh"

register_mail_suite() {
	register_mail_draft
	register_mail_send
	register_mail_search
	register_mail_list_inbox
	register_mail_list_unread
}
