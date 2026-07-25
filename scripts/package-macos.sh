#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "${script_dir}/.." && pwd -P)"
macos_dir="${repo_root}/macos"
artifact_root="${SIGNAL_ARTIFACT_DIR:-${repo_root}/artifacts}"
version="${SIGNAL_VERSION:-0.1.0}"
build_number="${SIGNAL_BUILD_NUMBER:-1}"
bundle_id="${SIGNAL_BUNDLE_ID:-app.signal.hand}"
product="${SIGNAL_SWIFT_PRODUCT:-Signal}"
minimum_macos="${SIGNAL_MINIMUM_MACOS:-13.0}"

case "${artifact_root}" in
  /*) ;;
  *) artifact_root="${repo_root}/${artifact_root}" ;;
esac

[[ "${version}" =~ ^[0-9]+(\.[0-9]+){1,3}([.-][A-Za-z0-9]+)*$ ]] || {
  printf 'error: SIGNAL_VERSION is not a safe version string\n' >&2
  exit 2
}
[[ "${build_number}" =~ ^[0-9]+(\.[0-9]+)*$ ]] || {
  printf 'error: SIGNAL_BUILD_NUMBER must contain only numeric components\n' >&2
  exit 2
}
[[ "${bundle_id}" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || {
  printf 'error: SIGNAL_BUNDLE_ID is not a valid reverse-DNS identifier\n' >&2
  exit 2
}
command -v shasum >/dev/null 2>&1 || {
  printf 'error: shasum is required for release checksums\n' >&2
  exit 1
}

commit="$(git -C "${repo_root}" rev-parse --short=12 HEAD 2>/dev/null || printf 'uncommitted')"
release_dir="${artifact_root}/Signal-${version}-${commit}"
if [[ -e "${release_dir}" ]]; then
  printf 'error: refusing to overwrite existing release directory %s\n' "${release_dir}" >&2
  exit 1
fi

stage_root="$(mktemp -d "${TMPDIR:-/tmp}/signal-package.XXXXXX")"
cleanup() {
  if [[ -n "${stage_root:-}" && -d "${stage_root}" ]]; then
    rm -rf "${stage_root}"
  fi
}
trap cleanup EXIT

app_path="${stage_root}/Signal.app"
staged_release="${stage_root}/release"
source_app="${SIGNAL_APP_PATH:-}"
if [[ -n "${source_app}" ]]; then
  case "${source_app}" in
    /*) ;;
    *) source_app="${repo_root}/${source_app}" ;;
  esac
  [[ -d "${source_app}/Contents" ]] || {
    printf 'error: SIGNAL_APP_PATH is not a macOS application bundle\n' >&2
    exit 1
  }
  if command -v ditto >/dev/null 2>&1; then
    ditto "${source_app}" "${app_path}"
  else
    cp -R "${source_app}" "${app_path}"
  fi
else
  [[ -f "${macos_dir}/Package.swift" ]] || {
    printf 'error: set SIGNAL_APP_PATH when the native owner does not use SwiftPM\n' >&2
    exit 1
  }
  command -v plutil >/dev/null 2>&1 || {
    printf 'error: plutil is required to construct a macOS application bundle\n' >&2
    exit 1
  }
  SIGNAL_BUILD_CONFIGURATION=Release "${script_dir}/build-macos.sh"
  bin_path="$(swift build --package-path "${macos_dir}" --configuration release --show-bin-path)"
  executable="${bin_path}/${product}"
  [[ -x "${executable}" ]] || {
    printf 'error: release executable not found at %s\n' "${executable}" >&2
    exit 1
  }

  mkdir -p "${app_path}/Contents/MacOS" "${app_path}/Contents/Resources"
  cp "${executable}" "${app_path}/Contents/MacOS/Signal"
  chmod 0755 "${app_path}/Contents/MacOS/Signal"
  plist="${app_path}/Contents/Info.plist"
  plutil -create xml1 "${plist}"
  plutil -insert CFBundleDisplayName -string Signal "${plist}"
  plutil -insert CFBundleExecutable -string Signal "${plist}"
  plutil -insert CFBundleIdentifier -string "${bundle_id}" "${plist}"
  plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "${plist}"
  plutil -insert CFBundleName -string Signal "${plist}"
  plutil -insert CFBundlePackageType -string APPL "${plist}"
  plutil -insert CFBundleShortVersionString -string "${version}" "${plist}"
  plutil -insert CFBundleVersion -string "${build_number}" "${plist}"
  plutil -insert LSMinimumSystemVersion -string "${minimum_macos}" "${plist}"
  plutil -insert SignalCommit -string "${commit}" "${plist}"
  plutil -insert NSCameraUsageDescription -string \
    'Signal processes hand gestures on this Mac. Camera frames remain in memory.' "${plist}"
fi

if [[ -n "${SIGNAL_SIGN_IDENTITY:-}" ]]; then
  command -v codesign >/dev/null 2>&1 || {
    printf 'error: codesign is unavailable\n' >&2
    exit 1
  }
  codesign --force --deep --options runtime --timestamp \
    --sign "${SIGNAL_SIGN_IDENTITY}" "${app_path}"
elif [[ "${SIGNAL_ADHOC_SIGN:-0}" == "1" ]]; then
  codesign --force --deep --sign - "${app_path}"
else
  printf 'note: packaging without adding a signature; verification will report actual status\n'
fi

mkdir -p "${staged_release}"
if command -v ditto >/dev/null 2>&1; then
  ditto "${app_path}" "${staged_release}/Signal.app"
else
  cp -R "${app_path}" "${staged_release}/Signal.app"
fi

zip_name="Signal-${version}-macOS.zip"
if command -v ditto >/dev/null 2>&1; then
  ditto -c -k --sequesterRsrc --keepParent \
    "${staged_release}/Signal.app" "${staged_release}/${zip_name}"
else
  command -v zip >/dev/null 2>&1 || {
    printf 'error: ditto or zip is required to create the release archive\n' >&2
    exit 1
  }
  (
    cd "${staged_release}"
    zip -qry "${zip_name}" Signal.app
  )
fi

if [[ "${SIGNAL_CREATE_DMG:-0}" == "1" ]]; then
  command -v hdiutil >/dev/null 2>&1 || {
    printf 'error: hdiutil is required when SIGNAL_CREATE_DMG=1\n' >&2
    exit 1
  }
  hdiutil create \
    -volname Signal \
    -srcfolder "${staged_release}/Signal.app" \
    -ov \
    -format UDZO \
    "${staged_release}/Signal-${version}-macOS.dmg"
fi

(
  cd "${staged_release}"
  checksum_targets=("${zip_name}")
  if [[ -f "Signal-${version}-macOS.dmg" ]]; then
    checksum_targets+=("Signal-${version}-macOS.dmg")
  fi
  shasum -a 256 "${checksum_targets[@]}" > SHA256SUMS
)

"${script_dir}/verify-release.sh" "${staged_release}"
mkdir -p "${artifact_root}"
mv "${staged_release}" "${release_dir}"
printf 'Packaged automated release candidate at %s\n' "${release_dir}"
printf 'No physical gesture, permission, signing, notarization, or launch claim was inferred.\n'
