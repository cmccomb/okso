# Tech Debt Register

This register tracks approved, time-bounded technical debt.

## Entry schema

Each entry must include:

- `id`: `TD-###`
- `severity`: `P0`, `P1`, or `P2`
- `area`: subsystem scope
- `file`: primary file path
- `owner`: responsible maintainer/team
- `rationale`: why debt exists
- `remediation`: concrete fix plan
- `due_milestone`: target milestone/date
- `validation`: command that proves closure

## Active entries

| id | severity | area | file | owner | rationale | remediation | due_milestone | validation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| TD-001 | P1 | Shell lint suppressions | `src/lib/settings/runtime.sh` | maintainers | `SC2034` is used for exported globals consumed across sourced modules and test harnesses. | Refactor shared-state contract to explicit getters or pass-by-arg interfaces, then remove suppressions. | 2026-Q2 | `bash ./scripts/ci/run-shellcheck.sh` |
| TD-002 | P1 | Test harness sourcing | `tests/lib/test_state.sh` | maintainers | `SC1091` suppressions are required for dynamic fixture sourcing in isolated temp directories. | Introduce deterministic static fixture paths or helper loader with explicit shellcheck includes. | 2026-Q2 | `bash ./scripts/ci/run-shellcheck.sh` |
| TD-003 | P2 | Test style cleanup | `tests/core/config.sh` | maintainers | `SC2155` suppressions exist where declaration+assignment is used for compact test setup. | Expand declarations to separate assignment statements where practical. | 2026-Q3 | `bash ./scripts/ci/run-shellcheck.sh` |
| TD-004 | P2 | Subshell variable semantics | `tests/planning/normalization.sh` | maintainers | `SC2030/SC2031` suppressions document deliberate subshell behavior assertions. | Rework assertions to avoid subshell mutation coupling. | 2026-Q3 | `bash ./scripts/ci/run-shellcheck.sh` |
| TD-005 | P2 | Test counting helpers | `tests/planning/rephrasing.sh` | maintainers | `SC2126` suppressions preserve compatibility in simple count checks. | Replace count pipelines with safer `grep -c` or `awk`-based assertions. | 2026-Q3 | `bash ./scripts/ci/run-shellcheck.sh` |
| TD-006 | P2 | Literal template strings | `src/tools/files/file_read.sh` | maintainers | `SC2016` suppression keeps literal `$` placeholders for templated snippets. | Centralize template rendering utility and avoid inline literal shell interpolation markers. | 2026-Q3 | `bash ./scripts/ci/run-shellcheck.sh` |
| TD-007 | P1 | LLM arg parsing | `src/lib/llm/llama_client.sh` | maintainers | `SC2206` suppression allows intentional word splitting into arrays for trusted arg strings. | Replace string splitting with structured parsing and remove dynamic split path. | 2026-Q2 | `bash ./scripts/ci/run-shellcheck.sh` |
| TD-008 | P2 | Terminal path parsing | `src/tools/terminal/index.sh` | maintainers | `SC2088` suppression preserves literal `~` handling semantics in command allowlist. | Normalize user home expansion before command dispatch to avoid literal tilde logic. | 2026-Q3 | `bash ./scripts/ci/run-shellcheck.sh` |
| TD-009 | P1 | Bats global variables | `tests/lib/test_llama_client.sh` | maintainers | grouped suppression (`SC2154,SC2016,SC2030,SC2031`) supports Bats-provided globals and literal heredoc content in test shells. | Split test helper files and narrow suppressions by scope with explicit wrapper helpers. | 2026-Q2 | `bash ./scripts/ci/run-shellcheck.sh` |
| TD-010 | P1 | Historical inline suppressions | `tests/**/*.sh` | maintainers | Existing suppressions predate standardized rationale/id format. | Normalize every suppression to include `TD-###` reference and clear rationale. | 2026-Q2 | `bash ./scripts/ci/audit-comments.sh` |
| TD-011 | P2 | Planner scope coupling | `src/lib/planning/planner.sh` | maintainers | `SC2153` suppression documents optional `TOOLS` injection from caller scope in sourced execution contexts. | Refactor planner tool catalog injection to an explicit function argument and remove scope-based lookup. | 2026-Q3 | `bash ./scripts/ci/run-shellcheck.sh` |
