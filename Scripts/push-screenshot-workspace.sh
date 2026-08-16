#!/usr/bin/env bash

set -Eeuo pipefail

# Copy Build, Fixtures and GuestScripts to the VM over SSH.
# Use this when VirtioFS is not mounted. Relies on Scripts/ssh-screenshot-vm.sh.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/.env" ]]; then
	set -a
	# shellcheck disable=SC1091
	source "$ROOT/.env"
	set +a
fi

SCREENSHOT_ROOT="${TABFLOW_SCREENSHOT_ROOT:-${HOME}/TabflowScreenshot}"
SSH="$ROOT/Scripts/ssh-screenshot-vm.sh"

mkdir -p "${SCREENSHOT_ROOT}/GuestScripts"
ditto "$ROOT/Scripts/guest" "${SCREENSHOT_ROOT}/GuestScripts"
chmod +x "${SCREENSHOT_ROOT}/GuestScripts"/*.sh
if compgen -G "${ROOT}/Scripts/guest/"*.command >/dev/null; then
	chmod +x "${SCREENSHOT_ROOT}/GuestScripts"/*.command
fi

for required in Build/TabFlow.app Fixtures GuestScripts; do
	if [[ ! -e "${SCREENSHOT_ROOT}/${required}" ]]; then
		echo "Missing ${SCREENSHOT_ROOT}/${required}. Run Scripts/build-screenshot.sh first." >&2
		exit 1
	fi
done

"$SSH" 'mkdir -p "$HOME/TabflowScreenshot/Output/en" "$HOME/TabflowScreenshot/Output/zh-Hans"'
tar -C "$SCREENSHOT_ROOT" -cf - Build Fixtures GuestScripts \
	| "$SSH" 'tar -C "$HOME/TabflowScreenshot" -xf -'

echo "Pushed screenshot workspace to screenshot@${SCREENSHOT_SSH_HOST:-192.168.64.2}:~/TabflowScreenshot"
