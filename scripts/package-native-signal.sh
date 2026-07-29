#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "${script_dir}/.." && pwd -P)"
artifact_root="${repo_root}/artifacts"
artifact_dir="${repo_root}/artifacts/native"
source_app="${artifact_dir}/Signal.app"
zip_path="${artifact_dir}/Signal-local.zip"
dmg_path="${artifact_dir}/Signal-local.dmg"
create_dmg="${SIGNAL_CREATE_DMG:-NO}"
dry_run="${SIGNAL_DRY_RUN:-NO}"

[[ "$(uname -s)" == "Darwin" ]] || fail "native Signal packaging requires macOS"
[[ "${repo_root}" != "/" ]] || fail "refusing to use the filesystem root"
[[ ! -L "${script_dir}/build-native-signal.sh" ]] \
  || fail "refusing a symlinked build-native-signal.sh"
[[ ! -L "${artifact_root}" ]] \
  || fail "refusing symlinked artifact root: ${artifact_root}"
[[ -x "${script_dir}/build-native-signal.sh" ]] \
  || fail "missing executable build-native-signal.sh"
[[ ! -L "${artifact_dir}" ]] \
  || fail "refusing symlinked artifact directory: ${artifact_dir}"
if [[ -e "${artifact_dir}" && ! -d "${artifact_dir}" ]]; then
  fail "expected a directory at ${artifact_dir}"
fi

case "${create_dmg}" in
  YES|NO) ;;
  *) fail "SIGNAL_CREATE_DMG must be YES or NO" ;;
esac

case "${dry_run}" in
  YES|NO) ;;
  *) fail "SIGNAL_DRY_RUN must be YES or NO" ;;
esac

require_command ditto
require_command find
require_command plutil
require_command xcrun
xcrun --find lipo >/dev/null || fail "lipo is unavailable"
if [[ "${create_dmg}" == "YES" ]]; then
  require_command hdiutil
fi

for destination in "${zip_path}" "${dmg_path}"; do
  [[ ! -L "${destination}" ]] \
    || fail "refusing to replace symlinked output: ${destination}"
  if [[ -e "${destination}" && ! -f "${destination}" ]]; then
    fail "refusing to replace non-file output: ${destination}"
  fi
done

"${script_dir}/build-native-signal.sh"

if [[ "${dry_run}" == "YES" ]]; then
  printf 'Dry run: validated native packaging inputs; no files were written.\n'
  printf 'Would rebuild and package only: %s\n' "${source_app}"
  printf 'Would replace: %s\n' "${zip_path}"
  if [[ "${create_dmg}" == "YES" ]]; then
    printf 'Would replace: %s\n' "${dmg_path}"
  else
    printf 'Would remove a stale optional DMG only at: %s\n' "${dmg_path}"
  fi
  exit 0
fi

[[ -d "${artifact_dir}" && ! -L "${artifact_dir}" ]] \
  || fail "refusing unsafe artifact directory: ${artifact_dir}"

validate_signal_app() {
  local app_path="$1"
  local bundle_id
  local architectures
  local unexpected_payload

  [[ -d "${app_path}/Contents" && ! -L "${app_path}" ]] \
    || fail "expected a non-symlinked Signal.app at ${app_path}"
  [[ -f "${app_path}/Contents/Info.plist" \
      && ! -L "${app_path}/Contents/Info.plist" ]] \
    || fail "Signal.app has no regular Info.plist at ${app_path}"
  [[ -f "${app_path}/Contents/MacOS/Signal" \
      && -x "${app_path}/Contents/MacOS/Signal" \
      && ! -L "${app_path}/Contents/MacOS/Signal" ]] \
    || fail "Signal.app has no regular Signal executable at ${app_path}"

  bundle_id="$(plutil -extract CFBundleIdentifier raw -o - \
    "${app_path}/Contents/Info.plist")"
  [[ "${bundle_id}" == "com.allenxu.Signal" ]] \
    || fail "unexpected bundle identifier at ${app_path}: ${bundle_id}"

  architectures="$(xcrun lipo -archs \
    "${app_path}/Contents/MacOS/Signal")"
  [[ "${architectures}" == "arm64" ]] \
    || fail "expected an arm64-only Signal executable at ${app_path}, found: ${architectures}"

  unexpected_payload="$(find "${app_path}/Contents" -mindepth 1 \
    \( -iname '*.app' -o -iname '*.appex' -o -iname '*.xpc' \
       -o -iname '*.xctest' -o -iname 'xctest*' \
       -o -iname 'XCTest*' -o -iname 'XCUnit*' \
       -o -iname 'Testing.framework' \
       -o -iname 'web' -o -iname 'website' -o -iname 'extension' \
       -o -iname 'server' -o -iname '*helper*' \) \
    -print -quit)"
  [[ -z "${unexpected_payload}" ]] \
    || fail "refusing non-Signal payload inside ${app_path}: ${unexpected_payload}"
}

validate_signal_app "${source_app}"

stage_dir="$(mktemp -d "${artifact_dir}/.package-stage.XXXXXX")"
cleanup() {
  if [[ -n "${stage_dir:-}" && -d "${stage_dir}" \
        && "${stage_dir}" == "${artifact_dir}/.package-stage."* ]]; then
    rm -rf "${stage_dir}"
  fi
}
trap cleanup EXIT

ditto "${source_app}" "${stage_dir}/Signal.app"
ditto -c -k --sequesterRsrc --keepParent \
  "${stage_dir}/Signal.app" "${stage_dir}/Signal-local.zip"

verify_dir="${stage_dir}/verify"
mkdir "${verify_dir}"
ditto -x -k "${stage_dir}/Signal-local.zip" "${verify_dir}"
[[ -d "${verify_dir}/Signal.app/Contents" ]] \
  || fail "archive verification did not recover Signal.app"
unexpected_archive_root="$(find "${verify_dir}" -mindepth 1 -maxdepth 1 \
  ! -name 'Signal.app' -print -quit)"
[[ -z "${unexpected_archive_root}" ]] \
  || fail "archive contains an unexpected top-level payload: ${unexpected_archive_root}"
validate_signal_app "${verify_dir}/Signal.app"

if [[ "${create_dmg}" == "YES" ]]; then
  dmg_root="${stage_dir}/dmg-root"
  mkdir "${dmg_root}"
  ditto "${source_app}" "${dmg_root}/Signal.app"
  hdiutil create \
    -volname Signal \
    -srcfolder "${dmg_root}" \
    -format UDZO \
    "${stage_dir}/Signal-local.dmg"
  hdiutil verify "${stage_dir}/Signal-local.dmg" >/dev/null \
    || fail "created disk image failed hdiutil verification"
fi

rm -f "${zip_path}"
mv "${stage_dir}/Signal-local.zip" "${zip_path}"

if [[ "${create_dmg}" == "YES" ]]; then
  rm -f "${dmg_path}"
  mv "${stage_dir}/Signal-local.dmg" "${dmg_path}"
else
  rm -f "${dmg_path}"
fi

printf 'Packaged canonical native application: %s\n' "${source_app}"
printf 'Created local archive: %s\n' "${zip_path}"
if [[ "${create_dmg}" == "YES" ]]; then
  printf 'Created optional disk image: %s\n' "${dmg_path}"
fi
printf 'Packaging does not establish launch, permission, physical-gesture, signing, or notarization evidence.\n'
