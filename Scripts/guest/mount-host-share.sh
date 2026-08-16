#!/usr/bin/env bash

set -Eeuo pipefail

SHARE_NAME="${TABFLOW_VIRTIOFS_SHARE:-share}"
MOUNT_POINT="${TABFLOW_MOUNT_POINT:-/Volumes/HostShare}"
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

if [[ -d "${MOUNT_POINT}/Build" && -d "${MOUNT_POINT}/Fixtures" ]]; then
	echo "Host share already mounted: ${MOUNT_POINT}"
	exit 0
fi

if ! command -v mount_virtiofs >/dev/null 2>&1; then
	echo "mount_virtiofs is not available in this macOS guest." >&2
	exit 1
fi

sudo_run mkdir -p "$MOUNT_POINT"
sudo_run mount_virtiofs "$SHARE_NAME" "$MOUNT_POINT"

if [[ ! -d "${MOUNT_POINT}/Build" || ! -d "${MOUNT_POINT}/Fixtures" ]]; then
	echo "The mounted share does not contain Build and Fixtures: ${MOUNT_POINT}" >&2
	exit 1
fi

echo "Mounted ${SHARE_NAME} at ${MOUNT_POINT}"
