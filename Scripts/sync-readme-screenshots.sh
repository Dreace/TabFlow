#!/usr/bin/env bash

set -Eeuo pipefail

# Copy VM captures from ~/TabflowScreenshot/Output into docs/screenshots
# as JPEG files under 1 MB for README use.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="${TABFLOW_SCREENSHOT_ROOT:-${HOME}/TabflowScreenshot}/Output"
DEST="${ROOT}/docs/screenshots"
MAX_EDGE="${TABFLOW_README_SCREENSHOT_MAX:-2200}"
MAX_BYTES="${TABFLOW_README_SCREENSHOT_MAX_BYTES:-1048576}"
START_QUALITY="${TABFLOW_README_SCREENSHOT_QUALITY:-90}"

require_file() {
	local path="$1"
	if [[ ! -f "$path" ]]; then
		echo "Screenshot missing: ${path}" >&2
		exit 1
	fi
}

compress_jpeg() {
	local src="$1"
	local dest="$2"
	local quality="$START_QUALITY"
	local edge="$MAX_EDGE"
	local tmp
	tmp="$(mktemp "${TMPDIR:-/tmp}/tabflow-readme.XXXXXX").jpg"

	sips -Z "$edge" -s format jpeg -s formatOptions "$quality" "$src" --out "$tmp" >/dev/null

	while [[ "$(stat -f %z "$tmp")" -gt "$MAX_BYTES" ]]; do
		if [[ "$quality" -gt 80 ]]; then
			quality=$((quality - 5))
			sips -Z "$edge" -s format jpeg -s formatOptions "$quality" "$src" --out "$tmp" >/dev/null
			continue
		fi
		if [[ "$edge" -gt 1600 ]]; then
			edge=$((edge - 200))
			quality="$START_QUALITY"
			sips -Z "$edge" -s format jpeg -s formatOptions "$quality" "$src" --out "$tmp" >/dev/null
			continue
		fi
		echo "Could not compress ${src} under ${MAX_BYTES} bytes" >&2
		rm -f "$tmp"
		exit 1
	done

	mkdir -p "$(dirname "$dest")"
	mv "$tmp" "$dest"
	rm -f "${dest%.jpg}.png"
}

mkdir -p "${DEST}/en" "${DEST}/zh-Hans"

for language in en zh-Hans; do
	for name in 01-switcher 02-list 03-settings; do
		require_file "${SOURCE}/${language}/${name}.png"
		compress_jpeg "${SOURCE}/${language}/${name}.png" "${DEST}/${language}/${name}.jpg"
	done
done

echo "README screenshots updated in ${DEST}"
ls -lh "${DEST}/en" "${DEST}/zh-Hans"
