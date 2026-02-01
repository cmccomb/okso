# Workflows

Workflows define reusable sequences of tools. Each workflow is stored as a JSON (`.json`) or YAML (`.yaml`/`.yml`) file in this directory. The loader parses every file and registers a pseudo-tool named `workflow_<name>` that expands into the workflow's step list during plan normalization.

## Schema

```json
{
  "name": "string (lowercase letters, numbers, underscores)",
  "description": "string",
  "parameters": {
    "type": "object",
    "properties": {
      "placeholder": { "type": "string" }
    },
    "required": ["placeholder"],
    "additionalProperties": false
  },
  "steps": [
    {
      "tool": "terminal",
      "args": { "command": "ls {{path}}" },
      "thought": "Optional planning note with {{placeholder}} interpolation."
    }
  ]
}
```

### Field reference

- `name` (string, required): Unique identifier used to register the pseudo-tool `workflow_<name>`.
- `description` (string, required): Human-readable summary surfaced in tool listings.
- `parameters` (object, optional): JSON Schema describing the arguments accepted by the workflow tool. Defaults to an empty object schema with `additionalProperties: false`.
- `steps` (array, required): List of tool steps. Each step requires:
  - `tool` (string): Tool name to execute.
  - `args` (object, optional): Structured arguments for the tool.
  - `thought` (string, optional): Internal note stored with the plan.

### Parameter interpolation

Step `args` and `thought` support simple string interpolation. Any `{{parameter_name}}` tokens are replaced with values from the workflow invocation arguments before execution.

## Example (YAML)

```yaml
name: onboarding_brief
description: Summarize new hire details and open a draft note.
parameters:
  type: object
  properties:
    teammate:
      type: string
  required:
    - teammate
  additionalProperties: false
steps:
  - tool: terminal
    args:
      command: "echo \"Welcome {{teammate}}\""
    thought: "Draft onboarding note for {{teammate}}."
  - tool: notes_create
    args:
      title: "Onboarding: {{teammate}}"
    thought: "Create the note."
```

## Example workflows

The following examples live in this directory and can be invoked via the `workflow_<name>` pseudo-tool:

- `daily-briefing.json` (`workflow_daily_briefing`): Search a topic, fetch a primary source, and save a daily briefing note.
- `research-and-summarize.json` (`workflow_research_and_summarize`): Research a query, fetch a source URL, and capture summary notes.
- `inbox-to-reminders.json` (`workflow_inbox_to_reminders`): List unread mail and create a follow-up reminder.

### Run via CLI

Use `--plan-only` to see the expanded steps without executing tools, or omit it to run the workflow.

```bash
./src/bin/okso --plan-only -- "Use workflow_daily_briefing with topic \"AI policy\" and source_url \"https://example.com\" and note_title \"Daily Briefing: AI policy\"."
./src/bin/okso --plan-only -- "Use workflow_research_and_summarize with query \"battery recycling\" and source_url \"https://example.com\" and note_title \"Research: Battery recycling\"."
./src/bin/okso --plan-only -- "Use workflow_inbox_to_reminders with reminder_title \"Reply to vendor\" and reminder_notes \"Follow up on pricing request\"."
```
