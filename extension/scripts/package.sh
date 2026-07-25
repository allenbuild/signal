#!/usr/bin/env bash
set -euo pipefail

extension_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_root="${extension_root}/dist"
dist_unpacked_root="${dist_root}/signal-extension"
dist_zip_path="${dist_root}/signal-extension.zip"
dist_checksum_path="${dist_zip_path}.sha256"
release_root="${extension_root}/release"
release_unpacked_root="${release_root}/signal-extension"
release_zip_path="${release_root}/signal-extension.zip"
release_checksum_path="${release_zip_path}.sha256"
staging_root="$(mktemp -d "${TMPDIR:-/tmp}/signal-extension-package.XXXXXX")"

cleanup() {
  rm -rf "${staging_root}"
}
trap cleanup EXIT

if [[ ! -f "${dist_root}/manifest.json" ]]; then
  echo "Missing ${dist_root}/manifest.json. Run the extension build first." >&2
  exit 1
fi

# Re-running the packager must not recursively include an older package.
rm -rf "${dist_unpacked_root}"
rm -f "${dist_zip_path}" "${dist_checksum_path}"

mkdir -p "${staging_root}/payload"
cp -R "${dist_root}/." "${staging_root}/payload/"
mkdir -p "${dist_unpacked_root}"
cp -R "${staging_root}/payload/." "${dist_unpacked_root}/"

# Archive the contents of the unpacked directory, not the directory itself.
# Chrome therefore sees manifest.json at the ZIP root.
(
  cd "${dist_unpacked_root}"
  zip -q -r "${staging_root}/signal-extension.zip" .
)
mv "${staging_root}/signal-extension.zip" "${dist_zip_path}"
(
  cd "${dist_root}"
  shasum -a 256 "signal-extension.zip" > "signal-extension.zip.sha256"
)

# Keep the earlier release/ handoff paths as mirrors of the canonical dist/
# outputs so existing docs and release automation remain usable.
mkdir -p "${release_root}"
rm -rf "${release_unpacked_root}"
rm -f "${release_zip_path}" "${release_checksum_path}"
cp -R "${dist_unpacked_root}" "${release_unpacked_root}"
cp "${dist_zip_path}" "${release_zip_path}"
cp "${dist_checksum_path}" "${release_checksum_path}"

echo "Unpacked extension: ${dist_unpacked_root}"
echo "ZIP: ${dist_zip_path}"
echo "Checksum: ${dist_checksum_path}"
cat "${dist_checksum_path}"
