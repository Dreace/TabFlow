#!/usr/bin/env bash

set -Eeuo pipefail

SHARE="${TABFLOW_SHARE:-/Volumes/HostShare}"
DEMO="${TABFLOW_DEMO_ROOT:-${HOME}/TabflowDemo}"
APP_TARGET="${TABFLOW_APP_TARGET:-/Applications/TabFlow.app}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/screenshot-sudo.sh" ]]; then
	# shellcheck source=screenshot-sudo.sh
	source "${SCRIPT_DIR}/screenshot-sudo.sh"
else
	sudo_run() {
		if [[ -n "${TABFLOW_SUDO_PASSWORD:-}" ]]; then
			printf '%s\n' "$TABFLOW_SUDO_PASSWORD" | sudo -S "$@"
		else
			sudo "$@"
		fi
	}
fi

APP_SOURCE="${SHARE}/Build/TabFlow.app"
if [[ ! -d "$APP_SOURCE" && -d "${SHARE}/Build/Tabflow.app" ]]; then
	APP_SOURCE="${SHARE}/Build/Tabflow.app"
fi
if [[ ! -d "$APP_SOURCE" && -d "${SHARE}/Build/tabflow.app" ]]; then
	APP_SOURCE="${SHARE}/Build/tabflow.app"
fi

if [[ ! -d "$APP_SOURCE" ]]; then
	echo "Built app not found: ${SHARE}/Build" >&2
	echo "Mount the host share and run Scripts/build-screenshot.sh first." >&2
	exit 1
fi

if [[ ! -d "${SHARE}/Fixtures" ]]; then
	echo "Fixture directory not found: ${SHARE}/Fixtures" >&2
	exit 1
fi

echo "Installing TabFlow..."
sudo_run -v
sudo_run rm -rf "$APP_TARGET"
sudo_run ditto "$APP_SOURCE" "$APP_TARGET"
sudo_run chmod -R a+rX "$APP_TARGET"

echo "Refreshing fixtures..."
rm -rf "$DEMO"
ditto "${SHARE}/Fixtures" "$DEMO"
chmod -R a+rX "$DEMO"

echo
echo "Screenshot VM ready:"
echo "  App:     ${APP_TARGET}"
echo "  Fixtures: ${DEMO}"
