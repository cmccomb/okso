# Core utilities

This package contains foundational helpers that are shared across the assistant:

- `logging.sh` and `errors.sh` centralize structured diagnostics and fatal error helpers.
- `state.sh` and `json_state.sh` manage cached JSON state blobs used by runtime components.

Anything that is widely reused or underpins other modules should live here so higher-level
packages can depend on a single, well-defined core without introducing circular references.
