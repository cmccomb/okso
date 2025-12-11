#!/usr/bin/env bash
set -euo pipefail

arg1="${1-}"
args="$*"

# Simulate curl for installer metadata and connectivity checks.
[[ "$args" == *"brew.sh"* ]] && exit 0

case "$arg1" in
-sI)
	printf 'HTTP/1.1 200 OK\nContent-Length: 15\n'
	;;
-fsL)
	printf '965e261385c7f1e8c7567e052cd56f4dc15530bf82a161140e8149338d10bbd5  model.gguf\n'
	;;
*) ;;
esac

exit 0
