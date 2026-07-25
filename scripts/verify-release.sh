#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "${script_dir}/.." && pwd -P)"
release_dir="${1:-}"

if [[ -z "${release_dir}" ]]; then
  printf 'usage: %s <release-directory>\n' "${0##*/}" >&2
  exit 2
fi
case "${release_dir}" in
  /*) ;;
  *) release_dir="${repo_root}/${release_dir}" ;;
esac

[[ -d "${release_dir}" ]] || {
  printf 'error: release directory does not exist: %s\n' "${release_dir}" >&2
  exit 1
}
for required_command in plutil rg shasum; do
  command -v "${required_command}" >/dev/null 2>&1 || {
    printf 'error: required command is unavailable: %s\n' "${required_command}" >&2
    exit 1
  }
done
app="${release_dir}/Signal.app"
plist="${app}/Contents/Info.plist"
checksums="${release_dir}/SHA256SUMS"
[[ -d "${app}" && -f "${plist}" ]] || {
  printf 'error: Signal.app/Contents/Info.plist is missing\n' >&2
  exit 1
}
[[ -s "${checksums}" ]] || {
  printf 'error: SHA256SUMS is missing or empty\n' >&2
  exit 1
}

bundle_id="$(plutil -extract CFBundleIdentifier raw "${plist}")"
version="$(plutil -extract CFBundleShortVersionString raw "${plist}")"
build_number="$(plutil -extract CFBundleVersion raw "${plist}")"
executable_name="$(plutil -extract CFBundleExecutable raw "${plist}")"
minimum_macos="$(plutil -extract LSMinimumSystemVersion raw "${plist}")"
executable="${app}/Contents/MacOS/${executable_name}"

[[ "${bundle_id}" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || {
  printf 'error: invalid CFBundleIdentifier: %s\n' "${bundle_id}" >&2
  exit 1
}
[[ -n "${version}" && -n "${build_number}" && -n "${minimum_macos}" ]] || {
  printf 'error: version/build/minimum-macOS metadata is incomplete\n' >&2
  exit 1
}
[[ -x "${executable}" ]] || {
  printf 'error: bundle executable is missing or not executable: %s\n' "${executable}" >&2
  exit 1
}

if rg -a -i -l \
  'https?://(localhost|127(\.[0-9]+){1,3}|0\.0\.0\.0|\[?::1\]?)([:/]|$)' \
  "${app}" >/dev/null; then
  printf 'error: application bundle contains a localhost release URL\n' >&2
  exit 1
fi
if [[ -n "${SIGNAL_PUBLIC_API_URL:-}" ]]; then
  case "${SIGNAL_PUBLIC_API_URL}" in
    https://*) ;;
    *)
      printf 'error: SIGNAL_PUBLIC_API_URL must use HTTPS\n' >&2
      exit 1
      ;;
  esac
  if printf '%s' "${SIGNAL_PUBLIC_API_URL}" |
    rg -i '^https://(localhost|127(\.[0-9]+){1,3}|0\.0\.0\.0|\[?::1\]?)([:/]|$)' >/dev/null; then
    printf 'error: SIGNAL_PUBLIC_API_URL may not target localhost\n' >&2
    exit 1
  fi
fi

(
  cd "${release_dir}"
  shasum -a 256 -c SHA256SUMS
)

zip_count="$(find "${release_dir}" -maxdepth 1 -type f -name '*.zip' | wc -l | tr -d ' ')"
[[ "${zip_count}" == "1" ]] || {
  printf 'error: expected exactly one ZIP artifact, found %s\n' "${zip_count}" >&2
  exit 1
}
zip_path="$(find "${release_dir}" -maxdepth 1 -type f -name '*.zip' -print -quit)"
if command -v unzip >/dev/null 2>&1; then
  unzip -Z1 "${zip_path}" | rg '^Signal\.app/Contents/Info\.plist$' >/dev/null || {
    printf 'error: ZIP does not contain Signal.app metadata\n' >&2
    exit 1
  }
fi

signature_status="not verified"
if command -v codesign >/dev/null 2>&1; then
  if codesign --verify --deep --strict "${app}" >/dev/null 2>&1; then
    signature_status="codesign verification passed"
  else
    signature_status="unsigned or codesign verification failed"
    if [[ "${SIGNAL_REQUIRE_SIGNING:-0}" == "1" ]]; then
      printf 'error: a valid signature is required but codesign verification failed\n' >&2
      exit 1
    fi
  fi
fi

printf 'Bundle identifier: %s\n' "${bundle_id}"
printf 'Version/build: %s (%s)\n' "${version}" "${build_number}"
printf 'Minimum macOS: %s\n' "${minimum_macos}"
printf 'Signature: %s\n' "${signature_status}"
printf 'Automated bundle metadata, localhost URL, archive, and checksum checks passed.\n'
printf 'Physical controls, permissions, launch, Gatekeeper, and notarization were not verified by this script.\n'
