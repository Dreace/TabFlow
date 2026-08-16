#!/bin/bash
set -euo pipefail

LOG=/tmp/tabflow-capture.log
OUT=/tmp/tabflow-shots
APP=/Applications/TabFlow.app
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec >>"$LOG" 2>&1

for helper in \
	"${SCRIPT_DIR}/screenshot-desktop.sh" \
	"${HOME}/Scripts/TabflowScreenshot/screenshot-desktop.sh" \
	"/tmp/screenshot-desktop.sh"
do
	if [[ -f "$helper" ]]; then
		# shellcheck source=screenshot-desktop.sh
		source "$helper"
		break
	fi
done

echo "===== capture start $(date) ====="
rm -f /tmp/tabflow-shots-done
mkdir -p "$OUT/zh-Hans" "$OUT/en"

killall TabFlow 2>/dev/null || true
sleep 1
apply_menu_bar_clock
if [[ ! -f "${FIXTURE_READY_FLAG:-/tmp/tabflow-fixtures-ready}" ]]; then
	prepare_fixture_windows
fi
set_screenshot_time

capture() {
	local dir="$1"
	local scenario="$2"
	local file="$3"
	shift 3

	echo "capturing ${dir} ${scenario} -> ${OUT}/${dir}/${file}"
	killall TabFlow 2>/dev/null || true
	sleep 1
	osascript -e 'tell application "Terminal" to set miniaturized of every window to true' >/dev/null 2>&1 || true
	open -n "$APP" --args --screenshot-mode --scenario "$scenario" "$@"
	if [[ "$scenario" == "app-store-03" ]]; then
		sleep 6
	else
		sleep 16
	fi
	osascript -e 'tell application "Terminal" to set miniaturized of every window to true' >/dev/null 2>&1 || true
	set_screenshot_time
	sleep 1
	screencapture -x "${OUT}/${dir}/${file}"
	ls -l "${OUT}/${dir}/${file}"
	killall TabFlow 2>/dev/null || true
	sleep 2
}

ZH=(-AppleLanguages "(zh-Hans)" -AppleLocale "zh_CN")
EN=(-AppleLanguages "(en)" -AppleLocale "en_US")

capture zh-Hans app-store-01 01-switcher.png "${ZH[@]}"
capture zh-Hans app-store-02 02-list.png "${ZH[@]}"
capture zh-Hans app-store-03 03-settings.png "${ZH[@]}"
capture en app-store-01 01-switcher.png "${EN[@]}"
capture en app-store-02 02-list.png "${EN[@]}"
capture en app-store-03 03-settings.png "${EN[@]}"

echo DONE
date > /tmp/tabflow-shots-done
ls -l "$OUT/zh-Hans" "$OUT/en"
echo finished
