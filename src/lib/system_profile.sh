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
#   - Apply pressure-aware caps to derive an effective tier per run.
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
#   - Optional: memory_pressure, vm_stat for headroom/pressure signals.
#
# Exit codes:
#   Functions emit non-zero status on argument errors; detection helpers are best-effort.

# shellcheck disable=SC2034
SYSTEM_PROFILE_LIB_DIR=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)

model_repo_for_size() {
	# Arguments:
	#   $1 - model size label (e.g., 0.6B, 1.7B, 4B)
	local size
	size="$1"

	printf 'bartowski/Qwen_Qwen3-%s-GGUF' "${size}"
}

model_file_for_size() {
	# Arguments:
	#   $1 - model size label (e.g., 0.6B, 1.7B, 4B)
	local size
	size="$1"

	printf 'Qwen_Qwen3-%s-Q4_K_M.gguf' "${size}"
}

normalize_bool_flag() {
	# Arguments:
	#   $1 - value to normalize
	case "$1" in
	1 | true | TRUE | True | yes | YES)
		printf '1'
		;;
	*)
		printf '0'
		;;
	esac
}

normalize_pressure_level() {
	# Arguments:
	#   $1 - raw pressure level
	case "$1" in
	normal | warning | critical)
		printf '%s' "$1"
		;;
	*)
		printf 'unknown'
		;;
	esac
}

normalize_headroom_class() {
	# Arguments:
	#   $1 - raw headroom class
	case "$1" in
	comfortable | tight | starved)
		printf '%s' "$1"
		;;
	*)
		printf 'unknown'
		;;
	esac
}

detect_physical_memory_bytes() {
	# Detect physical RAM in bytes using macOS sysctl.
	if ! command -v sysctl >/dev/null 2>&1; then
		return 1
	fi

	local raw
	raw=$(sysctl -n hw.memsize 2>/dev/null | tr -d '[:space:]') || return 1
	if [[ -z "${raw}" || ! "${raw}" =~ ^[0-9]+$ ]]; then
		return 1
	fi

	printf '%s' "${raw}"
}

detect_is_github_actions() {
	normalize_bool_flag "${GITHUB_ACTIONS:-0}"
}

map_resources_to_base_tier() {
	# Arguments:
	#   $1 - physical memory bytes (string int, required)
	#   $2 - is GitHub Actions flag (0/1, required)
	local phys_bytes is_gha mem_gb
	phys_bytes="$1"
	is_gha="$2"

	if [[ -z "${phys_bytes}" || -z "${is_gha}" ]]; then
		printf 'default'
		return 0
	fi

	if [[ "${is_gha}" == "1" ]]; then
		printf 'ci'
		return 0
	fi

	mem_gb=$((phys_bytes / 1024 / 1024 / 1024))

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

pressure_level_from_output() {
	# Arguments:
	#   $1 - memory_pressure command output
	local output level
	output="$1"

	level=$(printf '%s' "${output}" | awk -F': ' '/System-wide memory pressure level:/ {print tolower($2); exit}')
	if [[ -z "${level}" ]]; then
		level=$(printf '%s' "${output}" | awk -F': ' '/System-wide memory status:/ {print tolower($2); exit}')
	fi

	normalize_pressure_level "${level}"
}

headroom_ratio_from_vm_stat() {
	# Arguments:
	#   $1 - vm_stat output text
	local output page_size free_pages speculative_pages page_size_bytes free_bytes
	output="$1"

	page_size_bytes=$(printf '%s' "${output}" | awk '/page size of/ { if (match($0, /[0-9]+/)) { print substr($0, RSTART, RLENGTH); exit } }')
	if [[ -z "${page_size_bytes}" || ! "${page_size_bytes}" =~ ^[0-9]+$ ]]; then
		printf ''
		return
	fi
	free_pages=$(
		printf '%s' "$output" |
			awk '/Pages free/ {
      if (match($0, /[0-9]+/)) { print substr($0, RSTART, RLENGTH); exit }
    }'
	)

	speculative_pages=$(
		printf '%s' "$output" |
			awk '/Pages speculative/ {
      if (match($0, /[0-9]+/)) { print substr($0, RSTART, RLENGTH); exit }
    }'
	)
	free_pages=${free_pages:-0}
	speculative_pages=${speculative_pages:-0}

	if [[ ! "${free_pages}" =~ ^[0-9]+$ || ! "${speculative_pages}" =~ ^[0-9]+$ ]]; then
		printf ''
		return
	fi

	free_bytes=$(((free_pages + speculative_pages) * page_size_bytes))
	printf '%s' "${free_bytes}"
}

detect_pressure_level() {
	if ! command -v memory_pressure >/dev/null 2>&1; then
		printf 'unknown'
		return 0
	fi

	local output
	if ! output=$(memory_pressure 2>/dev/null); then
		printf 'unknown'
		return 0
	fi

	pressure_level_from_output "${output}"
}

estimate_headroom_class() {
	local phys_bytes output free_bytes ratio
	phys_bytes="${DETECTED_PHYS_MEM_BYTES:-}"

	if ! command -v vm_stat >/dev/null 2>&1; then
		printf 'unknown'
		return 0
	fi

	if [[ -z "${phys_bytes}" ]]; then
		phys_bytes=$(detect_physical_memory_bytes 2>/dev/null || printf '')
	fi

	if [[ -z "${phys_bytes}" ]]; then
		printf 'unknown'
		return 0
	fi

	if ! output=$(vm_stat 2>/dev/null); then
		printf 'unknown'
		return 0
	fi

	free_bytes=$(headroom_ratio_from_vm_stat "${output}")
	if [[ -z "${free_bytes}" ]]; then
		printf 'unknown'
		return 0
	fi

	ratio=$(awk -v free="${free_bytes}" -v total="${phys_bytes}" 'BEGIN { if (total == 0) { print ""; exit } printf "%.4f", free/total }')
	if [[ -z "${ratio}" ]]; then
		printf 'unknown'
		return 0
	fi

	awk -v r="${ratio}" 'BEGIN { if (r >= 0.30) { print "comfortable" } else if (r >= 0.10) { print "tight" } else { print "starved" } }'
}

cap_tier_for_pressure() {
	# Arguments:
	#   $1 - base tier
	#   $2 - pressure level
	#   $3 - headroom class
	local base pressure headroom
	base="$1"
	pressure="$(normalize_pressure_level "$2")"
	headroom="$(normalize_headroom_class "$3")"

	if [[ "${pressure}" == "critical" || "${headroom}" == "starved" ]]; then
		if [[ "${base}" == "ci" ]]; then
			printf 'ci'
			return 0
		fi
		printf 'tiny'
		return 0
	fi

	if [[ "${pressure}" == "warning" || "${headroom}" == "tight" ]]; then
		case "${base}" in
		ci)
			printf 'ci'
			;;
		tiny)
			printf 'tiny'
			;;
		*)
			printf 'small'
			;;
		esac
		return 0
	fi

	printf '%s' "${base}"
}

map_tier_to_models() {
	# Arguments:
	#   $1 - tier label
	# Returns:
	#   Three newline-delimited model size labels for task, default, and heavy.
	local tier
	tier="$1"

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
	local cache_home cache_file phys_bytes is_gha base_tier now_gb
	cache_home="${OKSO_CACHE_HOME:-${XDG_CACHE_HOME:-${HOME}/.cache}/okso}"
	cache_file="${cache_home}/system_profile.env"

	if [[ -f "${cache_file}" ]]; then
		# shellcheck source=/dev/null
		source "${cache_file}"
	fi

	if [[ -z "${DETECTED_PHYS_MEM_BYTES:-}" ]]; then
		phys_bytes=$(detect_physical_memory_bytes || printf '')
		if [[ -n "${phys_bytes}" ]]; then
			DETECTED_PHYS_MEM_BYTES="${phys_bytes}"
			now_gb=$((phys_bytes / 1024 / 1024 / 1024))
			DETECTED_PHYS_MEM_GB="${now_gb}"
		fi
	fi

	if [[ -z "${DETECTED_IS_GHA:-}" ]]; then
		is_gha=$(detect_is_github_actions)
		DETECTED_IS_GHA="${is_gha}"
	fi

	if [[ -z "${DETECTED_BASE_TIER:-}" && -n "${DETECTED_PHYS_MEM_BYTES:-}" ]]; then
		DETECTED_BASE_TIER=$(map_resources_to_base_tier "${DETECTED_PHYS_MEM_BYTES}" "${DETECTED_IS_GHA:-0}")
	fi

	if [[ -n "${DETECTED_PHYS_MEM_BYTES:-}" && -n "${DETECTED_IS_GHA:-}" && -n "${DETECTED_BASE_TIER:-}" ]]; then
		mkdir -p "${cache_home}"
		DETECTED_PROFILE_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
		cat >"${cache_file}" <<EOC
DETECTED_PHYS_MEM_BYTES="${DETECTED_PHYS_MEM_BYTES}"
DETECTED_PHYS_MEM_GB="${DETECTED_PHYS_MEM_GB:-}"
DETECTED_IS_GHA="${DETECTED_IS_GHA}"
DETECTED_BASE_TIER="${DETECTED_BASE_TIER}"
DETECTED_PROFILE_DATE="${DETECTED_PROFILE_DATE}"
EOC
	fi
}

resolve_autotune_model_sizes() {
	# Arguments:
	#   $1 - tier to resolve
	#   $2 - name of variable to receive task size
	#   $3 - name of variable to receive default size
	#   $4 - name of variable to receive heavy size
	local tier task_var default_var heavy_var sizes
	tier="$1"
	task_var="$2"
	default_var="$3"
	heavy_var="$4"

	mapfile -t sizes < <(map_tier_to_models "${tier}")
	printf -v "${task_var}" '%s' "${sizes[0]}"
	printf -v "${default_var}" '%s' "${sizes[1]}"
	printf -v "${heavy_var}" '%s' "${sizes[2]}"
}

export -f model_repo_for_size
export -f model_file_for_size
export -f detect_physical_memory_bytes
export -f detect_is_github_actions
export -f map_resources_to_base_tier
export -f detect_pressure_level
export -f estimate_headroom_class
export -f cap_tier_for_pressure
export -f map_tier_to_models
export -f load_or_detect_system_profile
export -f resolve_autotune_model_sizes
