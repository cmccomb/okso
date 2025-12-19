"""State helper integration tests executed via subprocess."""
from __future__ import annotations

import os
import subprocess
from pathlib import Path


def run_bash(script: str, tmp_path: Path) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["TMPDIR"] = str(tmp_path)
    return subprocess.run(
        ["bash", "-lc", script],
        capture_output=True,
        text=True,
        check=True,
        env=env,
    )


def test_increment_updates_cache(tmp_path: Path) -> None:
    script = r'''
cd "$(git rev-parse --show-toplevel)" || exit 1
source ./src/lib/state.sh
prefix=py_counter
state_increment "${prefix}" "runs" 2
state_increment "${prefix}" "runs" 3
cache_path="$(json_state_cache_path "${prefix}")"
counter_value="$(state_get "${prefix}" "runs")"
cache_contents="$(cat "${cache_path}")"
printf "%s|%s" "${counter_value}" "${cache_contents}"
'''
    result = run_bash(script, tmp_path)
    assert result.stdout.strip() == '5|{"runs":5}'


def test_state_recovers_from_corrupt_cache(tmp_path: Path) -> None:
    script = r'''
cd "$(git rev-parse --show-toplevel)" || exit 1
source ./src/lib/state.sh
prefix=py_repair
cache_path="$(json_state_cache_path "${prefix}")"
state_set_json_document "${prefix}" '{"count":1}'
printf '{corrupt' >"${cache_path}"
repaired="$(state_get_json_document "${prefix}" '{"count":1}')"
printf "%s" "${repaired}"
'''
    result = run_bash(script, tmp_path)
    assert result.stdout.strip() == '{"count":1}'
