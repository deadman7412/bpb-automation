# Cloudflare KV Apply Parity

## Purpose

When the app updates `proxySettings` through Cloudflare KV API directly, it must also recompute the same derived fields that BPB Panel's "Apply" path computes.

Without those transforms, subscription output can diverge from panel-generated output even if `cleanIPs` are the same.

## What Is Recomputed

Before writing `proxySettings` back to KV, the app now recomputes:

1. `remoteDnsHost` from `remoteDNS`
2. `outProxyParams` from `outProxy`
3. `echConfig` (only when `enableECH = true`)

This mirrors BPB panel-side behavior where derived fields are refreshed during apply.

## Current App Logic

In `CloudflareApiService.updateCleanIPs`:

1. Read current `proxySettings` from KV.
2. Replace `cleanIPs` with scan result values.
3. Apply panel-compatible transforms to derived fields.
4. PUT the full updated object back to KV.

## ECH Host Resolution Strategy

To match panel behavior, ECH is derived from the panel worker host (`hostName`).

In app mode, host resolution is:

1. Host from saved subscription URL
2. Host from saved panel base URL

If no host can be resolved, the update fails.

## Sanitized Debug Verification

For fast parity checks, the app logs sanitized snapshots before and after transforms:

- `remoteDnsHost`: host, domain flag, IPv4/IPv6 counts
- `outProxyParams`: non-secret fields + secret-presence flags
- `echConfig`: present flag, length, short prefix only

Log lines contain:

- `Derived fields snapshot (before): ...`
- `Derived fields snapshot (after): ...`

No tokens, passwords, or full secret values are logged.

## Reproduction Checklist

1. Configure valid Cloudflare credentials in app settings.
2. Ensure KV contains a valid `proxySettings` payload.
3. Run scan and trigger update via Cloudflare API mode.
4. Confirm update succeeds and logs include both derived snapshots.
5. Compare resulting KV payload against panel apply output for:
   - `remoteDnsHost`
   - `outProxyParams`
   - `echConfig` (if enabled)

## Notes

- If derived-field generation fails (DNS/ECH/proxy parsing), update fails and KV is not written.
- When `enableECH` is false, `echConfig` is set to an empty string (panel behavior).

## Live SOCKS Probe Script

When app-managed Xray SOCKS is short-lived, you can run this watcher in terminal
before pressing Apply in app. It waits for `127.0.0.1:10808`, then runs a quick
HTTP/HTTPS/DoH probe through the same SOCKS tunnel:

```bash
while true; do
  if nc -z 127.0.0.1 10808 2>/dev/null; then
    echo "=== SOCKS detected $(date) ==="
    curl -sS -v --socks5-hostname 127.0.0.1:10808 http://connectivitycheck.gstatic.com/generate_204 --max-time 8 -o /dev/null
    curl -sS -v --socks5-hostname 127.0.0.1:10808 https://example.com --max-time 8 -o /dev/null
    curl -sS -v --socks5-hostname 127.0.0.1:10808 "https://dns.google/resolve?name=artshop.ecomedgeinnovators.com&type=HTTPS" -H "accept: application/dns-json" --max-time 8
    curl -sS -v --socks5-hostname 127.0.0.1:10808 "https://cloudflare-dns.com/dns-query?name=artshop.ecomedgeinnovators.com&type=HTTPS" -H "accept: application/dns-json" --max-time 8
    echo "=== done ==="
    break
  fi
  sleep 0.1
done
```
