#!/usr/bin/env bash
# shellcheck shell=bash
#
# okso installer: macOS-only bootstrapper for the okso assistant.
#
# Usage:
#   scripts/install.sh [--prefix PATH] [--upgrade] [--uninstall] [--dry-run] [--help]
#
# Environment variables:
#   DO_LINK_DIR (string): Directory for the PATH symlink. Defaults to
#       "/usr/local/bin".
#   DO_INSTALLER_ASSUME_OFFLINE (bool): Set to "true" to skip network actions
#       (intended for CI); install fails if downloads are required while offline.
#   DO_INSTALLER_BASE_URL (string): Base URL hosting the installer artifacts
#       (install script + tarball). Defaults to the public site
#       https://cmccomb.github.io/okso; the installer fetches the project archive
#       from "${DO_INSTALLER_BASE_URL%/}/okso.tar.gz".
#   DO_PROJECT_ARCHIVE_URL (string): Explicit URL to a project archive. Takes
#       precedence over DO_INSTALLER_BASE_URL.
#   DO_INSTALLER_SKIP_SELF_TEST (bool): Set to "true" to bypass the post-install
#       self-test (not recommended).
#
# Exit codes:
#   0: Success
#   1: Invalid usage
#   2: Dependency installation failed
#   3: Unsupported platform (non-macOS)
#   4: Network unavailable when required
#   5: Filesystem permission error
#
# Dependencies:
#   - bash 5+
#   - curl
#   - core macOS utilities (cp, ln, mkdir, rm)

if [ -z "${BASH_VERSION:-}" ]; then
	# Re-exec with bash to ensure array and parameter expansion support.
	exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

# Defaults
APP_NAME="okso"
DEFAULT_PREFIX="/usr/local/okso"
DO_LINK_DIR="${DO_LINK_DIR:-/usr/local/bin}"
DEFAULT_LINK_PATH="${DO_LINK_DIR}/${APP_NAME}"
DEFAULT_INSTALLER_BASE_URL="https://cmccomb.github.io/okso"
INSTALLER_BASE_URL="${DO_INSTALLER_BASE_URL:-${DEFAULT_INSTALLER_BASE_URL}}"
DEFAULT_PROJECT_ARCHIVE_URL="${DO_PROJECT_ARCHIVE_URL:-${INSTALLER_BASE_URL%/}/okso.tar.gz}"
DRY_RUN="false"

SCRIPT_SOURCE="${BASH_SOURCE[0]-${0-}}"
if [ -z "${SCRIPT_SOURCE}" ] || [ "${SCRIPT_SOURCE}" = "-" ] || [ ! -f "${SCRIPT_SOURCE}" ]; then
	SCRIPT_DIR="${PWD}"
else
	SCRIPT_DIR=$(cd -- "$(dirname -- "${SCRIPT_SOURCE}")" && pwd)
fi
PROJECT_ROOT="${SCRIPT_DIR%/scripts}"
SRC_DIR="${PROJECT_ROOT}/src"
SOURCE_PAYLOAD_DIR="${SRC_DIR}"
TEMP_ARCHIVE_DIR=""

BREW_PACKAGES=(
	"llama.cpp"
	"tesseract"
	"pandoc"
	"poppler"
	"yq"
	"bash"
	"coreutils"
	"jq"
	"gum"
)

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

detect_macos() {
	local uname_bin
	uname_bin=$(command -v uname || true)

	if [ -n "${uname_bin}" ] && [ "$(${uname_bin} -s)" = "Darwin" ]; then
		printf 'true\n'
		return 0
	fi

	printf 'false\n'
}

IS_MACOS=$(detect_macos)

read_lines_into_array() {
	# $1: destination array name
	local target line
	target="$1"

	if command -v mapfile >/dev/null 2>&1; then
		mapfile -t "${target}"
		return
	fi

	eval "${target}=()"
	while IFS= read -r line; do
		eval "${target}+=(\"${line}\")"
	done
}

cleanup_temp_dir() {
	if [ -n "${TEMP_ARCHIVE_DIR}" ] && [ -d "${TEMP_ARCHIVE_DIR}" ]; then
		rm -rf "${TEMP_ARCHIVE_DIR}"
	fi
}

resolve_project_archive_url() {
	local archive_url

	if [ -n "${DEFAULT_PROJECT_ARCHIVE_URL}" ]; then
		printf '%s\n' "${DEFAULT_PROJECT_ARCHIVE_URL}"
		return 0
	fi

	log "ERROR" "Source directory missing and no archive URL configured."
	log "ERROR" "Set DO_PROJECT_ARCHIVE_URL to a tar.gz containing the project (for GitHub Pages: \"${DO_INSTALLER_BASE_URL:-https://example.github.io/okso}/okso.tar.gz\")."
	exit 2
}

has_network() {
	if [ "${DO_INSTALLER_ASSUME_OFFLINE:-false}" = "true" ]; then
		return 1
	fi
	curl --head --silent --connect-timeout 3 --max-time 5 https://brew.sh >/dev/null 2>&1
}

fetch_sidecar_file() {
	# $1: archive URL, $2: extension (e.g., .sha256), $3: destination path
	local archive_url ext dest_path sidecar_url
	archive_url="$1"
	ext="$2"
	dest_path="$3"

	if [[ "${archive_url}" == file://* ]]; then
		local file_path
		file_path="${archive_url#file://}"
		sidecar_url="${file_path}${ext}"
		if [ -f "${sidecar_url}" ]; then
			cp "${sidecar_url}" "${dest_path}"
			return 0
		fi
		return 1
	fi

	if ! has_network; then
		return 1
	fi

	sidecar_url="${archive_url}${ext}"
	if curl -fsSL "${sidecar_url}" -o "${dest_path}"; then
		return 0
	fi

	return 1
}

compute_sha256() {
	# $1: file path
	local target
	target="$1"
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "${target}" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "${target}" | awk '{print $1}'
	else
		log "ERROR" "No SHA-256 utility found for checksum verification"
		return 1
	fi
}

verify_download_integrity() {
	# $1: downloaded archive path, $2: original archive URL
	local archive_path archive_url checksum_path signature_path expected_checksum actual_checksum
	archive_path="$1"
	archive_url="$2"

	checksum_path="$(mktemp "${TMPDIR:-/tmp}/okso-archive-XXXXXX.sha256")"
	signature_path="$(mktemp "${TMPDIR:-/tmp}/okso-archive-XXXXXX.asc")"

	local checksum_available signature_available
	checksum_available=false
	signature_available=false

	if fetch_sidecar_file "${archive_url}" ".sha256" "${checksum_path}"; then
		checksum_available=true
	else
		rm -f "${checksum_path}"
	fi

	if fetch_sidecar_file "${archive_url}" ".asc" "${signature_path}"; then
		if [ "${DO_INSTALLER_VERIFY_SIGNATURES:-false}" = "true" ]; then
			signature_available=true
		else
			log "INFO" "Signature file detected but verification is disabled (set DO_INSTALLER_VERIFY_SIGNATURES=true to enforce)."
			signature_available=false
			rm -f "${signature_path}"
		fi
	else
		rm -f "${signature_path}"
	fi

	if [ "${checksum_available}" = true ]; then
		expected_checksum="$(head -n 1 "${checksum_path}" | awk '{print $1}')"
		if [[ ! ${expected_checksum} =~ ^[A-Fa-f0-9]{64}$ ]]; then
			log "ERROR" "Checksum file invalid or malformed"
			exit 2
		fi
	fi

	if [ "${checksum_available}" = true ]; then
		actual_checksum="$(compute_sha256 "${archive_path}")"
		if [ -z "${expected_checksum}" ] || [ -z "${actual_checksum}" ] || [ "${expected_checksum}" != "${actual_checksum}" ]; then
			log "ERROR" "Archive checksum verification failed"
			exit 2
		fi
		log "INFO" "Checksum verification passed"
	else
		log "INFO" "No checksum found; proceeding without SHA-256 verification"
	fi

	if [ "${signature_available}" = true ]; then
		if ! grep -q "BEGIN PGP SIGNATURE" "${signature_path}" 2>/dev/null; then
			log "WARN" "Signature file invalid; skipping verification"
			signature_available=false
		fi
	fi

	if [ "${signature_available}" = true ]; then
		if command -v gpg >/dev/null 2>&1; then
			if ! gpg --verify "${signature_path}" "${archive_path}" >/dev/null 2>&1; then
				log "ERROR" "Signature verification failed"
				exit 2
			fi
			log "INFO" "Signature verification passed"
		else
			log "WARN" "Signature provided but gpg is unavailable; skipping verification"
		fi
	fi

	rm -f "${checksum_path}" "${signature_path}"
}

prepare_source_payload() {
	if [ -d "${SRC_DIR}" ] && [ -f "${SRC_DIR}/main.sh" ]; then
		SOURCE_PAYLOAD_DIR="${SRC_DIR}"
		return 0
	fi

	local archive_url archive_path
	archive_url=$(resolve_project_archive_url)
	archive_path=$(mktemp "${TMPDIR:-/tmp}/okso-archive-XXXXXX.tar.gz")
	TEMP_ARCHIVE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/okso-src-XXXXXX")
	trap cleanup_temp_dir EXIT

	download_project_archive "${archive_url}" "${archive_path}"
	verify_download_integrity "${archive_path}" "${archive_url}"
	if ! tar -xzf "${archive_path}" -C "${TEMP_ARCHIVE_DIR}"; then
		log "ERROR" "Failed to extract project archive from ${archive_url}"
		exit 2
	fi

	SOURCE_PAYLOAD_DIR=$(derive_source_root "${TEMP_ARCHIVE_DIR}")
}

verify_checksum_file_present() {
	# Backwards compatibility shim: this function is retained to avoid breaking
	# callers that expect checksum utilities to be present.
	:
}

download_project_archive() {
	# $1: archive URL, $2: destination path
	local archive_url dest_path
	archive_url="$1"
	dest_path="$2"

	if [[ "${archive_url}" == file://* ]]; then
		local file_path
		file_path="${archive_url#file://}"
		if [ ! -f "${file_path}" ]; then
			log "ERROR" "Archive not found at ${file_path}"
			exit 2
		fi
		cp "${file_path}" "${dest_path}"
		return 0
	fi

	if ! has_network; then
		log "ERROR" "Network connectivity required to fetch ${archive_url}"
		exit 4
	fi

	if ! curl -fsSL "${archive_url}" -o "${dest_path}"; then
		log "ERROR" "Failed to download project archive from ${archive_url}"
		exit 2
	fi
}

derive_source_root() {
	# $1: extraction root
	local extraction_root archive_root
	extraction_root="$1"

	if [ -d "${extraction_root}/src" ]; then
		printf '%s\n' "${extraction_root}/src"
		return 0
	fi

	archive_root=$(find "${extraction_root}" -maxdepth 1 -mindepth 1 -type d | head -n 1)
	if [ -n "${archive_root}" ] && [ -d "${archive_root}/src" ]; then
		printf '%s\n' "${archive_root}/src"
		return 0
	fi

	log "ERROR" "Extracted archive does not contain a src directory"
	exit 2
}

usage() {
	cat <<'USAGE'
Usage: scripts/install.sh [options]

Options:
  --prefix PATH     Installation prefix (default: /usr/local/okso)
  --upgrade         Reinstall project files
  --uninstall       Remove installed files and symlink
  --dry-run         Print intended actions without modifying the system
  --help            Show this help message

Environment variables:
  DO_LINK_DIR                Directory for the CLI symlink
  HF_TOKEN                   Hugging Face token for gated downloads
  DO_INSTALLER_ASSUME_OFFLINE=true to prevent network access

Exit codes:
  0 success, 1 usage error, 2 dependency failure,
  3 unsupported platform, 4 network required, 5 permission error
USAGE
}

require_macos() {
	if [ "${IS_MACOS}" != "true" ]; then
		log "ERROR" "This installer only supports macOS."
		exit 3
	fi
}

ensure_homebrew() {
	if command -v brew >/dev/null 2>&1; then
		log "INFO" "Homebrew detected."
		return 0
	fi

	if ! has_network; then
		log "ERROR" "Homebrew is missing and network connectivity is unavailable."
		exit 4
	fi

	log "INFO" "Installing Homebrew..."
	local tmp_script
	tmp_script="$(mktemp)"
	trap 'rm -f -- "${tmp_script}"' EXIT
	if ! curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "${tmp_script}"; then
		log "ERROR" "Failed to download Homebrew installer."
		exit 2
	fi
	NONINTERACTIVE=1 /bin/bash "${tmp_script}" >/dev/null
	log "INFO" "Homebrew installation complete."
}

install_brew_packages() {
	local missing=()
	for pkg in "${BREW_PACKAGES[@]}"; do
		if ! brew list --formula --versions "${pkg}" >/dev/null 2>&1; then
			missing+=("${pkg}")
		fi
	done

	if [ ${#missing[@]} -eq 0 ]; then
		log "INFO" "Required Homebrew packages already installed."
		return 0
	fi

	if ! has_network; then
		log "ERROR" "Network connectivity is required to install: ${missing[*]}"
		exit 4
	fi

	log "INFO" "Installing required packages: ${missing[*]}"
	if ! HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 brew install "${missing[@]}"; then
		log "ERROR" "Failed to install Homebrew dependencies."
		exit 2
	fi
}

ensure_prefix_writable() {
	# $1: path to check
	local path="$1"
	if [ -w "${path}" ]; then
		return 0
	fi
	if [ ! -d "${path}" ]; then
		mkdir -p "${path}" 2>/dev/null || true
	fi
	if [ -w "${path}" ]; then
		return 0
	fi
	if command -v sudo >/dev/null 2>&1; then
		return 0
	fi
	log "ERROR" "Insufficient permissions to modify ${path} and sudo not available."
	exit 5
}

copy_project_files() {
	# $1: prefix
	local prefix="$1"
	ensure_prefix_writable "${prefix}"
	if [ ! -d "${SOURCE_PAYLOAD_DIR}" ]; then
		log "ERROR" "Source directory missing at ${SOURCE_PAYLOAD_DIR}"
		exit 2
	fi

	log "INFO" "Installing project files into ${prefix}"
	if [ -w "${prefix}" ]; then
		mkdir -p "${prefix}"
		cp -R "${SOURCE_PAYLOAD_DIR}/." "${prefix}/"
	else
		sudo mkdir -p "${prefix}"
		sudo cp -R "${SOURCE_PAYLOAD_DIR}/." "${prefix}/"
	fi
}

create_symlink() {
	# $1: target prefix, $2: link path
	local prefix="$1"
	local link_path="$2"
	local target="${prefix}/main.sh"

	if [ ! -f "${target}" ]; then
		log "ERROR" "Entrypoint missing at ${target}"
		exit 2
	fi

	local link_dir
	link_dir="$(dirname "${link_path}")"
	ensure_prefix_writable "${link_dir}"
	if [ -w "${link_dir}" ]; then
		mkdir -p "${link_dir}"
		ln -sf "${target}" "${link_path}"
	else
		sudo mkdir -p "${link_dir}"
		sudo ln -sf "${target}" "${link_path}"
	fi
	log "INFO" "Symlinked ${link_path} -> ${target}"
}

uninstall() {
	local prefix="$1"
	local link_path="$2"

	if [ -e "${link_path}" ]; then
		if [ -w "${link_path}" ]; then
			rm -f "${link_path}"
		elif command -v sudo >/dev/null 2>&1; then
			sudo rm -f "${link_path}"
		else
			log "ERROR" "Cannot remove ${link_path}; insufficient permissions."
			exit 5
		fi
		log "INFO" "Removed symlink ${link_path}"
	fi

	if [ -d "${prefix}" ]; then
		if [ -w "${prefix}" ]; then
			rm -rf "${prefix}"
		elif command -v sudo >/dev/null 2>&1; then
			sudo rm -rf "${prefix}"
		else
			log "ERROR" "Cannot remove ${prefix}; insufficient permissions."
			exit 5
		fi
		log "INFO" "Removed installation prefix ${prefix}"
	fi
}

self_test_install() {
	# $1: installation prefix, $2: link path
	local prefix link_path grammar_path_output temp_root query_output
	prefix="$1"
	link_path="$2"

	log "INFO" "Running installer self-test"

	if [ ! -x "${prefix}/main.sh" ]; then
		log "ERROR" "Installed main.sh is missing or not executable"
		exit 2
	fi

	if [ ! -f "${prefix}/grammars/planner_plan.gbnf" ]; then
		log "ERROR" "Planner grammar missing from installation"
		exit 2
	fi

	grammar_path_output="$(bash -c "source \"${prefix}/grammar.sh\" && grammar_path planner_plan" 2>/dev/null || true)"
	if [ "${grammar_path_output}" != "${prefix}/grammars/planner_plan.gbnf" ]; then
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
		"${prefix}/main.sh" --plan-only -- "Self-test query" 2>&1 || true)

	if [ -z "${query_output}" ]; then
		log "ERROR" "Self-test query produced no output"
		exit 2
	fi

	if ! printf '%s' "${query_output}" | grep -q "Plan outline"; then
		log "ERROR" "Self-test query did not complete as expected"
		exit 2
	fi

	if [ ! -L "${link_path}" ] && [ ! -x "${link_path}" ]; then
		log "WARN" "CLI link not present; continuing"
	fi

	log "INFO" "Installer self-test passed"
}

main() {
	local prefix="${DEFAULT_PREFIX}"
	local mode="install"

	while [ $# -gt 0 ]; do
		case "$1" in
		--prefix)
			if [ $# -lt 2 ]; then
				usage
				exit 1
			fi
			prefix="$2"
			shift 2
			;;
		--upgrade)
			mode="upgrade"
			shift
			;;
		--uninstall)
			mode="uninstall"
			shift
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

	if [ "${mode}" != "uninstall" ]; then
		if [ "${DRY_RUN}" = "true" ]; then
			log_dry_run "Would verify macOS compatibility"
			log_dry_run "Would ensure Homebrew is installed"
			log_dry_run "Would install Homebrew packages: ${BREW_PACKAGES[*]}"
		else
			require_macos
			ensure_homebrew
			install_brew_packages
		fi
	elif [ "${IS_MACOS}" != "true" ] && [ "${DRY_RUN}" != "true" ]; then
		log "ERROR" "Uninstall is only supported on macOS."
		exit 3
	fi

	case "${mode}" in
	install | upgrade)
		if [ "${DRY_RUN}" = "true" ]; then
			log_dry_run "Would prepare source payload"
			log_dry_run "Would copy project files to ${prefix}"
			log_dry_run "Would create symlink at ${DEFAULT_LINK_PATH}"
			log_dry_run "Would run installer self-test"
			log "INFO" "${APP_NAME} installer completed (dry-run)."
			exit 0
		fi

		prepare_source_payload
		copy_project_files "${prefix}"
		create_symlink "${prefix}" "${DEFAULT_LINK_PATH}"
		if [ "${DO_INSTALLER_SKIP_SELF_TEST:-false}" != "true" ]; then
			self_test_install "${prefix}" "${DEFAULT_LINK_PATH}"
		else
			log "WARN" "Skipping installer self-test due to DO_INSTALLER_SKIP_SELF_TEST"
		fi
		;;
	uninstall)
		if [ "${DRY_RUN}" = "true" ]; then
			log_dry_run "Would remove symlink ${DEFAULT_LINK_PATH}"
			log_dry_run "Would remove installation prefix ${prefix}"
			log "INFO" "${APP_NAME} installer completed (dry-run uninstall)."
			exit 0
		fi
		uninstall "${prefix}" "${DEFAULT_LINK_PATH}"
		;;
	esac

	log "INFO" "${APP_NAME} installer completed (${mode})."
}

main "$@"
