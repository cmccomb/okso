# Tools

The planner registers these tools (each implemented under `src/tools/<name>.sh`):

- `terminal`: persistent working directory with `pwd`, `ls`, `cd`, `find`, `grep`, `stat`, `wc`, `du`, `base64 encode|decode`, and guarded mutations (`rm -i`, `mkdir`, `mv`, `cp`, `touch`). Uses `open` on macOS.
- `python_repl`: run Python snippets in an ephemeral sandbox using quiet `python -i` startup guards that confine writes.
- `file_search`: search for files and contents using `fd`/`rg` fallbacks.
- `clipboard_copy` / `clipboard_paste`: macOS clipboard helpers.
- `notes_*`: create, append, list, read, or search Apple Notes entries.
- `reminders_*`: create, list, or complete Apple Reminders.
- `calendar_*`: create, list, or search Apple Calendar events.
- `mail_*`: draft, send, search, or list Apple Mail messages.
- `applescript`: execute AppleScript snippets on macOS (no-op elsewhere).
- `final_answer`: emit the assistant's final reply.

## Terminal tool

The `terminal` tool keeps a per-query working directory so subsequent calls share context. The default `status` command shows the current directory and a listing. Mutation commands validate arguments and keep `rm` interactive by default.

## Python REPL tool

`python_repl` feeds `TOOL_QUERY` to quiet `python -i` after installing a startup hook that changes into a temporary sandbox directory and wraps `open` so write modes only succeed inside that sandbox. On success it returns the interpreter output; uncaught exceptions exit non-zero and surface the traceback. Prefer short, single-purpose statements; long-running interpreters will be torn down once the session exits.

## macOS helpers

Clipboard, Notes, Reminders, Calendar, and Mail helpers rely on `osascript` and run only on macOS. They log a warning and exit without changes when the host is unsupported or when the required binaries are missing. Notes and Mail tools use line-based inputs (first line = title/recipients; later lines = body or options). Calendar tools expect title, start time, and optional location on separate lines.

## Ranking

When `LLAMA_BIN` is available, the planner asks `llama.cpp` to score tools with names, descriptions, commands, and key safety notes in a single prompt. Without `LLAMA_BIN`, a deterministic keyword heuristic ranks the tools. The resulting ordering drives suggestions and execution.
