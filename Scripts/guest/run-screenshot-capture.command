#!/bin/bash

# Run from Terminal.app so screencapture inherits Screen Recording permission.
# SSH/sshd cannot capture other windows. Host starts this file with `open`.

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
LOG=/tmp/tabflow-capture.log
DONE=/tmp/tabflow-screenshot-done
FAIL=/tmp/tabflow-screenshot-failed

exec >>"$LOG" 2>&1
echo "===== capture start $(date) ====="

rm -f "$DONE" "$FAIL"

if [[ -f /tmp/tabflow-screenshot.env ]]; then
	set -a
	# shellcheck disable=SC1091
	source /tmp/tabflow-screenshot.env
	set +a
fi

export TABFLOW_SCREENSHOT_AUTO=1
export TABFLOW_SHARE="${TABFLOW_SHARE:-$HOME/TabflowScreenshot}"

if ! "$DIR/run-screenshot-capture.sh"; then
	echo fail >"$FAIL"
	echo "===== capture failed $(date) ====="
	exit 1
fi

date >"$DONE"
rm -f /tmp/tabflow-screenshot.env
echo "===== capture done $(date) ====="
