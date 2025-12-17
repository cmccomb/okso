#!/usr/bin/env bats
# Regression tests for extracting structured JSON logs from mixed output.

load log_parsing.sh

@test "parse_json_logs ignores boxed summaries appended to structured logs" {
        # Arrange: mix compact JSON entries, stray text, and a boxed summary block.
        mixed_output=$'{"message":"Planner identified tools","detail":"tool-a"}\n'\
'noise line\n'\
$'{"message":"Final answer","detail":"Done"}\n'\
$'┌─────────────\n'\
$'│ Final answer\n'\
$'└─────────────'

        # Act
        parsed_logs=$(parse_json_logs <<<"${mixed_output}")

        # Assert
        [ "$(jq length <<<"${parsed_logs}")" -eq 2 ]
        [[ "$(jq -r '.[0].message' <<<"${parsed_logs}")" == "Planner identified tools" ]]
        [[ "$(jq -r '.[1].detail' <<<"${parsed_logs}")" == "Done" ]]
}

@test "parse_json_logs handles pretty-printed JSON blocks" {
        # Arrange: pretty JSON followed by a boxed recap.
        pretty_json=$'{\n  "message": "Final answer",\n  "detail": "Great success"\n}\n'\
$'┌───────\n'\
$'│ Final\n'\
$'└───────'

        # Act
        parsed_logs=$(parse_json_logs <<<"${pretty_json}")

        # Assert
        [ "$(jq length <<<"${parsed_logs}")" -eq 1 ]
        [[ "$(jq -r '.[0].detail' <<<"${parsed_logs}")" == "Great success" ]]
}
