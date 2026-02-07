---
title: Okso Documentation
layout: default
description: Local-first automation for macOS
---

<div style="display:flex; justify-content:center;">
  <div class="okso-invoke" aria-label="ok, so...">
    <span class="okso-text">ok so&nbsp;</span><span class="okso-cursor" aria-hidden="true">_</span>
  </div>
</div>

<style>
  .okso-invoke{
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
    font-size: 56px;
    font-weight: 700;
    line-height: 1.05;
    letter-spacing: -0.02em;
    margin: 0;
    display: inline-flex;
    align-items: baseline;
    gap: 0.12em;
  }
  .okso-cursor{
    display: inline-block;
    transform: translateY(-0.06em);
    animation: okso-blink 1s steps(1, end) infinite;
  }
  @keyframes okso-blink{
    0%, 49% { opacity: 1; }
    50%, 100% { opacity: 0; }
  }

  /* Respect "reduce motion" */
  @media (prefers-reduced-motion: reduce){
    .okso-cursor{ animation: none; opacity: 1; }
  }
</style>

`okso` is a local-first automation toolkit for macOS that turns natural-language intent into reliable, reviewable command-line execution. It plans first, shows you what it will do, and then runs tools with guardrails and logs you can audit.

## Start here

- [Installation](user-guides/installation.md): install, upgrade, or uninstall the CLI.
- [Usage](user-guides/usage.md): run your first request, approvals, and CLI flags.
- [Configuration](reference/configuration.md): model specs, caches, and runtime overrides.

## What makes Okso different

- **Local-first LLMs**: llama.cpp-powered planning and execution keep data on your machine.
- **Plan before action**: a structured plan is generated and approved before any tool runs.
- **Guarded tools**: each tool has a strict schema and safety checks.
- **Transparent logs**: every step emits structured output you can inspect.

## How it works (high level)

1. Intent classification narrows the tool catalog and decides whether to gather web context.
2. A pre-planner web search (optional) gathers snippets to ground the plan.
3. The planner produces a structured tool-by-tool outline.
4. You approve (or refine) the plan before execution.
5. The executor runs each tool deterministically and records observations.
6. The final answer is generated from the execution trace (with optional evaluation and replanning).

## Documentation map

- [Architecture](reference/architecture.md): end-to-end flow and system boundaries.
- [Execution model](reference/execution-model.md): planner + executor lifecycle.
- [Tools](reference/tools.md): tool schemas, behaviors, and platform notes.
- [Prompts](reference/prompts.md): prompt templates and schema wiring.
- [Schemas](reference/schemas.md): JSON schema inventory and intent payloads.
- [Contributor guides](contributor/development.md): formatting, tests, and workflow notes.
- [Project overview](project.md): support, roadmap, and contribution expectations.
