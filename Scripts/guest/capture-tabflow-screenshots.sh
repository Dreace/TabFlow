#!/usr/bin/env bash

set -Eeuo pipefail

SHARE="${TABFLOW_SHARE:-/Volumes/HostShare}"
APP_PATH="${TABFLOW_APP_TARGET:-/Applications/TabFlow.app}"
OUTPUT_ROOT="${SHARE}/Output"
LANGUAGE="${1:-en}"
SCENARIO="${2:-all}"

usage() {
	cat <<EOF
Usage: $(basename "$0") [zh|en] [scenario]

Captures fixed Tabflow scenarios into:
  ${OUTPUT_ROOT}

Scenarios:
  all           Capture all three fixed scenes (default)
  app-store-01  Grid switcher -> 01-switcher.png
  app-store-02  List switcher -> 02-list.png
  app-store-03  Appearance settings -> 03-settings.png
EOF
}

case "$LANGUAGE" in
	zh)
		LANGUAGE_ARGUMENTS=(
			-AppleLanguages "(zh-Hans)"
			-AppleLocale "zh_CN"
		)
		LANGUAGE_DIR="zh-Hans"
		;;
	en)
		LANGUAGE_ARGUMENTS=(
			-AppleLanguages "(en)"
			-AppleLocale "en_US"
		)
		LANGUAGE_DIR="en"
		;;
	--help|-h)
		usage
		exit 0
		;;
	*)
		echo "Unsupported language: ${LANGUAGE}" >&2
		usage >&2
		exit 2
		;;
esac

case "$SCENARIO" in
	all)
		SCENES=(
			"app-store-01:01-switcher.png"
			"app-store-02:02-list.png"
			"app-store-03:03-settings.png"
		)
		;;
	app-store-01|window-grid)
		SCENES=("app-store-01:01-switcher.png")
		;;
	app-store-02|window-list)
		SCENES=("app-store-02:02-list.png")
		;;
	app-store-03|settings)
		SCENES=("app-store-03:03-settings.png")
		;;
	--help|-h)
		usage
		exit 0
		;;
	*)
		echo "Unsupported scenario: ${SCENARIO}" >&2
		usage >&2
		exit 2
		;;
esac

if [[ ! -d "$APP_PATH" ]]; then
	echo "App not found: ${APP_PATH}" >&2
	exit 1
fi

if [[ ! -d "$OUTPUT_ROOT" ]]; then
	echo "Output directory not found: ${OUTPUT_ROOT}" >&2
	exit 1
fi

mkdir -p "${OUTPUT_ROOT}/${LANGUAGE_DIR}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=screenshot-desktop.sh
source "${SCRIPT_DIR}/screenshot-desktop.sh"

killall TabFlow 2>/dev/null || true
apply_menu_bar_clock
if [[ ! -f "$FIXTURE_READY_FLAG" ]]; then
	prepare_fixture_windows
fi
set_screenshot_time

miniaturize_terminal() {
	osascript -e 'tell application "Terminal" to set miniaturized of every window to true' >/dev/null 2>&1 || true
}

wait_for_scene() {
	local scenario="$1"
	local filename="$2"

	if [[ "${TABFLOW_SCREENSHOT_AUTO:-0}" != "1" ]]; then
		read -r -p "Press Return after ${scenario} is ready to capture ${filename}..." _
		return
	fi

	miniaturize_terminal
	if [[ "$scenario" == "app-store-03" ]]; then
		sleep "${TABFLOW_SCREENSHOT_SETTINGS_WAIT:-6}"
	else
		sleep "${TABFLOW_SCREENSHOT_OVERLAY_WAIT:-16}"
	fi
	miniaturize_terminal
}

capture_scenario() {
	local scenario="$1"
	local filename="$2"

	open_fixture_windows
	sleep 2
	open -n "$APP_PATH" --args \
		--screenshot-mode \
		--scenario "$scenario" \
		"${LANGUAGE_ARGUMENTS[@]}"

	wait_for_scene "$scenario" "$filename"
	set_screenshot_time
	sleep 1
	screencapture -x "${OUTPUT_ROOT}/${LANGUAGE_DIR}/${filename}"
	killall TabFlow 2>/dev/null || true
	sleep 2
}

for scene in "${SCENES[@]}"; do
	IFS=: read -r scenario filename <<< "$scene"
	capture_scenario "$scenario" "$filename"
done

echo "Screenshots written to ${OUTPUT_ROOT}/${LANGUAGE_DIR}"
