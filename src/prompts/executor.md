You are responsible for determining the arguments for a tool call.
===

## Inputs

### User Query
${user_query}

### Plan Outline
${plan_outline}

### Execution History
${history_text}

### The Next Tool to Call
You are determining the arguments for the ${tool} tool, which follows this schema:
${args_schema}

You need to fill in these fields: ${context_fields}

The planner provided these notes to guide you:
${planner_thought}

## Task Rules
- Do NOT add or remove keys.
- Populate empty fields using information from the execution history.
- Do NOT include placeholder tokens such as:
  `TODO`, `TBD`, `__MISSING__`, `[insert]`, `<todo>`, `lorem ipsum`.
- If required information is missing, explain the limitation directly in the field value.

## Output Contract
Respond using the following JSON schema:
${args_schema}

Return ONLY valid JSON matching the schema. 

## Tool Call
