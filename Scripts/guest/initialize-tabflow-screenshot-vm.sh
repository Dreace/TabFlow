#!/usr/bin/env bash

set -Eeuo pipefail

echo "Applying screenshot VM desktop defaults..."

defaults write com.apple.finder CreateDesktop -bool false
defaults write com.apple.dock autohide -bool true
defaults write com.apple.dock show-recents -bool false

defaults write com.apple.menuextra.clock IsAnalog -bool false
defaults write com.apple.menuextra.clock ShowDate -int 2
defaults write com.apple.menuextra.clock ShowDayOfWeek -bool false
defaults write com.apple.menuextra.clock ShowSeconds -bool false
defaults write com.apple.menuextra.clock Show24Hour -bool false
defaults write com.apple.menuextra.clock ShowAMPM -bool true
defaults write com.apple.menuextra.clock DateFormat -string "h:mm a"
defaults write -g AppleICUForce12HourTime -bool true
defaults write -g ApplePersistenceIgnoreState -bool true
defaults write com.apple.Numbers NSQuitAlwaysKeepsWindows -bool false
defaults write com.apple.iWork.Numbers NSQuitAlwaysKeepsWindows -bool false

if sudo -n true >/dev/null 2>&1; then
	sudo -n tee /etc/sudoers.d/tabflow-screenshot >/dev/null <<'EOF'
screenshot ALL=(root) NOPASSWD: /bin/date, /usr/sbin/systemsetup
EOF
	sudo -n chmod 440 /etc/sudoers.d/tabflow-screenshot
fi

killall Finder 2>/dev/null || true
killall Dock 2>/dev/null || true
killall ControlCenter 2>/dev/null || true

echo "Desktop icons hidden, Dock configured, and menu bar clock set to time-only."
echo "Set the Guest display resolution, wallpaper, and Focus mode manually before taking the golden VM snapshot."
