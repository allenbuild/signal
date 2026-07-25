#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "${script_dir}/.." && pwd -P)"
macos_dir="${repo_root}/macos"
configuration="${SIGNAL_BUILD_CONFIGURATION:-Release}"
product="${SIGNAL_SWIFT_PRODUCT:-Signal}"

case "${configuration}" in
  Release|Debug) ;;
  *)
    printf 'error: SIGNAL_BUILD_CONFIGURATION must be Release or Debug\n' >&2
    exit 2
    ;;
esac

if [[ -f "${macos_dir}/Package.swift" ]]; then
  command -v swift >/dev/null 2>&1 || {
    printf 'error: Swift is required to build macos/Package.swift\n' >&2
    exit 1
  }
  swift_configuration="$(printf '%s' "${configuration}" | tr '[:upper:]' '[:lower:]')"
  printf 'Building Swift package product %s (%s)\n' "${product}" "${configuration}"
  swift build \
    --package-path "${macos_dir}" \
    --configuration "${swift_configuration}" \
    --product "${product}"
  exit 0
fi

xcode_project="$(find "${macos_dir}" -maxdepth 2 -name '*.xcodeproj' -print -quit 2>/dev/null || true)"
if [[ -n "${xcode_project}" ]]; then
  command -v xcodebuild >/dev/null 2>&1 || {
    printf 'error: xcodebuild is required to build %s\n' "${xcode_project}" >&2
    exit 1
  }
  scheme="${SIGNAL_XCODE_SCHEME:-Signal}"
  derived_data="${SIGNAL_DERIVED_DATA_DIR:-${repo_root}/.build/SignalDerivedData}"
  case "${derived_data}" in
    /*) ;;
    *) derived_data="${repo_root}/${derived_data}" ;;
  esac
  printf 'Building Xcode scheme %s (%s)\n' "${scheme}" "${configuration}"
  xcodebuild \
    -project "${xcode_project}" \
    -scheme "${scheme}" \
    -configuration "${configuration}" \
    -derivedDataPath "${derived_data}" \
    build
  exit 0
fi

printf 'error: no macos/Package.swift or Xcode project exists\n' >&2
exit 1
