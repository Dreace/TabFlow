#!/usr/bin/env bash

set -Eeuo pipefail

APP_PATH="${APP_PATH:-/Applications/TabFlow.app}"
LANGUAGE="${1:-en}"
SCENARIO="${2:-window-grid}"

usage() {
	cat <<EOF
Usage: $(basename "$0") [zh|en] [scenario]

Scenarios:
  window-grid    Current windows in grid layout, second item selected
  window-preview Current windows with large cards, first item selected
  window-list    Current windows in list layout
  settings       Fixed-size appearance settings window
  app-store-01   Alias for window-grid
  app-store-02   Alias for window-list
  app-store-03   Alias for settings

APP_PATH can override the default /Applications/TabFlow.app.
EOF
}

case "$LANGUAGE" in
	zh)
		LANGUAGE_ARGUMENTS=(
			-AppleLanguages "(zh-Hans)"
			-AppleLocale "zh_CN"
		)
		;;
	en)
		LANGUAGE_ARGUMENTS=(
			-AppleLanguages "(en)"
			-AppleLocale "en_US"
		)
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
	window-grid|window-preview|window-list|settings|app-store-01|app-store-02|app-store-03)
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
	echo "Run Scripts/install-local.sh first or set APP_PATH." >&2
	exit 1
fi

killall TabFlow 2>/dev/null || true

open -n "$APP_PATH" --args \
	--screenshot-mode \
	--scenario "$SCENARIO" \
	"${LANGUAGE_ARGUMENTS[@]}"
