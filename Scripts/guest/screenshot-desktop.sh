#!/usr/bin/env bash

# Shared helpers for App Store screenshot capture.
# Sourced by capture scripts. Do not execute directly.

SCREENSHOT_CLOCK="081409412026"
TABFLOW_DEMO_ROOT="${TABFLOW_DEMO_ROOT:-${HOME}/TabflowDemo}"
FIXTURE_READY_FLAG="${FIXTURE_READY_FLAG:-/tmp/tabflow-fixtures-ready}"

apply_menu_bar_clock() {
	defaults write com.apple.menuextra.clock IsAnalog -bool false
	defaults write com.apple.menuextra.clock ShowDate -int 2
	defaults write com.apple.menuextra.clock ShowDayOfWeek -bool false
	defaults write com.apple.menuextra.clock ShowSeconds -bool false
	defaults write com.apple.menuextra.clock Show24Hour -bool false
	defaults write com.apple.menuextra.clock ShowAMPM -bool true
	defaults write com.apple.menuextra.clock DateFormat -string "h:mm a"
	defaults write -g AppleICUForce12HourTime -bool true
}

set_screenshot_time() {
	sudo -n systemsetup -setusingnetworktime off >/dev/null 2>&1 || true
	sudo -n date "$SCREENSHOT_CLOCK" >/dev/null 2>&1 || true
}

numbers_is_running() {
	pgrep -x Numbers >/dev/null
}

wait_for_named_process() {
	local name="$1"
	local attempts=0
	while ! pgrep -x "$name" >/dev/null; do
		sleep 0.5
		attempts=$((attempts + 1))
		if [[ "$attempts" -ge 40 ]]; then
			echo "timed out waiting for ${name}" >&2
			return 1
		fi
	done
}

clear_numbers_imports() {
	rm -rf "${HOME}/Library/Containers/com.apple.Numbers/Data/tmp/"com.apple.Numbers_*_import_*
	rm -rf "${HOME}/Library/Containers/com.apple.Numbers/Data/Library/Saved Application State"
	rm -rf "${HOME}/Library/Saved Application State/com.apple.Numbers.savedState"
	defaults write -g ApplePersistenceIgnoreState -bool true
	defaults write com.apple.Numbers NSQuitAlwaysKeepsWindows -bool false
	defaults write com.apple.iWork.Numbers NSQuitAlwaysKeepsWindows -bool false
}

quit_fixture_apps() {
	/usr/bin/killall -9 Numbers Safari TextEdit Preview 2>/dev/null || true
	sleep 1
	clear_numbers_imports
}

unhide_fixture_windows() {
	open -g -a Finder || true
	open -g -a Safari || true
	open -g -a TextEdit || true
	if numbers_is_running; then
		open -g -a Numbers || true
	fi
}

prepare_fixture_windows() {
	local root="${TABFLOW_DEMO_ROOT}"
	local numbers_app="/Applications/Numbers.app"

	rm -f "$FIXTURE_READY_FLAG"
	quit_fixture_apps
	sleep 1

	echo "opening fixture windows from ${root}"
	open -g "${root}/Project" || true
	open -g -a Safari "${root}/Web/Dashboard.html" || true
	open -g -a TextEdit "${root}/Documents/Project Brief.rtf" || true

	if [[ -d "/Applications/Numbers Creator Studio.app" ]]; then
		numbers_app="/Applications/Numbers Creator Studio.app"
	fi
	open -g -a "$numbers_app" "${root}/Data/Dashboard.csv" || true

	wait_for_named_process Safari
	wait_for_named_process TextEdit
	wait_for_named_process Numbers
	# CSV import creates a new document; wait until that single import finishes.
	sleep 8
	echo "fixture windows ready"
	touch "$FIXTURE_READY_FLAG"
}

open_fixture_windows() {
	if [[ -f "$FIXTURE_READY_FLAG" ]] && numbers_is_running; then
		unhide_fixture_windows
		return
	fi
	prepare_fixture_windows
}
