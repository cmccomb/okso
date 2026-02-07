# Code Quality Standards

This document defines the required comment, consistency, and technical-debt controls for the `okso` repository.

## Scope

These rules apply to:

- `src/`
- `tests/`
- `scripts/`
- `workflows/`
- contributor-facing documentation in `docs/`

## File header requirements

### `src/` and `scripts/`

Shell files in `src/` and `scripts/` (`*.sh` and `src/bin/okso`) must include these first lines:

```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# One-line purpose.
# Usage: ...
```

### `tests/`

Shell tests and fixtures in `tests/` (`*.sh`) must include at least:

```bash
#!/usr/bin/env bash
# shellcheck shell=bash
# One-line purpose.
```

Bats files may use `#!/usr/bin/env bats` and still require `# shellcheck shell=bash` and a one-line purpose line.

## Function docblock requirements (`src/lib/**`)

Shared functions in `src/lib/**` must include a concise docblock directly above the function with:

- one-line summary
- `Arguments:` section when arguments are used
- `Returns:` section describing output/exit behavior and side effects

Template:

```bash
# One-line summary.
# Arguments:
#   $1 - ...
# Returns:
#   stdout/side effects/exit code semantics.
```

## Suppression policy (`shellcheck disable`)

Every `shellcheck disable` directive must include:

- an explicit rationale
- a debt identifier in the form `TD-###`

Valid format:

```bash
# shellcheck disable=SC2034 # TD-001: variable intentionally consumed by sourced test harness.
```

Rules:

- No bare suppressions.
- Grouped suppressions are allowed, but still require a single `TD-###` reference and rationale.
- Debt ids must exist in `docs/contributor/tech-debt-register.md`.

## Marker-token policy

Unresolved authoring markers are prohibited outside explicitly approved examples:

- `TODO`
- `TBD`
- `__MISSING__`
- `[insert]`
- `<todo>`
- `lorem ipsum`

## CI policy

The following commands are required pre-PR and are enforced by CI:

```bash
find src scripts tests -type f \( -name '*.sh' -o -name 'okso' \) -print0 | xargs -0 shfmt -d
bash ./scripts/ci/run-shellcheck.sh
bash ./scripts/ci/run-bats.sh
bash ./scripts/ci/check-docs.sh
bash ./scripts/ci/audit-comments.sh
bash ./scripts/ci/audit-consistency.sh
```

## Enforcement level

- New violations fail CI.
- Temporary exceptions must be documented in the debt register and referenced with `TD-###`.
