#!/usr/bin/env python3
"""Planner schema validation helpers.

This module validates planner plans against per-tool JSON Schemas. It supports
common JSON Schema keywords used by okso tools (type, required, properties,
items, additionalProperties, enum, minLength, maxLength, minimum, maximum,
minItems, minProperties, format).

Usage:
    python schema_validation.py --plan-json "<plan_array_json>" --tool-schemas "<schema_map_json>"

Exit codes:
    0 when validation succeeds, non-zero otherwise.
"""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any, Dict, Iterable, List, Tuple


def _is_integer(value: Any) -> bool:
    """Return True when value is an int but not a bool."""

    return isinstance(value, int) and not isinstance(value, bool)


def _type_matches(instance: Any, expected: str) -> bool:
    """Check if instance matches the expected JSON Schema type."""

    if expected == "object":
        return isinstance(instance, dict)
    if expected == "string":
        return isinstance(instance, str)
    if expected == "integer":
        return _is_integer(instance)
    if expected == "number":
        return _is_integer(instance) or isinstance(instance, float)
    if expected == "boolean":
        return isinstance(instance, bool)
    if expected == "array":
        return isinstance(instance, list)
    return False


def _validate_object(instance: Dict[str, Any], schema: Dict[str, Any], path: str) -> List[str]:
    errors: List[str] = []
    required = schema.get("required", [])
    properties = schema.get("properties", {})
    additional_properties = schema.get("additionalProperties", True)

    for field in required:
        if field not in instance:
            errors.append(f"{path}: missing required property '{field}'")

    for key, value in instance.items():
        key_path = f"{path}.{key}" if path else key
        if key in properties:
            errors.extend(validate_instance(value, properties[key], key_path))
        elif isinstance(additional_properties, dict):
            errors.extend(validate_instance(value, additional_properties, key_path))
        elif additional_properties is False:
            errors.append(f"{key_path}: additional properties are not allowed")

    min_properties = schema.get("minProperties")
    if isinstance(min_properties, int) and len(instance) < min_properties:
        errors.append(f"{path}: expected at least {min_properties} properties")

    return errors


def _validate_array(instance: List[Any], schema: Dict[str, Any], path: str) -> List[str]:
    errors: List[str] = []
    items_schema = schema.get("items")
    min_items = schema.get("minItems")

    if isinstance(min_items, int) and len(instance) < min_items:
        errors.append(f"{path}: expected at least {min_items} items")

    if isinstance(items_schema, dict):
        for idx, item in enumerate(instance):
            item_path = f"{path}[{idx}]"
            errors.extend(validate_instance(item, items_schema, item_path))

    return errors


def validate_instance(instance: Any, schema: Dict[str, Any], path: str = "") -> List[str]:
    """Validate an instance against a limited JSON Schema subset."""

    errors: List[str] = []
    expected_type = schema.get("type")

    if expected_type:
        if not _type_matches(instance, expected_type):
            errors.append(f"{path or '<root>'}: expected type {expected_type}")
            return errors

    if "enum" in schema and instance not in schema["enum"]:
        errors.append(f"{path or '<root>'}: value not permitted by enum")

    if expected_type == "string":
        min_length = schema.get("minLength")
        max_length = schema.get("maxLength")
        if isinstance(min_length, int) and len(instance) < min_length:
            errors.append(f"{path or '<root>'}: expected minimum length {min_length}")
        if isinstance(max_length, int) and len(instance) > max_length:
            errors.append(f"{path or '<root>'}: expected maximum length {max_length}")

    if expected_type in {"integer", "number"}:
        minimum = schema.get("minimum")
        maximum = schema.get("maximum")
        if minimum is not None and isinstance(minimum, (int, float)) and instance < minimum:
            errors.append(f"{path or '<root>'}: value below minimum {minimum}")
        if maximum is not None and isinstance(maximum, (int, float)) and instance > maximum:
            errors.append(f"{path or '<root>'}: value above maximum {maximum}")

    if expected_type == "object":
        errors.extend(_validate_object(instance, schema, path or "<root>"))

    if expected_type == "array":
        errors.extend(_validate_array(instance, schema, path or "<root>"))

    return errors


def validate_plan(plan: Iterable[Dict[str, Any]], tool_schemas: Dict[str, Dict[str, Any]]) -> Tuple[bool, List[str]]:
    """Validate each plan step against the registered tool schemas."""

    errors: List[str] = []

    for index, step in enumerate(plan):
        step_path = f"step[{index}]"
        tool = step.get("tool")
        if tool not in tool_schemas:
            errors.append(f"{step_path}: missing schema for tool '{tool}'")
            continue

        args = step.get("args")
        schema = tool_schemas[tool]
        if not isinstance(schema, dict) or not schema:
            errors.append(f"{step_path}: invalid schema definition for '{tool}'")
            continue

        errors.extend(validate_instance(args, schema, f"{step_path}.args"))

    return (len(errors) == 0, errors)


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description="Validate planner plans against tool schemas.")
    parser.add_argument("--plan-json", required=True, help="Planner plan JSON array")
    parser.add_argument("--tool-schemas", required=True, help="JSON object mapping tools to schemas")
    args = parser.parse_args(argv)

    try:
        plan_data = json.loads(args.plan_json)
        schema_map = json.loads(args.tool_schemas)
    except json.JSONDecodeError as exc:  # pragma: no cover - defensive parsing
        sys.stderr.write(f"Failed to parse JSON input: {exc}\n")
        return 1

    if not isinstance(plan_data, list):
        sys.stderr.write("Planner plan must be an array.\n")
        return 1
    if not isinstance(schema_map, dict):
        sys.stderr.write("Tool schema map must be an object.\n")
        return 1

    ok, validation_errors = validate_plan(plan_data, schema_map)
    if not ok:
        for err in validation_errors:
            sys.stderr.write(f"{err}\n")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
