---
---

# Architecture

This page follows a typical run from the first prompt through tool execution so you can see where planning happens, when llama.cpp is invoked, and how tools are ranked and executed.

## End-to-end flow

<pre class="mermaid">
sequenceDiagram
    participant User
    participant CLI as okso CLI
    participant Planner
    participant Intent as Intent filter
    participant Llama as llama.cpp
    participant Approver as Approval prompts
    participant Executor as Executor
    participant Tool as Tool runner
    participant Trace as Trace/logs

    User->>CLI: Provide request
    CLI->>Intent: Classify intent + filter tool catalog
    Intent-->>Planner: Filtered tools + intent context
    CLI->>Planner: Build planner prompt (tools, guardrails)
    Planner->>Llama: Generate JSON plan (schema)
    Llama-->>Planner: Plan outline draft
    Planner-->>Approver: Show plan for confirmation/refinement
    Approver-->>Executor: Approved plan
    Executor->>Llama: Fill context-marked arguments (optional)
    Llama-->>Executor: Enriched arguments
    Executor->>Tool: Execute with sandbox/guards
    Tool-->>Trace: Stream stdout/stderr and status
    Trace-->>Executor: Observations captured
    Executor-->>User: Final answer once all steps complete
</pre>

## Planner pass

- Classifies intent before planning to optionally restrict the tool catalog and skip web search when not needed.
- Builds a structured prompt listing available tools, safety notes, and the user request.
- Requests a numbered outline with tool selections and short rationales using the JSON schema in [`src/schemas/planner_plan.schema.json`](../reference/schemas.md), plus intent context for compliance.
- Requires llama.cpp to generate and score candidate plans; if llama.cpp is unavailable, planning halts with an error (the pre-planner search stage still falls back to the raw query).
- Streams the plan to the terminal before moving to approvals.

## Executor

- Uses llama.cpp only to fill context-marked arguments; all required tool choices come from the planner.
- Executes the planned tool and streams observations; planner-specified context-controlled fields may be enriched by the executor LLM while all other required fields must be fully populated by the planner.
- When llama.cpp is unavailable, executes tools with the planner-provided arguments and skips LLM-based argument enrichment.
- Stops after `final_answer` emits the user-facing result or when a tool returns a fatal error.

### Step-by-step execution checklist

1. Load the approved plan and current step guidance.
2. Use the planned tool in order.
3. Run the tool with its sandbox (for example, the terminal's guarded `rm -i` or the Python REPL sandbox).
4. Record stdout/stderr and exit status for the execution summary.
5. Continue until all planned steps are replayed or `final_answer` is returned.

## llama.cpp dependency and fallbacks

- `LLAMA_BIN` controls the llama.cpp binary path. If it is unset or unavailable, okso cannot generate a plan; the pre-planner search stage still falls back to the raw user query.
- `PLANNER_MODEL_SPEC` and `EXECUTOR_MODEL_SPEC` select the model weights used by llama.cpp for planning and tool execution respectively; defaults are provided in [`configuration`](../reference/configuration.md).
- `TESTING_PASSTHROUGH=true` disables llama.cpp entirely for offline or CI runs; planner generation still requires llama.cpp, so use it only with tests or workflows that stub planner output.
- Planner and executor prompts both use the schemas in [`src/schemas/`](../reference/schemas.md) so that outputs stay parseable even when models vary.

## Tool ranking and execution

- Tool metadata (name, description, command, safety notes) is bundled into the planner prompt so llama.cpp can rank them for the outline and initial suggestions.
- Tool ordering comes directly from the planner output; there is no deterministic fallback ordering when planning cannot run.
- Each tool wrapper lives under `src/tools/` (with suites like `src/tools/web/` grouping related helpers) and enforces its own guards (sandboxed directories, platform checks, interactive deletes).
- The `terminal` tool keeps a persistent working directory per request, while helpers such as `python_repl` and macOS-specific tools run in isolated contexts.
- Traces and logs for each invocation help you audit decisions and replay failures.

<script type="module">
	import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
	mermaid.initialize({
		startOnLoad: true,
		theme: 'dark'
	});
</script>
