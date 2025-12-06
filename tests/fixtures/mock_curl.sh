#!/usr/bin/env bash
set -euo pipefail

# Simulate curl for installer metadata and connectivity checks.
if [[ "$*" == *"brew.sh"* ]]; then
        exit 0
fi

if [[ "$1" == "-sI" ]]; then
        printf 'HTTP/1.1 200 OK\nContent-Length: 15\n'
        exit 0
fi

if [[ "$1" == "-fsL" ]]; then
        printf '965e261385c7f1e8c7567e052cd56f4dc15530bf82a161140e8149338d10bbd5  model.gguf\n'
        exit 0
fi

# Default success for other invocations.
exit 0
