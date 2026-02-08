#!/usr/bin/env bats
# shellcheck shell=bash
# Test coverage for workflow_examples.sh.

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	export VERBOSITY=0
}

@test "expand_workflow_plan expands daily briefing workflow" {
	run bash <<'SCRIPT'
set -euo pipefail
export WORKFLOWS_DIR=./workflows
source ./src/lib/executor/workflow_loader.sh
plan='[{"tool":"workflow_daily_briefing","args":{"current_date":"2026-02-06"}}]'
expanded=$(expand_workflow_plan "${plan}")
printf '%s\n' "${expanded}" | jq -r '.[0].tool,.[1].tool,.[2].tool,.[3].tool,.[4].tool,.[5].tool,.[0].args.query'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "web_search" ]
	[ "${lines[1]}" = "web_search" ]
	[ "${lines[2]}" = "web_search" ]
	[ "${lines[3]}" = "web_search" ]
	[ "${lines[4]}" = "web_search" ]
	[ "${lines[5]}" = "final_answer" ]
	[ "${lines[6]}" = "top headlines after:2026-02-06" ]
}

@test "expand_workflow_plan expands research workflow" {
	run bash <<'SCRIPT'
set -euo pipefail
export WORKFLOWS_DIR=./workflows
source ./src/lib/executor/workflow_loader.sh
plan='[{"tool":"workflow_research","args":{"query":"battery recycling"}}]'
expanded=$(expand_workflow_plan "${plan}")
printf '%s\n' "${expanded}" | jq -r '.[0].tool,.[1].tool,.[2].tool,.[3].tool,.[4].tool,.[5].tool,.[0].args.query.__fill__'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "web_search" ]
	[ "${lines[1]}" = "web_search" ]
	[ "${lines[2]}" = "web_fetch" ]
	[ "${lines[3]}" = "web_fetch" ]
	[ "${lines[4]}" = "web_fetch" ]
	[ "${lines[5]}" = "final_answer" ]
	[ "${lines[6]}" = "true" ]
}

@test "expand_workflow_plan expands inbox to reminders workflow" {
	run bash <<'SCRIPT'
set -euo pipefail
export WORKFLOWS_DIR=./workflows
source ./src/lib/executor/workflow_loader.sh
plan='[{"tool":"workflow_inbox_to_reminders","args":{"reminder_title":"Reply to vendor","reminder_notes":"Follow up"}}]'
expanded=$(expand_workflow_plan "${plan}")
printf '%s\n' "${expanded}" | jq -r '.[0].tool,.[1].tool,.[2].tool,.[0].args,.[1].args.title,.[1].args.notes,.[2].args'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "mail_list_unread" ]
	[ "${lines[1]}" = "reminders_create" ]
	[ "${lines[2]}" = "final_answer" ]
	[ "${lines[3]}" = "{}" ]
	[ "${lines[4]}" = "Reply to vendor" ]
	[ "${lines[5]}" = "Follow up" ]
	[ "${lines[6]}" = "{}" ]
}
