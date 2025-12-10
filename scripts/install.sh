#!/usr/bin/env bash
# shellcheck shell=bash
#
# okso installer: macOS-only bootstrapper for the okso assistant.
#
# Usage:
#   scripts/install.sh [--prefix DIR] [--upgrade | --uninstall] [--dry-run] [--help]
#
# Environment variables:
#   DO_LINK_DIR (string): Directory for the PATH symlink. Defaults to
#       "/usr/local/bin".
#   DO_INSTALLER_SKIP_SELF_TEST (bool): Set to "true" to bypass the post-install
#       self-test (not recommended).
#
# Exit codes:
#   0: Success
#   1: Invalid usage
#   2: Dependency installation failed
#   3: Unsupported platform (non-macOS)
#   5: Filesystem permission error
#
# Dependencies:
#   - bash 5+
#   - curl
#   - Homebrew (https://brew.sh)

if [ -z "${BASH_VERSION:-}" ]; then
	exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

APP_NAME="okso"
DEFAULT_PREFIX="/usr/local/${APP_NAME}"
DEFAULT_LINK_DIR="${DO_LINK_DIR:-/usr/local/bin}"
DEFAULT_LINK_PATH="${DEFAULT_LINK_DIR}/${APP_NAME}"
DEFAULT_BASE_URL="https://cmccomb.github.io/okso"
SCRIPT_SOURCE="${BASH_SOURCE[0]-${0-}}"
if [ -z "${SCRIPT_SOURCE}" ] || [ "${SCRIPT_SOURCE}" = "-" ] || [ ! -f "${SCRIPT_SOURCE}" ]; then
	SCRIPT_DIR="${PWD}"
else
	SCRIPT_DIR=$(cd -- "$(dirname -- "${SCRIPT_SOURCE}")" && pwd)
fi
FORMULA_PATH="${SCRIPT_DIR}/okso.rb"
DRY_RUN="false"
INSTALL_PREFIX="${DEFAULT_PREFIX}"
MODE="install"

log() {
	# $1: level, $2: message
	printf '[%s] %s\n' "$1" "$2"
}

log_dry_run() {
	# $1: description of the skipped action
	if [ "${DRY_RUN}" = "true" ]; then
		printf '[DRYRUN] %s\n' "$1"
	fi
}

usage() {
	cat <<'EOF'
Usage: scripts/install.sh [--prefix DIR] [--upgrade | --uninstall] [--dry-run] [--help]

Options:
  --prefix DIR  Installation root (defaults to /usr/local/okso).
  --dry-run     Print the planned actions without executing them.
  --upgrade     Refresh the installation in place.
  --uninstall   Remove the okso installation and unlink the CLI.
  -h, --help    Show this help text.
EOF
}

detect_source_root() {
	local repo_root
	repo_root="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

	if [ -d "${repo_root}/src" ] && [ -f "${repo_root}/README.md" ]; then
		printf '%s\n' "${repo_root}"
		return 0
	fi

	printf ''
}

download_source_bundle() {
	local destination base_url tarball_url tarball_path extracted_root

	destination="$(mktemp -d)"
	base_url="${DO_INSTALLER_BASE_URL:-${DEFAULT_BASE_URL}}"
	tarball_url="${base_url%/}/okso.tar.gz"
	tarball_path="${destination}/okso.tar.gz"

	if ! curl -fsSL -o "${tarball_path}" "${tarball_url}"; then
		log "ERROR" "Failed to download okso bundle from ${tarball_url}"
		exit 2
	fi

	if ! tar -xzf "${tarball_path}" -C "${destination}"; then
		log "ERROR" "Failed to extract okso bundle"
		exit 2
	fi

	extracted_root="${destination}"
	if [ ! -d "${extracted_root}/src" ]; then
		extracted_root="$(find "${destination}" -maxdepth 2 -type d -name src -print0 2>/dev/null | xargs -0 dirname 2>/dev/null || true)"
	fi

	if [ -z "${extracted_root}" ] || [ ! -d "${extracted_root}/src" ]; then
		log "ERROR" "Extracted bundle is missing source tree"
		exit 2
	fi

	printf '%s\n' "${extracted_root}"
}

resolve_source_root() {
	local existing_root
	existing_root="$(detect_source_root)"

	if [ -n "${existing_root}" ]; then
		printf '%s\n' "${existing_root}"
		return 0
	fi

	if [ "${DO_INSTALLER_ASSUME_OFFLINE:-false}" = "true" ] && [ -z "${DO_INSTALLER_BASE_URL:-}" ]; then
		log "ERROR" "No source tree present and DO_INSTALLER_BASE_URL not set for offline install"
		exit 2
	fi

	download_source_bundle
}

detect_macos() {
	local uname_bin
	uname_bin=$(command -v uname || true)

	if [ -n "${uname_bin}" ] && [ "$(${uname_bin} -s)" = "Darwin" ]; then
		printf 'true\n'
		return 0
	fi

	printf 'false\n'
}

require_macos() {
	if [ "${IS_MACOS}" != "true" ]; then
		log "ERROR" "This installer only supports macOS."
		exit 3
	fi
}

ensure_homebrew() {
	if command -v brew >/dev/null 2>&1; then
		return 0
	fi

	log "ERROR" "Homebrew is required. Install from https://brew.sh and rerun the installer."
	exit 2
}

install_with_brew() {
	local help_output
	help_output="$(brew help install 2>/dev/null || true)"

	local brew_args
	brew_args=(install --formula)

	case "${help_output}" in
	*"--force"*) brew_args+=(--force) ;;
	esac

	case "${help_output}" in
	*"--overwrite"*) brew_args+=(--overwrite) ;;
	esac

	brew_args+=("${FORMULA_PATH}")

	log "INFO" "Installing ${APP_NAME} via Homebrew formula ${FORMULA_PATH}"
	if ! HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 brew "${brew_args[@]}"; then
		log "ERROR" "Failed to install ${APP_NAME} with Homebrew."
		exit 2
	fi
}

uninstall_with_brew() {
	if brew list --formula --versions "${APP_NAME}" >/dev/null 2>&1; then
		log "INFO" "Uninstalling ${APP_NAME} via Homebrew"
		brew uninstall --force "${APP_NAME}" >/dev/null 2>&1 || true
	else
		log "INFO" "${APP_NAME} is not installed via Homebrew; skipping uninstall"
	fi
}

resolve_install_prefix() {
	local prefix
	prefix=$(brew --prefix "${APP_NAME}" 2>/dev/null || true)
	if [ -n "${prefix}" ]; then
		printf '%s\n' "${prefix}"
		return 0
	fi

	prefix=$(brew --prefix 2>/dev/null || true)
	if [ -n "${prefix}" ] && [ -d "${prefix}/Cellar/${APP_NAME}" ]; then
		prefix=$(find "${prefix}/Cellar/${APP_NAME}" -maxdepth 1 -mindepth 1 -type d | sort | tail -n 1)
		if [ -n "${prefix}" ]; then
			printf '%s\n' "${prefix}"
			return 0
		fi
	fi

	log "ERROR" "Unable to determine Homebrew installation prefix for ${APP_NAME}."
	exit 2
}

ensure_link_dir_writable() {
	local link_dir="$1"

	if [ -w "${link_dir}" ]; then
		return 0
	fi

	if [ ! -d "${link_dir}" ]; then
		mkdir -p "${link_dir}" 2>/dev/null || true
	fi

	if [ -w "${link_dir}" ]; then
		return 0
	fi

	if command -v sudo >/dev/null 2>&1; then
		return 0
	fi

	log "ERROR" "Insufficient permissions to modify ${link_dir} and sudo not available."
	exit 5
}

link_binary() {
	# $1: installation prefix
	local prefix="$1"
	local target="${prefix}/bin/${APP_NAME}"

	if [ ! -x "${target}" ]; then
		log "ERROR" "Installed entrypoint missing at ${target}"
		exit 2
	fi

	local link_dir
	link_dir="$(dirname "${DEFAULT_LINK_PATH}")"
	ensure_link_dir_writable "${link_dir}"

	if [ -w "${link_dir}" ]; then
		mkdir -p "${link_dir}"
		ln -sf "${target}" "${DEFAULT_LINK_PATH}"
	else
		sudo mkdir -p "${link_dir}"
		sudo ln -sf "${target}" "${DEFAULT_LINK_PATH}"
	fi

	log "INFO" "Symlinked ${DEFAULT_LINK_PATH} -> ${target}"
}

copy_payload() {
	# $1: source root, $2: installation prefix
	local source_root="$1" prefix="$2" copy_target

	copy_target="${prefix}"
	mkdir -p "${copy_target}"

	if command -v rsync >/dev/null 2>&1; then
		rsync -a --delete "${source_root}/" "${copy_target}/"
	else
		tar -cf - -C "${source_root}" . | tar -xf - -C "${copy_target}"
	fi

	mkdir -p "${prefix}/bin"
	ln -sf "${prefix}/src/bin/${APP_NAME}" "${prefix}/bin/${APP_NAME}"
}

self_test_install() {
	# $1: installation prefix
	local prefix="$1" grammar_path_output temp_root query_output

	log "INFO" "Running installer self-test"

	if [ ! -x "${prefix}/src/bin/${APP_NAME}" ]; then
		log "ERROR" "Installed entrypoint is missing or not executable"
		exit 2
	fi

	if [ ! -f "${prefix}/src/grammars/planner_plan.schema.json" ]; then
		log "ERROR" "Planner grammar missing from installation"
		exit 2
	fi

	grammar_path_output="$(bash -c "source \"${prefix}/src/lib/grammar.sh\" && grammar_path planner_plan" 2>/dev/null || true)"
	if [ "${grammar_path_output}" != "${prefix}/src/grammars/planner_plan.schema.json" ]; then
		log "ERROR" "Grammar resolution failed during self-test"
		exit 2
	fi

	temp_root="$(mktemp -d "${TMPDIR:-/tmp}/okso-selftest-XXXXXX")"
	query_output=$(env \
		LLAMA_AVAILABLE=false \
		XDG_CONFIG_HOME="${temp_root}/config" \
		NOTES_DIR="${temp_root}/notes" \
		DEFAULT_MODEL_SPEC_BASE="self/test:model.gguf" \
		DEFAULT_MODEL_BRANCH_BASE="main" \
		DEFAULT_MODEL_FILE_BASE="model.gguf" \
		"${prefix}/src/bin/${APP_NAME}" --plan-only -- "Self-test query" 2>&1 || true)

	if [ -z "${query_output}" ]; then
		log "ERROR" "Self-test query produced no output"
		exit 2
	fi

	if ! printf '%s' "${query_output}" | grep -q "Plan outline"; then
		log "ERROR" "Self-test query did not complete as expected"
		exit 2
	fi

	log "INFO" "Installer self-test passed"
}

remove_symlink() {
	if [ -e "${DEFAULT_LINK_PATH}" ]; then
		if [ -w "${DEFAULT_LINK_PATH}" ]; then
			rm -f "${DEFAULT_LINK_PATH}"
		elif command -v sudo >/dev/null 2>&1; then
			sudo rm -f "${DEFAULT_LINK_PATH}"
		else
			log "ERROR" "Cannot remove ${DEFAULT_LINK_PATH}; insufficient permissions."
			exit 5
		fi
		log "INFO" "Removed symlink ${DEFAULT_LINK_PATH}"
	fi
}

main() {
	while [ $# -gt 0 ]; do
		case "$1" in
		--uninstall)
			MODE="uninstall"
			shift
			;;
		--upgrade)
			MODE="upgrade"
			shift
			;;
		--prefix)
			if [ $# -lt 2 ]; then
				usage
				exit 1
			fi
			INSTALL_PREFIX="$2"
			shift 2
			;;
		--dry-run)
			DRY_RUN="true"
			shift
			;;
		--help | -h)
			usage
			exit 0
			;;
		*)
			usage
			exit 1
			;;
		esac
	done

	if [ "${DRY_RUN}" = "true" ]; then
		log "INFO" "Dry run enabled; no changes will be made."
	fi

	require_macos

	if [ "${MODE}" = "uninstall" ]; then
		if [ "${DRY_RUN}" = "true" ]; then
			log_dry_run "Would remove symlink ${DEFAULT_LINK_PATH}"
			log_dry_run "Would remove installation prefix ${INSTALL_PREFIX}"
			log "INFO" "${APP_NAME} installer completed (dry-run uninstall)."
			exit 0
		fi

		remove_symlink
		if [ -d "${INSTALL_PREFIX}" ]; then
			rm -rf "${INSTALL_PREFIX}"
			log "INFO" "Removed ${INSTALL_PREFIX}"
		fi
		log "INFO" "${APP_NAME} installer completed (uninstall)."
		exit 0
	fi

	local source_root
	source_root="$(resolve_source_root)"

	if [ "${DRY_RUN}" = "true" ]; then
		log_dry_run "Would ensure Homebrew is available"
		log_dry_run "Would copy okso sources from ${source_root} to ${INSTALL_PREFIX}"
		log_dry_run "Would link ${APP_NAME} into ${DEFAULT_LINK_PATH}"
		log_dry_run "Would run installer self-test"
		log "INFO" "${APP_NAME} installer completed (dry-run ${MODE})."
		exit 0
	fi

	ensure_homebrew
	copy_payload "${source_root}" "${INSTALL_PREFIX}"
	link_binary "${INSTALL_PREFIX}"

	if [ "${DO_INSTALLER_SKIP_SELF_TEST:-false}" != "true" ]; then
		self_test_install "${INSTALL_PREFIX}"
	else
		log "WARN" "Skipping installer self-test due to DO_INSTALLER_SKIP_SELF_TEST"
	fi

	log "INFO" "${APP_NAME} installer completed (${MODE})."
}

IS_MACOS=$(detect_macos)
main "$@"
