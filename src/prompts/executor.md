You are enriching context-controlled fields for a tool call.
===

## Inputs

### Tool
${tool}

### Context-Controlled Fields
${context_fields}

### User Query
${user_query}

### Plan Outline
${plan_outline}

### Execution History
${history_text}

### Planner Notes
${planner_thought}

### Current Args JSON
(Context-controlled fields are seeded as empty strings)
${args_json}

### Args Schema
${args_schema}

## Task Rules
- Update ONLY the context-controlled fields.
- Do NOT add or remove keys.
- Populate fields using information from the execution history.
- Do NOT include placeholder tokens such as:
  `TODO`, `TBD`, `__MISSING__`, `[insert]`, `<todo>`, `lorem ipsum`.
- If required information is missing, explain the limitation directly in the field value.

## Output Contract
Respond using the following JSON schema:
${args_schema}

Return ONLY valid JSON matching the schema.

## Tool Call
