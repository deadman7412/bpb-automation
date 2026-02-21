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

When `enableECH` is true, host selection priority is:

1. `customCdnHost` (if set and domain)
2. Host from saved subscription URL
3. Host from `remoteDNS` (if domain)
4. Fallback: `cloudflare-ech.com`

The app queries DNS HTTPS records and extracts `ech=` / `echconfig=` value.

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

- If DNS endpoints are unreachable, update still proceeds; derived fields may remain partially unchanged.
- When `enableECH` is false, `echConfig` is not refreshed.
