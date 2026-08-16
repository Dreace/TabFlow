#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SCREENSHOT_ROOT="${TABFLOW_SCREENSHOT_ROOT:-${HOME}/TabflowScreenshot}"
BUILD_DIR="${SCREENSHOT_ROOT}/Build"
FIXTURE_DIR="${SCREENSHOT_ROOT}/Fixtures"
OUTPUT_DIR="${SCREENSHOT_ROOT}/Output"
DERIVED_DATA_DIR="${SCREENSHOT_ROOT}/DerivedData"
GUEST_SCRIPTS_DIR="${SCREENSHOT_ROOT}/GuestScripts"

PROJECT_PATH="${PROJECT_PATH:-${PROJECT_ROOT}/TabFlow.xcodeproj}"
SCHEME="${SCHEME:-tabflow}"
CONFIGURATION="${CONFIGURATION:-Debug}"

usage() {
	cat <<EOF
Usage: $(basename "$0")

Builds the screenshot app and refreshes the shared fixture workspace:
  ${SCREENSHOT_ROOT}

Environment overrides:
  TABFLOW_SCREENSHOT_ROOT  Host workspace root (default: ${SCREENSHOT_ROOT})
  PROJECT_PATH              Xcode project path
  SCHEME                    Xcode scheme (default: ${SCHEME})
  CONFIGURATION             Xcode configuration (default: ${CONFIGURATION})
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
require_command ditto

if [[ ! -d "$PROJECT_PATH" ]]; then
	echo "Xcode project not found: ${PROJECT_PATH}" >&2
	exit 1
fi

if [[ -z "$SCREENSHOT_ROOT" || "$SCREENSHOT_ROOT" == "/" || "$SCREENSHOT_ROOT" == "$HOME" ]]; then
	echo "Refusing to use unsafe screenshot root: ${SCREENSHOT_ROOT:-<empty>}" >&2
	exit 2
fi

mkdir -p "${SCREENSHOT_ROOT}" "${OUTPUT_DIR}/en" "${OUTPUT_DIR}/zh-Hans"

echo "Preparing screenshot fixtures..."
FIXTURE_ROOT="$FIXTURE_DIR" bash "${PROJECT_ROOT}/prepare-screenshot-fixtures.sh"

rm -rf "$BUILD_DIR" "$DERIVED_DATA_DIR" "$GUEST_SCRIPTS_DIR"
mkdir -p "$BUILD_DIR" "$DERIVED_DATA_DIR" "$GUEST_SCRIPTS_DIR"

echo "Building ${SCHEME} (${CONFIGURATION})..."
xcodebuild \
	-project "$PROJECT_PATH" \
	-scheme "$SCHEME" \
	-configuration "$CONFIGURATION" \
	-destination "platform=macOS" \
	-derivedDataPath "$DERIVED_DATA_DIR" \
	CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
	build

APP_PATH="${BUILD_DIR}/TabFlow.app"
if [[ ! -d "$APP_PATH" ]]; then
	echo "Built app not found: ${APP_PATH}" >&2
	exit 1
fi

cp "${SCRIPT_DIR}/guest/"*.sh "$GUEST_SCRIPTS_DIR/"
chmod +x "$GUEST_SCRIPTS_DIR/"*.sh
if compgen -G "${SCRIPT_DIR}/guest/"*.command >/dev/null; then
	cp "${SCRIPT_DIR}/guest/"*.command "$GUEST_SCRIPTS_DIR/"
	chmod +x "$GUEST_SCRIPTS_DIR/"*.command
fi

echo
echo "Screenshot workspace ready:"
echo "  App:     ${APP_PATH}"
echo "  Fixtures: ${FIXTURE_DIR}"
echo "  Output:   ${OUTPUT_DIR}"
echo "  Guest scripts: ${GUEST_SCRIPTS_DIR}"
