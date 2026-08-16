#!/usr/bin/env bash

set -Eeuo pipefail

# Host SSH wrapper for the screenshot VM.
# Credentials come from .env:
#   SCREENSHOT_SSH_HOST=192.168.64.2
#   SCREENSHOT_SSH_USER=screenshot
#   SCREENSHOT_SSH_PASSWORD=...

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/.env" ]]; then
	set -a
	# shellcheck disable=SC1091
	source "$ROOT/.env"
	set +a
fi

HOST="${SCREENSHOT_SSH_HOST:-192.168.64.2}"
USER="${SCREENSHOT_SSH_USER:-screenshot}"
PASSWORD="${SCREENSHOT_SSH_PASSWORD:-}"
CONTROL_PATH="${SCREENSHOT_SSH_CONTROL_PATH:-/tmp/tabflow-vm-ssh}"

if [[ -z "$PASSWORD" ]]; then
	echo "Set SCREENSHOT_SSH_PASSWORD in .env" >&2
	exit 1
fi

ASKPASS="$(mktemp "${TMPDIR:-/tmp}/tabflow-ssh-askpass.XXXXXX")"
cleanup() {
	rm -f "$ASKPASS"
}
trap cleanup EXIT

{
	printf '%s\n' '#!/bin/sh'
	printf 'printf %%s %q\n' "$PASSWORD"
} >"$ASKPASS"
chmod 700 "$ASKPASS"

export SSH_ASKPASS="$ASKPASS"
export SSH_ASKPASS_REQUIRE=force
export DISPLAY="${DISPLAY:-:0}"

if ! ssh -o ControlPath="$CONTROL_PATH" -O check "$USER@$HOST" >/dev/null 2>&1; then
	rm -f "$CONTROL_PATH"
fi

SSH_ARGS=(
	-T
	-o ControlMaster=auto
	-o ControlPath="$CONTROL_PATH"
	-o ControlPersist=600
	-o StrictHostKeyChecking=accept-new
	-o PreferredAuthentications=password
	-o PubkeyAuthentication=no
	-o NumberOfPasswordPrompts=1
	-o ConnectTimeout=15
	"$USER@$HOST"
)

# Guest login shell is zsh. Send one quoted `bash -lc` string so spaces stay
# inside the command and `=` path expansion does not rewrite it.
if [[ $# -eq 1 ]]; then
	ssh "${SSH_ARGS[@]}" "bash -lc $(printf %q "$1")"
else
	ssh "${SSH_ARGS[@]}" "$@"
fi
