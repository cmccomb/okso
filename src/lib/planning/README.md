# Planning utilities

Planner-related helpers reside here, including the planner and responder flows, llama.cpp
client glue, schema resolution, and prompt builders. Modules in this package coordinate
model interactions and planning responses while relying on `../core` for logging/state and
`../cli` for user-facing output.

The ReAct loop now lives in `../react`. Existing callers that previously sourced
`planning/react.sh` still work through the compatibility shim in this directory, but new
entry points should source `../react/react.sh` directly. The planner populates plan
entries, schema constraints, and llama.cpp client wiring that the ReAct loop consumes to
execute tool calls and emit final answers.
