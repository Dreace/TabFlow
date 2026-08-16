#!/usr/bin/env bash

set -Eeuo pipefail

# Guest one-shot capture. Invoked from the host via Scripts/capture-screenshots.sh.
# Uses LaunchServices (`open -n`), not the app binary.

SHARE="${TABFLOW_SHARE:-/Volumes/HostShare}"
DEST="${HOME}/Scripts/TabflowScreenshot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -x "${SCRIPT_DIR}/screenshot-sudo.sh" ]]; then
	# shellcheck disable=SC1091
	source "${SCRIPT_DIR}/screenshot-sudo.sh"
elif [[ -x "${SHARE}/GuestScripts/screenshot-sudo.sh" ]]; then
	# shellcheck disable=SC1091
	source "${SHARE}/GuestScripts/screenshot-sudo.sh"
else
	sudo_run() { sudo "$@"; }
fi

if [[ ! -d "${SHARE}/GuestScripts" && -d "${HOME}/TabflowScreenshot/GuestScripts" ]]; then
	SHARE="${HOME}/TabflowScreenshot"
	export TABFLOW_SHARE="$SHARE"
fi

if [[ ! -d "${SHARE}/GuestScripts" ]]; then
	echo "Host share is not mounted at ${SHARE}" >&2
	exit 1
fi

mkdir -p "$DEST"
ditto "${SHARE}/GuestScripts" "$DEST"
chmod +x "$DEST"/*.sh
if compgen -G "${DEST}/*.command" >/dev/null; then
	chmod +x "$DEST"/*.command
fi

export TABFLOW_SCREENSHOT_AUTO=1
export TABFLOW_SHARE="$SHARE"

if [[ "${TABFLOW_CAPTURE_SKIP_PREPARE:-0}" != "1" ]]; then
	"$DEST/prepare-tabflow-screenshot.sh"
	"$DEST/open-tabflow-fixtures.sh"
fi

if [[ -n "${TABFLOW_CAPTURE_SCENARIO:-}" ]]; then
	for language in ${TABFLOW_CAPTURE_LANGUAGES:-en}; do
		"$DEST/capture-tabflow-screenshots.sh" "$language" "$TABFLOW_CAPTURE_SCENARIO"
	done
else
	"$DEST/capture-tabflow-screenshots.sh" zh
	"$DEST/capture-tabflow-screenshots.sh" en
fi

echo "Guest capture finished."
