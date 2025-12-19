#!/usr/bin/env bash
# shellcheck shell=bash
#
# okso installer: macOS-only bootstrapper for the okso assistant.
#
# Usage:
#   scripts/install.sh [--prefix DIR] [--upgrade | --uninstall] [--dry-run] [--help]
#
# Environment variables:
#   OKSO_LINK_DIR (string): Directory for the PATH symlink. Defaults to
#       "/usr/local/bin".
#   OKSO_INSTALLER_ASSUME_OFFLINE (bool): Do not attempt a network clone. Requires
#       a local okso checkout next to this script (../src + ../README.md).
#   OKSO_INSTALLER_BASE_URL (string): Git repository URL (or local path) to clone
#       when no local checkout is present.
#
# Exit codes:
#   0: Success
#   1: Invalid usage
#   2: Dependency installation failed
#   3: Unsupported platform (non-macOS)
#   5: Filesystem permission error :(
#
# Dependencies:
#   - bash 5+
#   - git
#   - curl
#   - Homebrew (https://brew.sh)

if [ -z "${BASH_VERSION:-}" ]; then
	exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

APP_NAME="okso"
DEFAULT_PREFIX="/usr/local/${APP_NAME}"
DEFAULT_LINK_DIR="${OKSO_LINK_DIR:-/usr/local/bin}"
DEFAULT_LINK_PATH="${DEFAULT_LINK_DIR}/${APP_NAME}"
DEFAULT_BASE_URL="https://github.com/cmccomb/okso"
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

ensure_git() {
	if command -v git >/dev/null 2>&1; then
		return 0
	fi

	log "ERROR" "git is required for installation (needed to clone the okso repository)."
	log "ERROR" "Install Xcode Command Line Tools with: xcode-select --install"
	exit 2
}

clone_source_repo() {
	local destination base_url clone_dir marker

	if [ "${OKSO_INSTALLER_ASSUME_OFFLINE:-false}" = "true" ]; then
		log "ERROR" "Offline mode is enabled and no local okso checkout was found."
		exit 2
	fi

	ensure_git

	destination="$(mktemp -d "${TMPDIR:-/tmp}/okso-install-XXXXXX")"
	base_url="${OKSO_INSTALLER_BASE_URL:-${DEFAULT_BASE_URL}}"
	clone_dir="${destination}/repo"
	marker="${destination}/.okso_installer_tmp"
	: >"${marker}"

	if ! git clone --depth 1 "${base_url}" "${clone_dir}"; then
		log "ERROR" "Failed to clone okso repository from ${base_url}"
		rm -rf "${destination}" >/dev/null 2>&1 || true
		exit 2
	fi

	printf '%s\n' "${clone_dir}"
}

resolve_source_root() {
	local existing_root
	existing_root="$(detect_source_root)"

	if [ -n "${existing_root}" ]; then
		printf '%s\n' "${existing_root}"
		return 0
	fi

	if [ "${OKSO_INSTALLER_ASSUME_OFFLINE:-false}" = "true" ]; then
		log "ERROR" "No source tree present and offline mode enabled; cannot proceed."
		exit 2
	fi

	clone_source_repo
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

prefix_writable() {
	local dir="$1" probe
	[ -d "${dir}" ] || return 1
	probe="${dir}/.okso-installer-probe.$$"
	if (: >"${probe}") 2>/dev/null; then
		rm -f "${probe}" >/dev/null 2>&1 || true
		return 0
	fi
	return 1
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
	local source_root="$1" prefix="$2" copy_target sudo_cmd probe

	copy_target="${prefix}"
	sudo_cmd=""

	# Ensure destination exists.
	if ! mkdir -p "${copy_target}" 2>/dev/null; then
		if command -v sudo >/dev/null 2>&1; then
			sudo_cmd="sudo"
			sudo mkdir -p "${copy_target}"
		else
			log "ERROR" "Insufficient permissions to create ${copy_target}. Re-run with sudo or pass --prefix to a writable directory."
			exit 5
		fi
	fi

	# Determine whether we can write into the destination; if not, use sudo for the payload copy.
	if ! prefix_writable "${copy_target}"; then
		if command -v sudo >/dev/null 2>&1; then
			sudo_cmd="sudo"
		else
			log "ERROR" "Insufficient permissions to write into ${copy_target}. Re-run with sudo or pass --prefix to a writable directory."
			exit 5
		fi
	fi

	if command -v rsync >/dev/null 2>&1; then
		if [ -n "${sudo_cmd}" ]; then
			sudo rsync -a --delete "${source_root}/" "${copy_target}/"
		else
			rsync -a --delete "${source_root}/" "${copy_target}/"
		fi
	else
		if [ -n "${sudo_cmd}" ]; then
			tar -cf - -C "${source_root}" . | sudo tar -xf - -C "${copy_target}"
		else
			tar -cf - -C "${source_root}" . | tar -xf - -C "${copy_target}"
		fi
	fi

	if [ -n "${sudo_cmd}" ]; then
		sudo mkdir -p "${prefix}/bin"
		sudo ln -sf "${prefix}/src/bin/${APP_NAME}" "${prefix}/bin/${APP_NAME}"
	else
		mkdir -p "${prefix}/bin"
		ln -sf "${prefix}/src/bin/${APP_NAME}" "${prefix}/bin/${APP_NAME}"
	fi
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

	require_macos

	if [ "${DRY_RUN}" = "true" ]; then
		log "INFO" "Dry run enabled; no changes will be made."
		local local_root base_url
		local_root="$(detect_source_root)"
		base_url="${OKSO_INSTALLER_BASE_URL:-${DEFAULT_BASE_URL}}"

		log_dry_run "Would ensure Homebrew is available"
		if [ -n "${local_root}" ]; then
			log_dry_run "Would copy okso sources from ${local_root} to ${INSTALL_PREFIX}"
		else
			log_dry_run "Would git clone ${base_url} and copy sources to ${INSTALL_PREFIX}"
		fi
		log_dry_run "Would link ${APP_NAME} into ${DEFAULT_LINK_PATH}"
		log "INFO" "${APP_NAME} installer completed (dry-run ${MODE})."
		exit 0
	fi

	if [ "${MODE}" = "uninstall" ]; then
		remove_symlink
		if [ -d "${INSTALL_PREFIX}" ]; then
			if rm -rf "${INSTALL_PREFIX}" 2>/dev/null; then
				log "INFO" "Removed ${INSTALL_PREFIX}"
			elif command -v sudo >/dev/null 2>&1; then
				sudo rm -rf "${INSTALL_PREFIX}"
				log "INFO" "Removed ${INSTALL_PREFIX}"
			else
				log "ERROR" "Cannot remove ${INSTALL_PREFIX}; insufficient permissions."
				exit 5
			fi
		fi
		log "INFO" "${APP_NAME} installer completed (uninstall)."
		exit 0
	fi

	local source_root
	source_root="$(resolve_source_root)"

	ensure_homebrew
	copy_payload "${source_root}" "${INSTALL_PREFIX}"
	if [ -f "$(dirname "${source_root}")/.okso_installer_tmp" ]; then
		rm -rf "$(dirname "${source_root}")" >/dev/null 2>&1 || true
	fi
	link_binary "${INSTALL_PREFIX}"

	log "INFO" "${APP_NAME} installer completed (${MODE})."
}

IS_MACOS=$(detect_macos)
main "$@"
