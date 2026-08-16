#!/usr/bin/env bash

set -Eeuo pipefail

# Copy captured PNGs from the VM back to ~/TabflowScreenshot/Output.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/.env" ]]; then
	set -a
	# shellcheck disable=SC1091
	source "$ROOT/.env"
	set +a
fi

SCREENSHOT_ROOT="${TABFLOW_SCREENSHOT_ROOT:-${HOME}/TabflowScreenshot}"
SSH="$ROOT/Scripts/ssh-screenshot-vm.sh"

mkdir -p "${SCREENSHOT_ROOT}/Output/en" "${SCREENSHOT_ROOT}/Output/zh-Hans"
"$SSH" 'tar -C "$HOME/TabflowScreenshot" -cf - Output' \
	| tar -C "$SCREENSHOT_ROOT" -xf -

echo "Pulled screenshots into ${SCREENSHOT_ROOT}/Output"
