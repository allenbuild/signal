#!/usr/bin/env bash
set -euo pipefail

public_url="${1:-}"
if [[ -z "${public_url}" ]]; then
  printf 'usage: %s <explicit-public-https-url>\n' "${0##*/}" >&2
  exit 2
fi
command -v node >/dev/null 2>&1 || {
  printf 'error: Node.js is required for URL and resolved-address validation\n' >&2
  exit 1
}
command -v curl >/dev/null 2>&1 || {
  printf 'error: curl is required for public URL smoke testing\n' >&2
  exit 1
}

validate_public_url() {
  node --input-type=module - "${1}" <<'NODE'
import dns from "node:dns/promises";
import net from "node:net";

const raw = process.argv[2];
let url;
try {
  url = new URL(raw);
} catch {
  console.error(`error: invalid URL: ${raw}`);
  process.exit(1);
}
if (url.protocol !== "https:" || url.username || url.password) {
  console.error("error: smoke URL must be HTTPS and contain no user-info");
  process.exit(1);
}
const host = url.hostname.toLowerCase().replace(/\.$/, "");
if (
  !host ||
  !host.includes(".") ||
  host === "localhost" ||
  host.endsWith(".localhost") ||
  host.endsWith(".local") ||
  host.endsWith(".internal")
) {
  console.error(`error: URL host is not an explicit public hostname: ${host}`);
  process.exit(1);
}

const blocked = new net.BlockList();
for (const [network, prefix] of [
  ["0.0.0.0", 8], ["10.0.0.0", 8], ["100.64.0.0", 10],
  ["127.0.0.0", 8], ["169.254.0.0", 16], ["172.16.0.0", 12],
  ["192.0.0.0", 24], ["192.0.2.0", 24], ["192.168.0.0", 16],
  ["198.18.0.0", 15], ["198.51.100.0", 24], ["203.0.113.0", 24],
  ["224.0.0.0", 4], ["240.0.0.0", 4],
]) blocked.addSubnet(network, prefix, "ipv4");
for (const [network, prefix] of [
  ["::", 128], ["::1", 128], ["fc00::", 7], ["fe80::", 10],
  ["ff00::", 8], ["2001:db8::", 32],
]) blocked.addSubnet(network, prefix, "ipv6");

let answers;
try {
  answers = await dns.lookup(host, { all: true, verbatim: true });
} catch {
  console.error(`error: DNS lookup failed for ${host}`);
  process.exit(1);
}
if (!answers.length) {
  console.error(`error: DNS returned no addresses for ${host}`);
  process.exit(1);
}
for (const { address, family } of answers) {
  const kind = family === 6 ? "ipv6" : "ipv4";
  const mapped = address.toLowerCase().match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
  if (blocked.check(address, kind) || (mapped && blocked.check(mapped[1], "ipv4"))) {
    console.error(`error: ${host} resolved to blocked address ${address}`);
    process.exit(1);
  }
}
answers.sort((left, right) => left.family - right.family);
const selected = answers[0];
process.stdout.write(`${host}|${url.port || "443"}|${selected.address}`);
NODE
}

resolve_location() {
  node --input-type=module - "${1}" "${2}" <<'NODE'
try {
  process.stdout.write(new URL(process.argv[3], process.argv[2]).toString());
} catch {
  process.exit(1);
}
NODE
}

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/signal-smoke.XXXXXX")"
cleanup() {
  if [[ -n "${tmp_dir:-}" && -d "${tmp_dir}" ]]; then
    rm -rf "${tmp_dir}"
  fi
}
trap cleanup EXIT

current="${public_url}"
redirects=0
while :; do
  resolution="$(validate_public_url "${current}")"
  IFS='|' read -r resolved_host resolved_port resolved_address <<<"${resolution}"
  if [[ "${resolved_address}" == *:* ]]; then
    resolved_address="[${resolved_address}]"
  fi
  headers="${tmp_dir}/headers-${redirects}"
  body="${tmp_dir}/body-${redirects}"
  status="$(
    curl --silent --show-error \
      --proto '=https' \
      --connect-timeout 10 \
      --max-time 30 \
      --max-redirs 0 \
      --max-filesize 2097152 \
      --resolve "${resolved_host}:${resolved_port}:${resolved_address}" \
      --dump-header "${headers}" \
      --output "${body}" \
      --write-out '%{http_code}' \
      "${current}"
  )"

  case "${status}" in
    200|201|202|204)
      content_type="$(awk 'BEGIN{IGNORECASE=1} /^content-type:/ {sub(/\r$/, ""); sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' "${headers}")"
      printf 'Public HTTPS smoke passed: %s -> %s\n' "${current}" "${status}"
      printf 'Content-Type: %s\n' "${content_type:-not supplied}"
      printf 'This check verifies HTTP reachability and public address policy, not application behavior or physical controls.\n'
      exit 0
      ;;
    301|302|303|307|308)
      ((redirects += 1))
      if (( redirects > 5 )); then
        printf 'error: more than five redirects\n' >&2
        exit 1
      fi
      location="$(awk 'BEGIN{IGNORECASE=1} /^location:/ {sub(/\r$/, ""); sub(/^[^:]*:[[:space:]]*/, ""); print; exit}' "${headers}")"
      [[ -n "${location}" ]] || {
        printf 'error: redirect response omitted Location\n' >&2
        exit 1
      }
      current="$(resolve_location "${current}" "${location}")" || {
        printf 'error: invalid redirect target\n' >&2
        exit 1
      }
      ;;
    *)
      printf 'error: public URL returned HTTP %s\n' "${status}" >&2
      exit 1
      ;;
  esac
done
