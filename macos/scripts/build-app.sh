#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
macos_dir="${script_dir:h}"
configuration="${CONFIGURATION:-release}"
version="${SIGNAL_VERSION:-1.0.0}"
build_number="${SIGNAL_BUILD_NUMBER:-1}"
dist_dir="${DIST_DIR:-${macos_dir}/dist}"
app_dir="${dist_dir}/Signal.app"

cd "${macos_dir}"
swift build -c "${configuration}"
bin_dir="$(swift build -c "${configuration}" --show-bin-path)"

mkdir -p "${app_dir}/Contents/MacOS" "${app_dir}/Contents/Resources"
cp "${bin_dir}/Signal" "${app_dir}/Contents/MacOS/Signal"
chmod 755 "${app_dir}/Contents/MacOS/Signal"

cat > "${app_dir}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key><string>Signal</string>
  <key>CFBundleExecutable</key><string>Signal</string>
  <key>CFBundleIdentifier</key><string>app.signal.hand</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Signal</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${version}</string>
  <key>CFBundleVersion</key><string>${build_number}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSCameraUsageDescription</key><string>Signal processes hand landmarks locally to control your Mac. Camera frames are never uploaded.</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Signal</string>
</dict>
</plist>
PLIST

echo -n "APPL????" > "${app_dir}/Contents/PkgInfo"

if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "${SIGNING_IDENTITY}" "${app_dir}"
  echo "Signed Signal.app with configured identity."
else
  codesign --force --deep --sign - "${app_dir}"
  echo "Ad-hoc signed Signal.app (distribution fallback)."
fi

echo "${app_dir}"
