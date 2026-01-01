[![CI - Unit](https://github.com/cmccomb/okso/actions/workflows/ci-unit.yml/badge.svg)](https://github.com/cmccomb/okso/actions/workflows/ci-unit.yml)
[![CI - Install](https://github.com/cmccomb/okso/actions/workflows/ci-install.yml/badge.svg)](https://github.com/cmccomb/okso/actions/workflows/ci-install.yml)
[![Deploy Installer](https://github.com/cmccomb/okso/actions/workflows/deploy_installer.yml/badge.svg)](https://github.com/cmccomb/okso/actions/workflows/deploy_installer.yml)

# `okso`, let's go to work

**A local-first, agentic CLI tool for macOS; a polite ghost in your machine.**  
okso helps small language models *operate* inside a desktop environment by routing intent → plans → tool calls, with an emphasis on repeatability, tight I/O, and “no surprises.”

## What it does

okso is a command-line interface that:
- turns a user request into a **structured plan**
- selects from a **tool registry** (terminal, files, notes, etc.)
- executes tool calls with **bounded side effects**
- emits a **final answer** (and can record it as an artifact)


## Installation

Use the macOS installer from the repository root to set up dependencies and place the `okso` CLI on your `PATH`:

```bash
./scripts/install.sh [--prefix /custom/path] [--upgrade | --uninstall]
```

You can also install directly from the hosted script:

```bash
curl -fsSL https://cmccomb.github.io/okso/install.sh | bash
```

For offline deployments, set `OKSO_INSTALLER_ASSUME_OFFLINE=true` and point
`OKSO_INSTALLER_BASE_URL` to a directory or URL containing `okso.tar.gz`; the
installer will expand the archive instead of cloning the repository.

See [docs/user-guides/installation.md](docs/user-guides/installation.md) for additional options and manual setup notes.

## Basic usage

See [docs/user-guides/usage.md](docs/user-guides/usage.md) for task-based walkthroughs (approvals, offline and configuration setup). Reference material lives in the [docs/](docs/index.md), including:

- [Execution model](docs/reference/execution-model.md): how planning and executor loops interact with tool calls.
- [Prompt assets](docs/reference/prompts.md): where prompts live and how they load.
- [Architecture overview](docs/reference/architecture.md): deeper look at the planner pass, executor loop, llama.cpp fallbacks, and tool ranking.


## Model autotuning

Model selection always runs through a deterministic autotune pipeline on macOS:

1. Detect stable resources (physical RAM via `sysctl -n hw.memsize`, GitHub Actions via `GITHUB_ACTIONS=true`).
2. Map resources → baseline tier (CI always maps to `ci`).
3. Sample runtime pressure signals (`memory_pressure`, `vm_stat`) to compute headroom.
4. Cap the baseline tier based on pressure/headroom and resolve models for each role.

Baseline tier mapping:

| Resources (macOS) | Baseline tier |
| --- | --- |
| `GITHUB_ACTIONS=true` | `ci` |
| `< 8 GB` | `tiny` |
| `8–16 GB` | `small` |
| `16–24 GB` | `default` |
| `24–48 GB` | `large` |
| `>= 48 GB` | `xlarge` |

Tier → model (Qwen3 GGUF Q4_K_M):

| Tier | task | default    | heavy      |
| --- | --- |------------|------------|
| `ci` / `tiny` | Qwen3-0.6B | Qwen3-0.6B | Qwen3-0.6B |
| `small` | Qwen3-0.6B | Qwen3-1.7B | Qwen3-4B   |
| `default` | Qwen3-1.7B | Qwen3-4B   | Qwen3-8B   |
| `large` | Qwen3-1.7B | Qwen3-8B   | Qwen3-14B  |
| `xlarge` | Qwen3-4B | Qwen3-14B  | Qwen3-32B  |

Runtime pressure caps ambition instead of shifting one tier at a time:

- `critical` pressure or `starved` headroom → cap at `tiny` (or `ci`).
- `warning` pressure or `tight` headroom → cap at `small` (or the smallest available tier).
- `normal` pressure and `comfortable` headroom → keep the baseline tier.
- Unknown signals fall back to the baseline tier.

Each run logs a concise summary, e.g. `model autotune: base=default eff=small (physmem=16GB, pressure=warning, headroom=tight)`.
