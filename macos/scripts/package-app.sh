#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
macos_dir="${script_dir:h}"
dist_dir="${DIST_DIR:-${macos_dir}/dist}"

"${script_dir}/build-app.sh"
rm -f "${dist_dir}/Signal-macOS.zip" "${dist_dir}/Signal-macOS.zip.sha256"
ditto -c -k --sequesterRsrc --keepParent \
  "${dist_dir}/Signal.app" \
  "${dist_dir}/Signal-macOS.zip"
shasum -a 256 "${dist_dir}/Signal-macOS.zip" > "${dist_dir}/Signal-macOS.zip.sha256"

echo "${dist_dir}/Signal-macOS.zip"
cat "${dist_dir}/Signal-macOS.zip.sha256"
