# Documentation Guidelines

This document provides concise, repo-wide recommendations for file headers, function docblocks, and workflow JSON documentation.

Bash file header template (place in the first 4-6 lines):
```
#!/usr/bin/env bash
# shellcheck shell=bash
# Short one-line purpose (what this file provides).
# Usage: example invocation or source pattern.
# Environment: LIST key env vars (one-line)
```

Function docblock template (for bash functions):
```
# One-line summary of the function's purpose.
# Arguments:
#   $1 - description of arg1
#   $2 - description of arg2
# Returns:
#   Description of return value and side-effects (stdout/json/exit code)
```

Workflow JSON guidance:

- Always include `name`, `description`, `parameters` (JSON Schema), and `steps`.
- For optional parameters that may be interpolated into step `args`, prefer providing a `default` (e.g., `"default": ""`) so renderers can substitute an empty string instead of leaving a literal placeholder.
- The loader strips unresolved `{{...}}` tokens and drops keys whose rendered values are empty or null; nevertheless prefer explicit defaults or omit optional args in example invocations.
- Add an example invocation file under `workflows/examples/` for each workflow that includes: one minimal required invocation, and one invocation showing optional fields present.

CI checks:
- Add `scripts/ci/check-docs.sh` to detect unresolved `{{...}}` tokens in workflows, TODO/TBD markers in docs, and missing shebang/header lines in shell scripts.
