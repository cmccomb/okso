#!/usr/bin/env bash
# shellcheck shell=bash
#
# System profile detection and model autotuning helpers.
#
# Usage:
#   source "${BASH_SOURCE[0]%/system_profile.sh}/system_profile.sh"
#
# Responsibilities:
#   - Detect stable hardware characteristics (physical RAM, CI environment).
#   - Map resources to baseline model tiers.
#   - Map tiers to model roles (task/default/heavy) using Qwen3 GGUF sizes.
#   - Persist stable detections to a cache file for reuse across invocations.
#
# Expected types:
#   DETECTED_PHYS_MEM_BYTES (string int): physical memory bytes detected from sysctl.
#   DETECTED_PHYS_MEM_GB (string int): physical memory in whole gigabytes.
#   DETECTED_IS_GHA (string int): 1 when GITHUB_ACTIONS=true, otherwise 0.
#   DETECTED_BASE_TIER (string): baseline tier derived from stable resources.
#
# Dependencies:
#   - bash 3.2+
#   - sysctl (macOS)
#   - Optional: none
#
# Exit codes:
#   Functions emit non-zero status on argument errors; detection helpers are best-effort.

# shellcheck disable=SC2034 # TD-001: dynamic globals are intentionally consumed across sourced modules and tests.
SYSTEM_PROFILE_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

model_repo_for_size() {
	# Provides the preferred HF repo name for a given model size.
	# Arguments:
	#   $1 - model size label (e.g., 0.6B, 1.7B, 4B)
	# Returns:
	#   HF repo name (string)
	local size
	size="$1"

	printf 'bartowski/Qwen_Qwen3-%s-GGUF' "${size}"
}

model_file_for_size() {
	# Provides the preferred GGUF filename for a given model size.
	# Arguments:
	#   $1 - model size label (e.g., 0.6B, 1.7B, 4B)
	# Returns:
	#   GGUF filename (string)
	local size
	size="$1"

	printf 'Qwen_Qwen3-%s-Q4_K_M.gguf' "${size}"
}

normalize_bool_flag() {
	# Normalizes various boolean-like inputs to 0/1.
	# Arguments:
	#   $1 - value to normalize
	# Returns:
	#   '1' for true-like inputs, '0' otherwise
	case "$1" in
	1 | true | TRUE | True | yes | YES)
		printf '1'
		;;
	*)
		printf '0'
		;;
	esac
}

detect_physical_memory_bytes() {
	# Detect physical RAM in bytes using macOS sysctl.
	# Returns:
	#   Physical memory in bytes (string int); empty on failure.

	# Run sysctl to get hw.memsize
	local raw
	raw=$(sysctl -n hw.memsize 2>/dev/null | tr -d '[:space:]')

	# Print result
	printf '%s' "${raw}"
}

detect_is_github_actions() {
	# Detect if running in GitHub Actions environment.
	# Returns:
	#   '1' if GITHUB_ACTIONS=true; '0' otherwise
	normalize_bool_flag "${GITHUB_ACTIONS:-0}"
}

map_resources_to_base_tier() {
	# Arguments:
	#   $1 - physical memory bytes (string int, required)
	#   $2 - is GitHub Actions flag (0/1, required)
	local phys_bytes is_gha mem_gb
	phys_bytes="$1"
	is_gha="$2"

	# Validate arguments
	if [[ -z "${phys_bytes}" || -z "${is_gha}" ]]; then
		printf 'default'
		return 0
	fi

	# CI environments get 'ci' tier
	if [[ "${is_gha}" == "1" ]]; then
		printf 'ci'
		return 0
	fi

	# Map physical memory to tier
	mem_gb=$((phys_bytes / 1024 / 1024 / 1024))

	# Determine tier based on memory size
	case ${mem_gb} in
	'' | *[^0-9]*)
		printf 'default'
		;;
	[0-7])
		printf 'tiny'
		;;
	8 | 9 | 10 | 11 | 12 | 13 | 14 | 15)
		printf 'small'
		;;
	16 | 17 | 18 | 19 | 20 | 21 | 22 | 23)
		printf 'default'
		;;
	24 | 25 | 26 | 27 | 28 | 29 | 30 | 31 | 32 | 33 | 34 | 35 | 36 | 37 | 38 | 39 | 40 | 41 | 42 | 43 | 44 | 45 | 46 | 47)
		printf 'large'
		;;
	*)
		printf 'xlarge'
		;;
	esac
}

map_tier_to_models() {
	# Map a tier label to model size labels for task, default, and heavy roles.
	# Arguments:
	#   $1 - tier label
	# Returns:
	#   Three newline-delimited model size labels for task, default, and heavy.
	local tier
	tier="$1"

	# Map tier to model sizes
	case "${tier}" in
	ci | tiny)
		printf '0.6B\n0.6B\n0.6B'
		;;
	small)
		printf '0.6B\n1.7B\n4B'
		;;
	default)
		printf '1.7B\n4B\n8B'
		;;
	large)
		printf '1.7B\n8B\n14B'
		;;
	xlarge)
		printf '4B\n14B\n32B'
		;;
	*)
		printf '1.7B\n4B\n8B'
		;;
	esac
}

load_or_detect_system_profile() {
	# Load cached system profile or detect and cache it.
	# Sets global variables:
	#   DETECTED_PHYS_MEM_BYTES
	#   DETECTED_PHYS_MEM_GB
	#   DETECTED_IS_GHA
	#   DETECTED_BASE_TIER
	# Returns:
	#   None.

	local phys_bytes is_gha base_tier now_gb
	cache_home="${OKSO_CACHE_HOME:-${XDG_CACHE_HOME:-${HOME}/.cache}/okso}"
	cache_file="${cache_home}/system_profile.env"

	# Load from cache if available
	if [[ -f "${cache_file}" ]]; then
		# shellcheck source=/dev/null
		source "${cache_file}"
	fi

	# Detect missing values
	if [[ -z "${DETECTED_PHYS_MEM_BYTES:-}" ]]; then
		phys_bytes=$(detect_physical_memory_bytes || printf '')
		if [[ -n "${phys_bytes}" ]]; then
			DETECTED_PHYS_MEM_BYTES="${phys_bytes}"
			now_gb=$((phys_bytes / 1024 / 1024 / 1024))
			DETECTED_PHYS_MEM_GB="${now_gb}"
		fi
	fi

	# Detect GHA status
	if [[ -z "${DETECTED_IS_GHA:-}" ]]; then
		is_gha=$(detect_is_github_actions)
		DETECTED_IS_GHA="${is_gha}"
	fi

	# Map resources to base tier
	if [[ -z "${DETECTED_BASE_TIER:-}" && -n "${DETECTED_PHYS_MEM_BYTES:-}" ]]; then
		DETECTED_BASE_TIER=$(map_resources_to_base_tier "${DETECTED_PHYS_MEM_BYTES}" "${DETECTED_IS_GHA:-0}")
	fi

	# Cache detections if all present
	if [[ -n "${DETECTED_PHYS_MEM_BYTES:-}" && -n "${DETECTED_IS_GHA:-}" && -n "${DETECTED_BASE_TIER:-}" ]]; then
		DETECTED_PROFILE_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
		if mkdir -p "${cache_home}" 2>/dev/null && [[ -w "${cache_home}" ]]; then
			if ! {
				cat <<EOC >"${cache_file}"
DETECTED_PHYS_MEM_BYTES="${DETECTED_PHYS_MEM_BYTES}"
DETECTED_PHYS_MEM_GB="${DETECTED_PHYS_MEM_GB:-}"
DETECTED_IS_GHA="${DETECTED_IS_GHA}"
DETECTED_BASE_TIER="${DETECTED_BASE_TIER}"
DETECTED_PROFILE_DATE="${DETECTED_PROFILE_DATE}"
EOC
			} 2>/dev/null; then
				:
			fi
		fi
	fi
}

resolve_autotune_model_sizes() {
	# Resolve model sizes for task, default, and heavy roles based on tier.
	# Arguments:
	#   $1 - tier to resolve
	#   $2 - name of variable to receive task size
	#   $3 - name of variable to receive default size
	#   $4 - name of variable to receive heavy size
	# Returns:
	#   None; sizes assigned to specified variable names.

	local tier task_var default_var heavy_var i line
	local task_val default_val heavy_val

	tier="$1"
	task_var="$2"
	default_var="$3"
	heavy_var="$4"

	i=0
	task_val=""
	default_val=""
	heavy_val=""

	# Map tier to model sizes
	while IFS= read -r line; do
		case "${i}" in
		0) task_val="${line}" ;;
		1) default_val="${line}" ;;
		2) heavy_val="${line}" ;;
		*) break ;;
		esac
		i=$((i + 1))
	done < <(map_tier_to_models "${tier}")

	: "${task_val:=1.7B}"
	: "${default_val:=4B}"
	: "${heavy_val:=8B}"

	printf -v "${task_var}" '%s' "${task_val}"
	printf -v "${default_var}" '%s' "${default_val}"
	printf -v "${heavy_var}" '%s' "${heavy_val}"
}

export -f model_repo_for_size
export -f model_file_for_size
export -f detect_physical_memory_bytes
export -f detect_is_github_actions
export -f map_resources_to_base_tier
export -f map_tier_to_models
export -f load_or_detect_system_profile
export -f resolve_autotune_model_sizes
