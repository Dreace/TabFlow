#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="${TABFLOW_DEMO_ROOT:-${HOME}/TabflowDemo}"

if [[ ! -d "$ROOT" ]]; then
	echo "Fixture directory not found: ${ROOT}" >&2
	echo "Run prepare-tabflow-screenshot.sh first." >&2
	exit 1
fi

quit_if_running() {
	local application="$1"
osascript - "$application" <<'OSA' >/dev/null 2>&1 || true
on run argv
    tell application (item 1 of argv)
        repeat with currentWindow in windows
            try
                close currentWindow
            end try
        end repeat
        quit
    end tell
end run
OSA
}

close_finder_windows() {
	osascript <<'OSA' >/dev/null 2>&1 || true
tell application "Finder"
    close every window
end tell
OSA
}

set_window_bounds() {
	local application="$1"
	local left="$2"
	local top="$3"
	local right="$4"
	local bottom="$5"
	osascript - "$application" "$left" "$top" "$right" "$bottom" <<'OSA' >/dev/null 2>&1 || true
on run argv
    tell application (item 1 of argv)
        if (count windows) > 0 then
            set bounds of front window to {(item 2 of argv) as integer, (item 3 of argv) as integer, (item 4 of argv) as integer, (item 5 of argv) as integer}
        end if
    end tell
end run
OSA
}

quit_if_running "Safari"
quit_if_running "TextEdit"
quit_if_running "Preview"
quit_if_running "Numbers"
if [[ "${TABFLOW_SCREENSHOT_AUTO:-0}" != "1" ]]; then
	quit_if_running "Terminal"
fi
close_finder_windows

open "$ROOT/Project"
sleep 1

open -a Safari "$ROOT/Web/Dashboard.html"
sleep 1

open -a TextEdit "$ROOT/Documents/Project Brief.rtf"
sleep 1

NUMBERS_APP=""
for candidate in \
	"/Applications/Numbers.app" \
	"/Applications/Numbers Creator Studio.app"
do
	if [[ -d "$candidate" ]]; then
		NUMBERS_APP="$candidate"
		break
	fi
done
if [[ -z "$NUMBERS_APP" ]]; then
	echo "Numbers.app not found. Install Numbers before capturing spreadsheet screenshots." >&2
	exit 1
fi
open -a "$NUMBERS_APP" "$ROOT/Data/Dashboard.csv"
sleep 1

if [[ -f "$ROOT/Design/AppIcon.svg" ]]; then
	open -a Preview "$ROOT/Design/AppIcon.svg" 2>/dev/null \
		|| open "$ROOT/Design/AppIcon.svg"
fi
sleep 1

osascript - "$ROOT/Project" <<'OSA'
on run argv
    set projectPath to item 1 of argv
    tell application "Terminal"
        activate
        do script "cd " & quoted form of projectPath & "; clear; cat status.txt"
    end tell
end run
OSA

set_window_bounds "Finder" 80 80 820 650
set_window_bounds "Safari" 900 80 1760 650
set_window_bounds "TextEdit" 1840 80 2480 650
set_window_bounds "Numbers" 80 720 820 1290
set_window_bounds "Preview" 900 720 1760 1290
set_window_bounds "Terminal" 1840 720 2480 1290

touch "${FIXTURE_READY_FLAG:-/tmp/tabflow-fixtures-ready}"
echo "Fixture windows opened from ${ROOT}"
