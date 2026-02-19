# Scan Pipeline

## Overview

The BPB Automation scanner finds Cloudflare IPs that genuinely work for your
BPB Panel worker and produces configs you can directly import into any
Xray-compatible VPN app.

The pipeline runs in four sequential phases. Each phase narrows the candidate
pool before passing survivors to the more expensive next phase.

```
All IPs (500-1500)
  └── Phase 0: TCP ping x2         → ~30% survive  → sorted by avg latency
        └── Phase 1a: TLS test x1  → ~50% survive  → sorted by TLS latency
              └── Phase 1b: re-TLS → ~70% survive  → sorted by latency+jitter
                    └── Phase 2: Xray proxy test → top 5-10 working IPs
```

---

## Phase 0 — Two-Probe TCP Filter

**Goal**: Remove unreachable IPs and IPs with unstable routing fast, before any
TLS work is done.

**Mechanism**: For each candidate IP, attempt two sequential TCP connections to
port 443. A 100 ms pause separates the probes to catch IPs that only pass
momentarily.

**Pass condition**: Both probes must succeed. A single failure (timeout or
refused) drops the IP immediately — if even one probe fails, the routing is
unstable.

**Sort key**: Average latency of the two successful probes (ascending).

**Parameters**:
- Timeout per probe: 1 s
- Probes per IP: 2
- Concurrency: 200 IPs tested in parallel
- Gap between probes: 100 ms

**Why two probes and not four**: Two probes doubles Phase 0 time from ~1 s to
~2 s per batch. Four probes would add ~4 s for diminishing returns. Two probes
reliably catches IPs with >50% loss rate, which are the ones that cause
real-world VPN failures.

**Note**: This uses TCP SYN/ACK measurement, NOT ICMP ping. ICMP requires root
on Android and is frequently blocked. TCP to port 443 is always available and
directly reflects the latency of the connection we will use.

---

## Phase 1a — First TLS Pass

**Goal**: Confirm the IP is a reachable Cloudflare edge that correctly handles
the BPB worker's SNI.

**Mechanism**: Full TLS handshake to `ip:443` using the worker hostname as SNI
(from the subscription template config). A successful handshake proves the IP
is a Cloudflare edge node that routes TLS to the correct zone.

**Pass condition**: TLS handshake completes within 3 s.

**Sort key**: TLS handshake latency (ascending).

**Parameters**:
- Timeout: 3 s
- Concurrency: 200
- Input: Phase 0 survivors (~30% of original pool)

---

## Phase 1b — Second TLS Pass (Re-Validation)

**Goal**: Eliminate IPs that passed Phase 1a due to a momentary good state.
An IP that consistently passes two independent TLS tests minutes apart is
genuinely stable.

**Mechanism**: Re-run the identical TLS test on Phase 1a survivors only. The
second pass is applied to a much smaller pool (typically 20-80 IPs), so it
completes quickly.

**Pass condition**: Must pass BOTH Phase 1a and Phase 1b.

**Sort key**: `latencyMs + jitterMs * 0.5`

Where:
- `latencyMs` = average of Phase 1a and Phase 1b TLS latencies
- `jitterMs` = absolute difference between the two latencies
- The 0.5 factor penalises jitter without making it dominate

**Example**:
- IP A: 80 ms + 82 ms → avg=81, jitter=2, score=82
- IP B: 50 ms + 200 ms → avg=125, jitter=150, score=200
- IP C: 60 ms + 65 ms → avg=62.5, jitter=5, score=65

IP C wins despite IP B having a faster first pass, because IP B's jitter reveals
unstable routing.

**Parameters**:
- Timeout: 3 s
- Concurrency: 200
- Input: Phase 1a survivors only

---

## Phase 2 — Xray Proxy Test (Worker Outbound Reachability)

**Goal**: Confirm the IP can reach the broader internet through the BPB Worker
using the actual Xray/VLESS protocol chain.

**Test target**: `connectivitycheck.gstatic.com:80` (Google, non-Cloudflare).

**Why non-Cloudflare**:
- Phase 1 already confirmed the IP routes TLS to the correct worker zone via SNI.
- Phase 2 must confirm the Worker can reach the **real internet** (non-Cloudflare).
- Testing against any Cloudflare-hosted domain (including `cp.cloudflare.com`,
  `workerHost`, etc.) exercises only Cloudflare-internal network routing, which
  is always available to Workers regardless of real outbound internet access.
  This produces false positives — IPs that appear to work in Phase 2 but fail
  in actual use (e.g. -1 in BPB Panel speed tests).
- `connectivitycheck.gstatic.com` is Google's dedicated connectivity probe:
  not on Cloudflare, globally available, returns `HTTP 204` at `/generate_204`.

**Flow**:
1. Write Xray config to temp file (candidate IP substituted into outbound).
2. Start Xray process, wait up to 8 s for SOCKS5 port 10808 to open.
3. Record `xrayReadyTime`; compute remaining HTTP test budget.
4. SOCKS5 CONNECT to `connectivitycheck.gstatic.com:80` through Xray.
5. HTTP GET `/generate_204` with `Host: connectivitycheck.gstatic.com`.
6. Read response. HTTP 2xx or 3xx = success; 4xx/5xx = failure.
7. Kill Xray process, delete temp file.

**Pass condition**: HTTP 2xx or 3xx received within the HTTP test timeout.
HTTP 4xx/5xx (e.g. 530 Worker Error) are explicitly counted as failure.

**Latency measurement**: Measured from `xrayReadyTime` (when SOCKS5 port opened)
to HTTP response. Xray startup time is logged separately and does not inflate
the stored latency used for IP ranking.

**Timeout budget**:
- Total budget: `phase2TimeoutSeconds` (default 15 s).
- HTTP test budget: `totalTimeout − xrayStartupSeconds`, minimum 5 s.
- Example: if Xray starts in 7 s, HTTP test gets 8 s (not 15 s).

**Parameters**:
- Total timeout: 15 s per IP
- Minimum HTTP test timeout: 5 s
- Concurrency: 1 (sequential — one Xray process at a time)
- Input: top `phase2TestDepth` IPs from Phase 1b (default: 50)
- Stops early: once `desiredIPCount` working IPs found (default: 10)

---

## JSON Export

After the scan, the app can export working IPs as Xray-compatible config files
for direct import into v2rayN, NekoBox, or any Xray-based app.

**Approach**: For each working IP, take the subscription template config and:
1. Substitute the clean IP as the outbound server address.
2. Drop the DNS section (users may not have geosite.dat/geoip.dat).
3. Strip geosite:/geoip: routing rules for the same reason.
4. Keep original inbounds (SOCKS5 + HTTP on standard ports).
5. Keep all other settings (fragmentation, TLS, ECH, etc.).

**Output formats**:
- JSON array: all IPs as separate configs (same format as BPB subscription).
  Import directly into v2rayN, NekoBox, etc.
- Single best-IP config: one clean config with the lowest-latency IP.

**Why not reconstruct from scratch**: The template config already contains all
the user's BPB Panel settings (UUID, password, fragment config, ECH config,
WebSocket path, etc.). Reconstructing from scratch would require re-parsing all
of these. Template substitution preserves all settings automatically.

---

## Parameter Reference

| Parameter | Default | Description |
|---|---|---|
| `maxSamplesPerCIDR` | 50 (mobile) / 100 (desktop) | IPs sampled per CIDR range |
| `batchSize` | 200 | Concurrent connections in Phase 0/1 |
| `tlsTimeoutSeconds` | 3 | TLS handshake timeout |
| `phase2TestDepth` | 50 | Phase 1b survivors to test in Phase 2 |
| `desiredIPCount` | 10 | Stop Phase 2 early once this many IPs found |
| `phase2TimeoutSeconds` | 15 | Xray proxy test timeout per IP |
| `enableIPv6` | false | Include IPv6 CIDR ranges in candidate pool |

---

## Why VLESS and Trojan Both Work

Both protocols connect to the same Cloudflare edge IP on port 443 with the same
SNI. The Cloudflare edge does not inspect the VPN protocol — it routes purely
on SNI to the worker. The worker then handles VLESS or Trojan identically. If
the IP reaches the worker (confirmed by Phase 2), both protocols work through it.
Testing with one protocol is sufficient.

---

## Temporal Stability

Clean Cloudflare IPs can degrade if:
- The user's ISP changes its routing to that Cloudflare PoP.
- Cloudflare shifts load between anycast nodes.
- The IP becomes congested.

The two-probe Phase 0 and two-pass Phase 1 significantly reduce false positives
by requiring consistency over two independent measurements. IPs that only pass
once are discarded. Recommended scan frequency: run a fresh scan every 24-48 h
or when VPN performance degrades.
