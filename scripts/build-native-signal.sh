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
project_path="${repo_root}/Signal.xcodeproj"
scheme_path="${project_path}/xcshareddata/xcschemes/Signal.xcscheme"
derived_data="${repo_root}/.derivedData"
artifact_root="${repo_root}/artifacts"
artifact_dir="${repo_root}/artifacts/native"
destination_app="${artifact_dir}/Signal.app"

configuration="${SIGNAL_BUILD_CONFIGURATION:-Release}"
code_signing_allowed="${CODE_SIGNING_ALLOWED:-NO}"
signing_identity="${SIGNAL_SIGN_IDENTITY:-}"
dry_run="${SIGNAL_DRY_RUN:-NO}"

[[ "$(uname -s)" == "Darwin" ]] || fail "native Signal builds require macOS"
[[ "${repo_root}" != "/" ]] || fail "refusing to use the filesystem root"
[[ -d "${project_path}" ]] || fail "missing root project: ${project_path}"
[[ -f "${scheme_path}" ]] || fail "missing shared Signal scheme: ${scheme_path}"
[[ ! -L "${project_path}" ]] \
  || fail "refusing a symlinked root project: ${project_path}"
[[ ! -L "${scheme_path}" ]] \
  || fail "refusing a symlinked shared scheme: ${scheme_path}"

case "${configuration}" in
  Debug|Release) ;;
  *) fail "SIGNAL_BUILD_CONFIGURATION must be Debug or Release" ;;
esac

case "${code_signing_allowed}" in
  YES|NO) ;;
  *) fail "CODE_SIGNING_ALLOWED must be YES or NO" ;;
esac

case "${dry_run}" in
  YES|NO) ;;
  *) fail "SIGNAL_DRY_RUN must be YES or NO" ;;
esac

if [[ -n "${signing_identity}" ]]; then
  [[ "${code_signing_allowed}" == "YES" ]] \
    || fail "SIGNAL_SIGN_IDENTITY requires CODE_SIGNING_ALLOWED=YES"
  [[ "${signing_identity}" != *$'\n'* && "${signing_identity}" != *$'\r'* ]] \
    || fail "SIGNAL_SIGN_IDENTITY must be one line"
fi

for guarded_path in "${derived_data}" "${artifact_root}" "${artifact_dir}"; do
  [[ ! -L "${guarded_path}" ]] \
    || fail "refusing symlinked build/output path: ${guarded_path}"
  if [[ -e "${guarded_path}" && ! -d "${guarded_path}" ]]; then
    fail "expected a directory at ${guarded_path}"
  fi
done

require_command xcrun
require_command ditto
require_command plutil
require_command find

xcrun --find xcodebuild >/dev/null \
  || fail "xcodebuild is unavailable; install or select Xcode"
xcrun --find lipo >/dev/null || fail "lipo is unavailable"
if [[ "${code_signing_allowed}" == "YES" ]]; then
  require_command codesign
fi

unexpected_output=""
if [[ -d "${artifact_dir}" ]]; then
  unexpected_output="$(find "${artifact_dir}" -mindepth 1 -maxdepth 1 \
    ! -name 'Signal.app' \
    ! -name 'Signal-local.zip' \
    ! -name 'Signal-local.dmg' \
    -print -quit)"
fi
[[ -z "${unexpected_output}" ]] \
  || fail "refusing ambiguous native output directory; unexpected entry: ${unexpected_output}"

[[ ! -L "${destination_app}" ]] \
  || fail "refusing symlinked output: ${destination_app}"
if [[ -e "${destination_app}" && ! -d "${destination_app}" ]]; then
  fail "refusing non-directory output: ${destination_app}"
fi

xcode_arguments=(
  -project "${project_path}"
  -scheme Signal
  -configuration "${configuration}"
  -destination "generic/platform=macOS"
  -derivedDataPath "${derived_data}"
  ARCHS=arm64
  ONLY_ACTIVE_ARCH=NO
  "CODE_SIGNING_ALLOWED=${code_signing_allowed}"
)

if [[ "${code_signing_allowed}" == "NO" ]]; then
  xcode_arguments+=(CODE_SIGNING_REQUIRED=NO)
else
  xcode_arguments+=(CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
fi

if [[ -n "${signing_identity}" ]]; then
  xcode_arguments+=(
    CODE_SIGN_STYLE=Manual
    "CODE_SIGN_IDENTITY=${signing_identity}"
  )
fi

if [[ "${dry_run}" == "YES" ]]; then
  printf 'Dry run: validated native build inputs; no files were written.\n'
  printf 'Would build only the root Signal scheme:'
  printf ' %q' xcrun xcodebuild "${xcode_arguments[@]}" build
  printf '\nWould replace only: %s\n' "${destination_app}"
  exit 0
fi

mkdir -p "${derived_data}" "${artifact_dir}"

printf 'Building root Signal.xcodeproj / Signal (%s, macOS arm64)\n' \
  "${configuration}"
xcrun xcodebuild "${xcode_arguments[@]}" build

built_app="${derived_data}/Build/Products/${configuration}/Signal.app"
[[ -d "${built_app}/Contents" && ! -L "${built_app}" ]] \
  || fail "expected exactly one built application at ${built_app}"
[[ -f "${built_app}/Contents/Info.plist" \
    && ! -L "${built_app}/Contents/Info.plist" ]] \
  || fail "built application has no Info.plist"
[[ -f "${built_app}/Contents/MacOS/Signal" \
    && -x "${built_app}/Contents/MacOS/Signal" ]] \
  || fail "built application has no Signal executable"
[[ ! -L "${built_app}/Contents/MacOS/Signal" ]] \
  || fail "refusing a symlinked Signal executable"

bundle_id="$(plutil -extract CFBundleIdentifier raw -o - \
  "${built_app}/Contents/Info.plist")"
[[ "${bundle_id}" == "com.allenxu.Signal" ]] \
  || fail "unexpected bundle identifier: ${bundle_id}"

architectures="$(xcrun lipo -archs "${built_app}/Contents/MacOS/Signal")"
[[ "${architectures}" == "arm64" ]] \
  || fail "expected an arm64-only Signal executable, found: ${architectures}"

unexpected_payload="$(find "${built_app}/Contents" -mindepth 1 \
  \( -iname '*.app' -o -iname '*.appex' -o -iname '*.xpc' \
     -o -iname '*.xctest' -o -iname 'xctest*' \
     -o -iname 'XCTest*' -o -iname 'XCUnit*' \
     -o -iname 'Testing.framework' \
     -o -iname 'web' -o -iname 'website' -o -iname 'extension' \
     -o -iname 'server' -o -iname '*helper*' \) \
  -print -quit)"
[[ -z "${unexpected_payload}" ]] \
  || fail "refusing non-canonical payload inside Signal.app: ${unexpected_payload}"

if [[ "${code_signing_allowed}" == "YES" ]]; then
  codesign --verify --deep --strict "${built_app}" \
    || fail "the built application failed code-signature verification"
fi

stage_dir="$(mktemp -d "${artifact_dir}/.build-stage.XXXXXX")"
cleanup() {
  if [[ -n "${stage_dir:-}" && -d "${stage_dir}" \
        && "${stage_dir}" == "${artifact_dir}/.build-stage."* ]]; then
    rm -rf "${stage_dir}"
  fi
}
trap cleanup EXIT

ditto "${built_app}" "${stage_dir}/Signal.app"

if [[ -d "${destination_app}" ]]; then
  rm -rf "${destination_app}"
fi
mv "${stage_dir}/Signal.app" "${destination_app}"
rmdir "${stage_dir}"
stage_dir=""

printf 'Built canonical native application: %s\n' "${destination_app}"
printf 'No website, extension, server, or helper payload was packaged.\n'
