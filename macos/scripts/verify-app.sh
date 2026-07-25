#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
macos_dir="${script_dir:h}"
dist_dir="${DIST_DIR:-${macos_dir}/dist}"
app_dir="${dist_dir}/Signal.app"

test -x "${app_dir}/Contents/MacOS/Signal"
plutil -lint "${app_dir}/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app_dir}/Contents/Info.plist")" = "app.signal.hand"
codesign --verify --deep --strict "${app_dir}"

if strings "${app_dir}/Contents/MacOS/Signal" | grep -Eq 'https?://(localhost|127\\.0\\.0\\.1|0\\.0\\.0\\.0)'; then
  echo "Release binary contains a localhost URL." >&2
  exit 1
fi

echo "Verified Signal.app structure, identifier, signature, and no localhost URL."
