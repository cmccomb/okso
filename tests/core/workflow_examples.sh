#!/usr/bin/env bats

setup() {
	unset -f chpwd _mise_hook 2>/dev/null || true
	export VERBOSITY=0
}

@test "expand_workflow_plan expands daily briefing workflow" {
	run bash <<'SCRIPT'
set -euo pipefail
export WORKFLOWS_DIR=./workflows
source ./src/lib/executor/workflow_loader.sh
plan='[{"tool":"workflow_daily_briefing","args":{"topic":"ai policy","source_url":"https://example.com","note_title":"Daily Briefing"}}]'
expanded=$(expand_workflow_plan "${plan}")
printf '%s\n' "${expanded}" | jq -r '.[0].tool,.[1].tool,.[2].tool,.[3].tool,.[0].args.query,.[1].args.url,.[2].args.title'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "web_search" ]
	[ "${lines[1]}" = "web_fetch" ]
	[ "${lines[2]}" = "notes_create" ]
	[ "${lines[3]}" = "final_answer" ]
	[ "${lines[4]}" = "daily briefing ai policy" ]
	[ "${lines[5]}" = "https://example.com" ]
	[ "${lines[6]}" = "Daily Briefing" ]
}

@test "expand_workflow_plan expands research and summarize workflow" {
	run bash <<'SCRIPT'
set -euo pipefail
export WORKFLOWS_DIR=./workflows
source ./src/lib/executor/workflow_loader.sh
plan='[{"tool":"workflow_research_and_summarize","args":{"query":"battery recycling","source_url":"https://example.com","note_title":"Research notes"}}]'
expanded=$(expand_workflow_plan "${plan}")
printf '%s\n' "${expanded}" | jq -r '.[0].tool,.[1].tool,.[2].tool,.[3].tool,.[0].args.query,.[1].args.url,.[2].args.title'
SCRIPT

	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "web_search" ]
	[ "${lines[1]}" = "web_fetch" ]
	[ "${lines[2]}" = "notes_create" ]
	[ "${lines[3]}" = "final_answer" ]
	[ "${lines[4]}" = "battery recycling" ]
	[ "${lines[5]}" = "https://example.com" ]
	[ "${lines[6]}" = "Research notes" ]
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
