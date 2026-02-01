# Tools

The planner registers these tools (implemented under `src/tools/`, with suites such as `src/tools/web/` grouping related helpers).
Handlers expect structured arguments in `TOOL_ARGS` that follow the registered JSON schema. Free-form, single-string payloads always
use the canonical `input` property so prompts and schemas can reference `args.input` consistently across tools:

- `terminal`: persistent working directory with `pwd`, `ls`, `cd`, `find`, `grep`, `stat`, `wc`, `du`, `date`, `base64 encode|decode`, and guarded mutations (`rm -i`, `mkdir`, `mv`, `cp`, `touch`). Uses `open` on macOS.
- `python_repl`: run Python snippets in an ephemeral sandbox using quiet `python -i` startup guards that confine writes.
- `web_search`: query the Google Custom Search API with a structured payload (`query` and optional `num`, default `5`, maximum `10`) and return JSON results.
- `web_fetch`: retrieve HTTP response bodies with a configurable size cap, returning JSON metadata (final URL, HTTP status, content type, headers, byte length, truncation flag, body encoding, body snippet, optional `body_markdown`, and anchor metadata). It only accepts a `url` argument and prefers normalized snippets from prior `web_search` results when available.
- `*_search`: Notes, Calendar, and Mail searches reuse the same `input` field for the search term.
- `notes_*`: create, append, list, read, or search Apple Notes entries.
- `reminders_*`: create, list, or complete Apple Reminders.
- `calendar_*`: create, list, or search Apple Calendar events.
- `mail_*`: draft, send, search, or list Apple Mail messages.
- `final_answer`: emit the assistant's final reply; the evaluator produces the response from the execution trace (no arguments required).
- `workflow_*`: pseudo-tools backed by `workflows/` specs. Each workflow expands into concrete tool steps during plan normalization; see [Workflows](#workflows) for schema and examples.

`web_fetch` responses include the final URL, HTTP status, content type, headers, byte length, a truncation flag, a preview snippet, anchor metadata (`anchor_query`, `anchor_match`), and a `body_markdown` field when text-like payloads can be converted. Text responses (HTML, JSON, XML, or plain text) are transformed into Markdown with previews truncated to 1024 characters. Non-text payloads are base64-encoded with `body_encoding` set to `base64` to avoid unsafe binary output. Conversion failures fall back to raw snippets with `body_markdown` set to `null`. When a fetch target is discovered via `web_search`, the preview centers on a normalized snippet (ellipses removed, whitespace collapsed, and shortened to a brief phrase).

For end-to-end scenarios that show how tools fit into approvals, see the [Run with approvals](../user-guides/usage.md#run-with-approvals) walkthrough.

## Workflows

Workflows are reusable tool sequences defined as JSON files under `workflows/`. Each workflow registers a pseudo-tool named `workflow_<name>` with an argument schema derived from the workflow's `parameters` field. During plan normalization, workflow steps are expanded so downstream systems see concrete tool steps.

### Workflow schema

```json
{
  "name": "weekly_status",
  "description": "Draft a weekly update.",
  "intents": ["notes"],
  "parameters": {
    "type": "object",
    "properties": {
      "project": { "type": "string" }
    },
    "required": ["project"],
    "additionalProperties": false
  },
  "steps": [
    {
      "tool": "terminal",
      "args": { "command": "echo \"Status for {{project}}\""} ,
      "thought": "Collect update data for {{project}}."
    }
  ]
}
```

### Interpolation

Workflow step `args` and `thought` values support `{{parameter}}` interpolation. Values are taken from the workflow tool arguments at invocation time.

### Intent tagging

Add an `intents` array to scope workflows to specific intent tool groups (for example, `["notes"]` or `["web","notes"]`). Supported values: `general`, `web`, `notes`, `reminders`, `calendar`, `mail`, `filesystem`, `coding`, `math`. When omitted, workflows default to `["general"]`, which only matches the general tool group.

### Invocation

When a plan contains a tool call such as `workflow_weekly_status`, the workflow loader replaces it with the concrete steps defined above, injecting any interpolated values before execution.

## Web search configuration

Configure the Google Custom Search-backed `web_search` tool with a local `.env` file so secrets stay out of source control:

```bash
# .env (keep this file in .gitignore)
OKSO_GOOGLE_CSE_API_KEY="your-google-api-key"
OKSO_GOOGLE_CSE_ID="your-cse-id"

set -a
source ./.env
set +a

# Run okso with web_search enabled; variables from .env override config values.
./src/bin/okso -- "collect recent release notes"
```

The exported variables are preferred over values in `config.env`, letting you keep API keys local while still allowing `okso init` to write non-secret defaults.

## Terminal tool

The `terminal` tool keeps a per-query working directory so subsequent calls share context. The default `status` command shows the current directory and a listing. Mutation commands validate arguments and keep `rm` interactive by default.

## Python REPL tool

`python_repl` feeds `TOOL_QUERY` to quiet `python -i` after installing a startup hook that changes into a temporary sandbox directory and wraps `open` so write modes only succeed inside that sandbox. On success it returns the interpreter output; uncaught exceptions exit non-zero and surface the traceback. Prefer short, single-purpose statements; long-running interpreters will be torn down once the session exits.

## macOS helpers

Notes, Reminders, Calendar, and Mail helpers rely on `osascript` and run only on macOS. They log a warning and exit without changes when the host is unsupported or when the required binaries are missing. Notes and Mail tools use line-based inputs (first line = title/recipients; later lines = body or options). Reminders lists return newline-delimited titles to preserve commas inside reminder names. Calendar tools expect title, start time, and optional location on separate lines.

## Ranking

When `LLAMA_BIN` is available, the planner asks `llama.cpp` to score tools with names, descriptions, commands, and key safety notes in a single prompt. Without `LLAMA_BIN`, a deterministic keyword heuristic ranks the tools. The resulting ordering drives suggestions and execution.
