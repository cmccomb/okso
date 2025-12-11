#!/usr/bin/env bats
#
# Tests for tools_normalize_path behavior across platforms.
#
# Usage: bats tests/tools/test_tools_normalize_path.bats
#
# Dependencies:
#   - bats
#   - bash 5+
#
# Exit codes:
#   Inherits Bats semantics; individual tests assert script exit codes explicitly.

@test "tools_normalize_path falls back when realpath lacks -m support" {
	run bash -lc '
                set -euo pipefail

                repo_root="$(git rev-parse --show-toplevel)"
                tmpdir="$(mktemp -d)"

                cat >"${tmpdir}/realpath" <<"SCRIPT"
#!/usr/bin/env bash
# Simulate macOS/BSD realpath that does not accept -m.
echo "realpath: illegal option -- m" >&2
exit 1
SCRIPT
                chmod +x "${tmpdir}/realpath"

                expected="$(cd "${repo_root}" && python - <<"PY"
import os
print(os.path.realpath("README.md"))
PY
)"

                PATH="${tmpdir}:${PATH}" bash -lc "
                        source \"${repo_root}/src/lib/tools.sh\"
                        cd \"${repo_root}\"
                        tools_normalize_path \"README.md\"
                " >"${tmpdir}/actual"

                diff -u <(printf "%s\n" "${expected}") "${tmpdir}/actual"
        '

	[ "$status" -eq 0 ]
}
