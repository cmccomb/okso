#!/usr/bin/env bats
#
# Tests for path normalization and workspace boundary enforcement.
#
# Usage:
#   bats tests/tools/test_path_normalization.sh

@test "tools_normalize_path falls back when realpath lacks -m support" {
	run bash --noprofile --norc -c '
                set -euo pipefail

                unset -f chpwd _mise_hook __zsh_like_cd cd 2>/dev/null || true

                repo_root="$(git rev-parse --show-toplevel)"
                tmpdir="$(mktemp -d)"
                base_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

                cat >"${tmpdir}/realpath" <<"SCRIPT"
#!/usr/bin/env bash
# Simulate macOS/BSD realpath that does not accept -m.
echo "realpath: illegal option -- m" >&2
exit 1
SCRIPT
                chmod +x "${tmpdir}/realpath"

                expected="$(cd "${repo_root}" && python3 - <<"PY"
import os
print(os.path.realpath("README.md"))
PY
)"

                PATH="${tmpdir}:${base_path}" bash --noprofile --norc -c "
                        source \"${repo_root}/src/lib/tools.sh\"
                        cd \"${repo_root}\"
                        tools_normalize_path \"README.md\"
                " >"${tmpdir}/actual"

                diff -u <(printf "%s\n" "${expected}") "${tmpdir}/actual"
        '

	[ "$status" -eq 0 ]
}

@test "tools_normalize_path errors when python3 unavailable for fallback" {
	run bash --noprofile --norc -c '
                set -euo pipefail

                unset -f chpwd _mise_hook __zsh_like_cd cd 2>/dev/null || true

                repo_root="$(git rev-parse --show-toplevel)"
                tmpdir="$(mktemp -d)"
                base_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

                cat >"${tmpdir}/realpath" <<"SCRIPT"
#!/usr/bin/env bash
echo "realpath: illegal option -- m" >&2
exit 1
SCRIPT
                chmod +x "${tmpdir}/realpath"

                cat >"${tmpdir}/python3" <<"SCRIPT"
#!/usr/bin/env bash
echo "python3 unavailable" >&2
exit 127
SCRIPT
                chmod +x "${tmpdir}/python3"

                PATH="${tmpdir}:${base_path}" bash --noprofile --norc -c "
                        source \"${repo_root}/src/lib/tools.sh\"
                        cd \"${repo_root}\"
                        tools_normalize_path \"README.md\"
                "
        '

	[ "$status" -ne 0 ]
	[[ "${output}" == *"python3 is required for path normalization fallback"* ]]
}
