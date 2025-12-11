# macOS Bash quirks

macOS still ships Bash 3.2. The codebase targets that shell so the installer and runtime work without requiring Homebrew's newer Bash.

## Legacy Bash 3.2 constraints

- Avoid associative arrays and other Bash 4+ features. Settings are stored as JSON and accessed via `jq` to stay compatible.
- When running scripts manually, use the system `bash` to mirror production behavior.

## Path normalization on macOS

- BSD `realpath` lacks the GNU `-m` flag. `tools_normalize_path` probes for support and falls back to Python's `os.path.realpath` when needed so allowlist checks stay consistent.
- Tests simulate the macOS `realpath` behavior to ensure the Python fallback returns the expected paths.

## Writing new Bash helpers

When adding or editing Bash code, keep macOS compatibility in mind:

- Prefer POSIX/GNU-neutral flags; probe for macOS/BSD variants when necessary.
- Add regression tests that cover macOS-specific branches and fallbacks.
