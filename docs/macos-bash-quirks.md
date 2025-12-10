# macOS Bash quirks

macOS still ships Bash 3.2, which lacks several modern Bash features. The
codebase intentionally targets that legacy shell to keep the installer and
runtime usable without requiring Homebrew's newer Bash.

## Legacy Bash 3.2 constraints

- The runtime avoids associative arrays and other Bash 4+ conveniences. Settings
  are stored as JSON blobs accessed through `jq`, allowing the scripts to run on
  the default macOS shell without feature flags.
- When running scripts manually, use the system `bash` to mirror the production
  environment; the code is written to behave correctly under macOS 3.2 builds.

## Path normalization on macOS

- BSD `realpath` on macOS does not support the GNU `-m` flag. `tools_normalize_path`
  probes for that flag and falls back to Python's `os.path.realpath` when it is
  unavailable so allowlist checks stay consistent across platforms.
- Tests simulate the macOS `realpath` behavior to ensure the Python fallback is
  exercised and returns the expected normalized paths.

## Writing new Bash helpers

When adding or editing Bash code, keep macOS compatibility in mind:

- Avoid associative arrays, `readarray/mapfile`, and other Bash 4+ features.
- Prefer POSIX/GNU-neutral flags; probe for macOS/BSD variants when needed.
- Add regression tests that cover the macOS code paths whenever you add a new
  fallback or platform-specific branch.
