#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_PATH="${PROJECT_PATH:-${PROJECT_ROOT}/TabFlow.xcodeproj}"
SCHEME="${SCHEME:-tabflow}"
CONFIGURATION="${CONFIGURATION:-Debug}"
BUILD_ROOT="${BUILD_ROOT:-/Users/Shared/TabflowBuild}"
BUILD_DIR="${BUILD_ROOT}/${CONFIGURATION}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${BUILD_ROOT}/DerivedData}"
APP_PATH="${APP_PATH:-${BUILD_DIR}/TabFlow.app}"
INSTALL_PATH="${INSTALL_PATH:-/Applications/TabFlow.app}"

usage() {
	cat <<EOF
Usage: $(basename "$0")

Builds the tabflow macOS app in a shared directory and installs it at:
  ${INSTALL_PATH}

Environment overrides:
  PROJECT_PATH       Xcode project path
  SCHEME             Xcode scheme (default: ${SCHEME})
  CONFIGURATION      Build configuration (default: ${CONFIGURATION})
  BUILD_ROOT         Shared build root (default: ${BUILD_ROOT})
  DERIVED_DATA_PATH  Derived data path (default: ${DERIVED_DATA_PATH})
  APP_PATH           Built app path (default: ${APP_PATH})
  INSTALL_PATH       Installed app path (default: ${INSTALL_PATH})
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
	usage
	exit 0
fi

if (($# > 0)); then
	echo "Unexpected argument: $1" >&2
	usage >&2
	exit 2
fi

require_command() {
	local command_name="$1"
	if ! command -v "$command_name" >/dev/null 2>&1; then
		echo "Required command not found: ${command_name}" >&2
		exit 1
	fi
}

require_command xcodebuild
require_command codesign
require_command ditto
require_command sudo

if [[ ! -d "$PROJECT_PATH" ]]; then
	echo "Xcode project not found: ${PROJECT_PATH}" >&2
	exit 1
fi

if [[ "$INSTALL_PATH" != /Applications/*.app ]]; then
	echo "INSTALL_PATH must point to an app directly under /Applications: ${INSTALL_PATH}" >&2
	exit 1
fi

mkdir -p "$BUILD_DIR" "$DERIVED_DATA_PATH"

echo "Building ${SCHEME} (${CONFIGURATION})..."
xcodebuild \
	-project "$PROJECT_PATH" \
	-scheme "$SCHEME" \
	-configuration "$CONFIGURATION" \
	-destination "platform=macOS" \
	-derivedDataPath "$DERIVED_DATA_PATH" \
	CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
	build

if [[ ! -d "$APP_PATH" ]]; then
	echo "Built app not found: ${APP_PATH}" >&2
	exit 1
fi

echo "Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Installing to ${INSTALL_PATH}..."
sudo -v
sudo rm -rf "$INSTALL_PATH"
sudo ditto "$APP_PATH" "$INSTALL_PATH"
sudo chmod -R a+rX "$INSTALL_PATH"

echo "Installed: ${INSTALL_PATH}"
