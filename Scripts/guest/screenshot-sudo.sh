#!/usr/bin/env bash

# Shared sudo helper for screenshot VM scripts.
# Set TABFLOW_SUDO_PASSWORD when running over SSH.

sudo_run() {
	if [[ -n "${TABFLOW_SUDO_PASSWORD:-}" ]]; then
		printf '%s\n' "$TABFLOW_SUDO_PASSWORD" | sudo -S -p '' "$@"
	else
		sudo "$@"
	fi
}
