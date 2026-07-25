export type ReleaseMetadata = {
  version: string | null;
  commit: string | null;
  checksum: string | null;
  downloadUrl: string | null;
  minimumMacOS: string | null;
  architecture: string | null;
  signingStatus: string | null;
  notarizationStatus: string | null;
  filename: string | null;
};

function value(...names: string[]): string | null {
  for (const name of names) {
    const candidate = process.env[name]?.trim();
    if (candidate) return candidate;
  }
  return null;
}

function filenameFromUrl(candidate: string | null): string | null {
  if (!candidate) return null;
  try {
    const filename = decodeURIComponent(
      new URL(candidate).pathname.split("/").at(-1) ?? "",
    );
    return filename || null;
  } catch {
    return null;
  }
}

export function getReleaseMetadata(): ReleaseMetadata {
  const downloadUrl = value(
    "NEXT_PUBLIC_RELEASE_DOWNLOAD_URL",
    "SIGNAL_DOWNLOAD_URL",
  );
  return {
    version: value("NEXT_PUBLIC_RELEASE_VERSION", "SIGNAL_RELEASE_VERSION"),
    commit: value("NEXT_PUBLIC_RELEASE_COMMIT", "SIGNAL_RELEASE_COMMIT"),
    checksum: value("NEXT_PUBLIC_RELEASE_SHA256", "SIGNAL_RELEASE_SHA256"),
    downloadUrl:
      downloadUrl?.startsWith("https://") ? downloadUrl : null,
    minimumMacOS: value("NEXT_PUBLIC_RELEASE_MINIMUM_MACOS"),
    architecture: value("SIGNAL_RELEASE_ARCHITECTURE"),
    signingStatus: value(
      "NEXT_PUBLIC_RELEASE_SIGNING_STATUS",
      "SIGNAL_SIGNING_STATUS",
    ),
    notarizationStatus: value("SIGNAL_NOTARIZATION_STATUS"),
    filename:
      value("NEXT_PUBLIC_RELEASE_FILENAME") ??
      filenameFromUrl(downloadUrl),
  };
}
