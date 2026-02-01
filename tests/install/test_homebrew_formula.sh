#!/usr/bin/env bats
# shellcheck shell=bash
#
# Tests for the Homebrew formula to ensure the tap is installable and points to
# a tagged release rather than a moving branch.

setup() {
	FORMULA_PATH="$(cd -- "$(dirname -- "${BATS_TEST_FILENAME}")/../.." && pwd)/Formula/okso.rb"
}

@test "formula uses tagged release tarball" {
	run grep -E 'url "https://github.com/cmccomb/okso/archive/refs/tags/v[0-9.]+' "${FORMULA_PATH}"
	[ "$status" -eq 0 ]
	[[ "$output" != *"refs/heads"* ]]
}

@test "formula declares Homebrew dependencies" {
	for dep in docx2txt jq libxml2 llama.cpp pandoc poppler ripgrep ripgrep-all tesseract; do
		run grep -E "depends_on \"${dep}\"" "${FORMULA_PATH}"
		[ "$status" -eq 0 ]
	done
}

@test "formula test block exercises okso version" {
	run sed -n '/test do/,/end/p' "${FORMULA_PATH}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"okso --version"* ]]
}
