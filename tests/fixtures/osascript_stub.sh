#!/usr/bin/env bash
set -euo pipefail
log_file="${NOTES_STUB_LOG:-${REMINDERS_STUB_LOG:-${MAIL_STUB_LOG:-${CALENDAR_STUB_LOG:-}}}}"
if [[ -n "${log_file}" ]]; then
	{
		printf 'ARGS:'
		printf ' %q' "$@"
		printf '\nSCRIPT<<EOF\n'
		cat
		printf 'EOF\n'
	} >>"${log_file}"
else
	cat >/dev/null
fi
printf 'stubbed\n'
