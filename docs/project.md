# Project

## Maintainers

`okso` is maintained by the core maintainers and community contributors.
For the current maintainer list and release stewardship, refer to the GitHub repository ownership and commit history.

## Support and contact

- **Documentation:** Start with the [documentation index](index.md) and the [README](../README.md) for installation and usage details.
- **Bugs and feature requests:** Open a GitHub issue with clear reproduction steps, logs, and environment details.
- **Development questions:** Review the contributor guides on [development](contributor/development.md) and [testing](contributor/testing.md) before opening a ticket.

## Contribution expectations

We welcome improvements to usability, documentation, tests, and core behavior.
Please align contributions with the existing workflow:

1. Follow the formatting, linting, and test steps in the [development guide](contributor/development.md).
2. Add or update tests as needed; see the [testing guide](contributor/testing.md).
3. Keep changes focused and document any user-facing updates in the docs.

## Release readiness checklist

Before cutting a release or merging high-impact changes, run:

```bash
find src scripts tests -type f \( -name '*.sh' -o -name 'okso' \) -print0 | xargs -0 shfmt -d
bash ./scripts/ci/run-shellcheck.sh
bash ./scripts/ci/run-bats.sh
bash ./scripts/ci/check-docs.sh
```
