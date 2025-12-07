# Tools

The planner registers the following tools (each defined in `src/tools/<name>.sh`):

- `terminal`: persistent terminal session with a curated command set (pwd, ls, du, cd, cat, head, tail, find, grep, stat, wc, base64 encode/decode, mkdir, rmdir, mv, cp, touch, rm -i by default, plus `open` on macOS).
- `file_search`: search for files and contents using `fd`/`rg` fallbacks.
- `clipboard_copy`: copy provided text into the macOS clipboard.
- `clipboard_paste`: read the current macOS clipboard contents.
- `notes_create`: create a new Apple Note (first line = title).
- `notes_append`: append text to an existing Apple Note by title.
- `notes_list`: list note titles within the configured Apple Notes folder.
- `notes_search`: search Apple Notes titles and bodies for a phrase.
- `notes_read`: read an Apple Note's contents by title.
- `reminders_create`: create a new Apple Reminder (first line = title).
- `reminders_list`: list incomplete Apple Reminders in the configured list.
- `reminders_complete`: mark an Apple Reminder complete by title.
- `calendar_create`: create a new Apple Calendar event (line 1: title; line 2: start time; optional line 3: location).
- `calendar_list`: list upcoming Apple Calendar events for the configured calendar.
- `calendar_search`: search Apple Calendar events by title or location.
- `mail_draft`: create a new Apple Mail draft (line 1: recipients, line 2: subject).
- `mail_send`: compose and send an Apple Mail message immediately.
- `mail_search`: search Apple Mail inbox messages by subject, sender, or body.
- `mail_list_inbox`: list recent Apple Mail inbox messages.
- `mail_list_unread`: list unread Apple Mail inbox messages.
- `applescript`: execute AppleScript snippets on macOS (no-op elsewhere).

## Terminal tool

The `terminal` tool keeps a per-query working directory and reuses it across invocations so agents can `cd` once and continue running commands from the same location. Supported commands include `status` (default, shows the current directory and a listing), `pwd`, `ls`, `cd`, `cat`, `head`, `tail`, `find`, `grep`, `stat`, `wc`, `du` (defaults to `-sh .` when no arguments are provided), `base64` (requires an explicit `encode` or `decode` mode), and `open` on macOS hosts.

Mutation commands are guarded to reduce risk: `rm` always includes `-i` unless an interactive flag is already present, while `mkdir`, `rmdir`, `mv`, `cp`, and `touch` validate required arguments before executing.

## macOS helpers

Clipboard helpers are macOS-only and rely on `pbcopy`/`pbpaste`. Avoid copying credentials or other sensitive information because clipboard contents may be visible to other applications and logs.

Apple Notes tools expect the first line of `TOOL_QUERY` to be the note title and the remaining lines to form the body (where applicable). Set `NOTES_FOLDER` to point at a specific folder (default: `Notes`). On non-macOS hosts or when `osascript` is unavailable, the tools emit a warning and exit without changes.

Apple Calendar tools use `TOOL_QUERY` lines for event details: the first line is the title, the second is a human-friendly start time (parsed by AppleScript's `date`), and the third is an optional location. Set `CALENDAR_NAME` to direct operations to a specific calendar (default: `Calendar`). These tools only run on macOS with `osascript` available; otherwise, they log a warning and return without executing.

Apple Mail tools expect `TOOL_QUERY` lines to be structured as comma-separated recipients on the first line, a subject on the second, and the optional body on subsequent lines. The inbox listing tools respect `MAIL_INBOX_LIMIT` to cap results (default: 10).

## Ranking

Ranking builds a single compact prompt that lists every tool's name, description, safety note, and command. When `LLAMA_BIN` is available, `llama.cpp` returns the subset of tools to run (with scores and short justifications) in one call; otherwise a deterministic keyword heuristic is used. The resulting ranking is reused for the user-facing suggestion prompt and execution ordering.
