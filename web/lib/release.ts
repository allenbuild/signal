export type ReleaseMetadata = {
  version: string | null;
  commit: string | null;
  checksum: string | null;
  downloadUrl: string | null;
  minimumMacOS: string | null;
  signingStatus: string | null;
  filename: string | null;
};

function value(name: string): string | null {
  const candidate = process.env[name]?.trim();
  return candidate ? candidate : null;
}

export function getReleaseMetadata(): ReleaseMetadata {
  const downloadUrl = value("NEXT_PUBLIC_RELEASE_DOWNLOAD_URL");
  return {
    version: value("NEXT_PUBLIC_RELEASE_VERSION"),
    commit: value("NEXT_PUBLIC_RELEASE_COMMIT"),
    checksum: value("NEXT_PUBLIC_RELEASE_SHA256"),
    downloadUrl:
      downloadUrl?.startsWith("https://") ? downloadUrl : null,
    minimumMacOS: value("NEXT_PUBLIC_RELEASE_MINIMUM_MACOS"),
    signingStatus: value("NEXT_PUBLIC_RELEASE_SIGNING_STATUS"),
    filename: value("NEXT_PUBLIC_RELEASE_FILENAME"),
  };
}
