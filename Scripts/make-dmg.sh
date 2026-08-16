#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${MACOS_DMG_APP:-$ROOT/dist/TabFlow.app}"
DMG="${MACOS_DMG_OUTPUT:-$ROOT/dist/TabFlow.dmg}"
VOLNAME="${MACOS_DMG_VOLUME_NAME:-TabFlow}"
SVG="$ROOT/Distribution/DMG/background.svg"
PNG_1X="$ROOT/Distribution/DMG/background.png"
PNG_2X="$ROOT/Distribution/DMG/background@2x.png"
TIFF="$ROOT/Distribution/DMG/background.tiff"
STAGE=""

usage() {
  cat <<'EOF'
Usage: make-dmg.sh [--app <TabFlow.app>] [--output <TabFlow.dmg>] [--volname <name>]

Creates a drag-to-Applications DMG with the Distribution/DMG background.
Requires: brew install create-dmg librsvg
EOF
}

fail() {
  echo "Error: $1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$2"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP="${2:-}"
      shift 2
      ;;
    --output)
      DMG="${2:-}"
      shift 2
      ;;
    --volname)
      VOLNAME="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      fail "Unexpected argument: $1"
      ;;
  esac
done

cleanup() {
  if [[ -n "${STAGE:-}" && -d "$STAGE" ]]; then
    rm -rf "$STAGE"
  fi
}
trap cleanup EXIT

require_command create-dmg "Install create-dmg with: brew install create-dmg"
require_command rsvg-convert "Install librsvg with: brew install librsvg"
require_command tiffutil "Install macOS command line tools."
require_command ditto "Install macOS command line tools."

[[ -d "$APP" ]] || fail "App not found: $APP"
[[ -f "$SVG" ]] || fail "DMG background SVG not found: $SVG"

APP_NAME="$(basename "$APP")"
mkdir -p "$(dirname "$PNG_1X")" "$(dirname "$DMG")"

echo "Rendering DMG background..."
rsvg-convert \
  --width 660 \
  --height 420 \
  --output "$PNG_1X" \
  "$SVG"
rsvg-convert \
  --width 1320 \
  --height 840 \
  --output "$PNG_2X" \
  "$SVG"
[[ -f "$PNG_1X" && -f "$PNG_2X" ]] || fail "Failed to render DMG background"
tiffutil -cathidpicheck "$PNG_1X" "$PNG_2X" -out "$TIFF"
[[ -f "$TIFF" ]] || fail "Failed to create Retina DMG background: $TIFF"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/tabflow-dmg.XXXXXX")"
ditto "$APP" "$STAGE/$APP_NAME"

echo "Creating styled DMG..."
rm -f "$DMG"
create-dmg \
  --overwrite \
  --volname "$VOLNAME" \
  --background "$TIFF" \
  --window-pos 200 120 \
  --window-size 660 420 \
  --icon-size 96 \
  --icon "$APP_NAME" 180 160 \
  --hide-extension "$APP_NAME" \
  --app-drop-link 480 160 \
  --no-internet-enable \
  --format UDZO \
  "$DMG" \
  "$STAGE"

[[ -f "$DMG" ]] || fail "DMG was not created: $DMG"
echo "Created DMG: $DMG"
