#!/usr/bin/env bash

set -Eeuo pipefail

# Host entry for screenshot capture:
#   1. Build TabFlow into ~/TabflowScreenshot
#   2. SSH into the screenshot VM
#   3. Install the app, open fixture windows, capture EN/ZH scenes

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/.env" ]]; then
	set -a
	# shellcheck disable=SC1091
	source "$ROOT/.env"
	set +a
fi

SKIP_BUILD=0
if [[ "${1:-}" == "--skip-build" ]]; then
	SKIP_BUILD=1
	shift
fi

if [[ "$SKIP_BUILD" -eq 0 ]]; then
	"$ROOT/Scripts/build-screenshot.sh"
fi

PASSWORD="${SCREENSHOT_SSH_PASSWORD:-}"
if [[ -z "$PASSWORD" ]]; then
	echo "Set SCREENSHOT_SSH_PASSWORD in .env" >&2
	exit 1
fi

SSH="$ROOT/Scripts/ssh-screenshot-vm.sh"

if "$SSH" 'test -d /Volumes/HostShare/GuestScripts'; then
	GUEST_SHARE=/Volumes/HostShare
	PULL_OUTPUT=0
else
	echo "VirtioFS share is not mounted; pushing workspace over SSH..."
	"$ROOT/Scripts/push-screenshot-workspace.sh"
	GUEST_SHARE='$HOME/TabflowScreenshot'
	PULL_OUTPUT=1
fi

# screencapture from sshd cannot record other windows. Launch the guest
# capture in Terminal.app, which already has Screen Recording permission.
echo "Starting guest capture in Terminal..."
"$SSH" "cat > /tmp/tabflow-screenshot.env && chmod 600 /tmp/tabflow-screenshot.env" <<EOF
TABFLOW_SUDO_PASSWORD=${PASSWORD}
TABFLOW_SCREENSHOT_AUTO=1
TABFLOW_SHARE=${GUEST_SHARE}
TABFLOW_CAPTURE_LANGUAGES=${TABFLOW_CAPTURE_LANGUAGES:-}
TABFLOW_CAPTURE_SCENARIO=${TABFLOW_CAPTURE_SCENARIO:-}
TABFLOW_CAPTURE_SKIP_PREPARE=${TABFLOW_CAPTURE_SKIP_PREPARE:-0}
EOF

"$SSH" "rm -f /tmp/tabflow-screenshot-done /tmp/tabflow-screenshot-failed /tmp/tabflow-capture.log; mkdir -p \"\$HOME/Scripts/TabflowScreenshot\"; ditto ${GUEST_SHARE}/GuestScripts \"\$HOME/Scripts/TabflowScreenshot\"; chmod +x \"\$HOME/Scripts/TabflowScreenshot\"/*; open \"\$HOME/Scripts/TabflowScreenshot/run-screenshot-capture.command\""

echo "Waiting for guest capture to finish..."
finished=0
for _ in $(seq 1 90); do
	if "$SSH" 'test -f /tmp/tabflow-screenshot-done'; then
		echo "Guest capture finished."
		finished=1
		break
	fi
	if "$SSH" 'test -f /tmp/tabflow-screenshot-failed'; then
		echo "Guest capture failed. Log:" >&2
		"$SSH" 'tail -n 80 /tmp/tabflow-capture.log' >&2 || true
		exit 1
	fi
	sleep 5
done
if [[ "$finished" -eq 0 ]]; then
	echo "Timed out waiting for guest capture. Log:" >&2
	"$SSH" 'tail -n 80 /tmp/tabflow-capture.log' >&2 || true
	exit 1
fi

if [[ "$PULL_OUTPUT" -eq 1 ]]; then
	"$ROOT/Scripts/pull-screenshot-output.sh"
fi

"$ROOT/Scripts/sync-readme-screenshots.sh"
