# Scanner Configuration Guide

This document explains the scan parameters available in the Configuration screen and how to tune them for your network.

## Overview

The scanner tests Cloudflare IPs using your actual BPB Panel Xray configs. It runs in three phases:

1. **Phase 1 (TLS)** — Concurrent TLS handshake test on all candidates
2. **Phase 2 (Proxy)** — Live Xray proxy test on the top Phase 1 results
3. **Results** — Top working IPs saved to BPB Panel

## Configuration Screen Parameters

### BPB Subscription URL (Required)

Your BPB Panel subscription URL. The app appends `?app=xray` to fetch Xray-format configs.

**Example:**
```
https://your-worker.workers.dev/sub/UUID
```

Tap **Fetch & Verify** to validate the URL before scanning. The app downloads the config and shows which protocol and SNI it will use for testing.

### Desired IP Count

- **What it does**: How many working IPs to save after the scan
- **Default**: 5
- **Recommended**: 3–10
- **Notes**: More IPs give BPB Panel more fallbacks, but a small number is enough for good reliability

### Phase 2 Test Depth

- **What it does**: How many Phase 1 passing IPs to test with the real Xray proxy (Phase 2)
- **Default**: 50
- **Recommended**: 20–100
- **Notes**:
  - Higher = more Phase 2 tests = better chance of finding working IPs, but slower scan
  - Lower = faster scan, but you may miss good IPs that failed Phase 1 narrowly
  - Set to 0 to skip Phase 2 entirely (results based on TLS latency only)

### Enable IPv6

- **What it does**: Include IPv6 Cloudflare IPs in the candidate pool
- **Default**: Off
- **When to enable**: If your network has native IPv6 connectivity
- **Notes**: IPv6 support on your network is required; enabling on an IPv4-only network results in all IPv6 IPs failing Phase 1

### Max Samples per CIDR

- **What it does**: Maximum number of IPs to sample from each Cloudflare CIDR range
- **Default**: 100
- **Range**: 10–500
- **Notes**:
  - Each sample is from a different /24 subnet (for IPv4), ensuring routing diversity
  - Higher = larger IP pool = more coverage, but slower Phase 1
  - Typical total pool size: 600–800 IPs with default settings

### Batch Size

- **What it does**: How many concurrent TLS connections to run during Phase 1
- **Default**: 200
- **Recommended**:
  - Mobile (4G/5G): 100–150
  - Home WiFi: 200–300
  - VPS: 300–500
- **Notes**: Higher = faster Phase 1, but excessive concurrency may trigger ISP throttling or socket limits

## Scan Phases in Detail

### Phase 1: TLS Handshake Test

```
[INFO] Phase 1: Testing 743 IPs for TLS connectivity...
[INFO] Phase 1 progress: 250/743 (33.6%) — success: 62, failed: 188
[INFO] Phase 1 progress: 500/743 (67.3%) — success: 121, failed: 379
[OK] Phase 1 complete: 152 IPs passed TLS handshake
```

**What happens per IP:**
1. TCP connect to `ip:443` (1-second timeout)
2. TLS handshake using the SNI hostname from your config
3. Success = valid TLS connection established
4. Measures handshake latency

**Results:** Sorted by TLS latency (fastest first). Top `phase2TestDepth` IPs advance.

**Typical duration:** 10–30 seconds

### Phase 2: Live Proxy Test

```
[INFO] Phase 2: Testing top 50 IPs with real Xray proxy...
[INFO] Testing 104.21.48.77... OK (latency: 142ms, status: 204)
[INFO] Testing 172.67.156.23... OK (latency: 188ms, status: 204)
[INFO] Testing 198.41.212.1... FAIL (timeout)
[OK] Phase 2 complete: 8 working IPs found
```

**What happens per IP:**
1. Xray-core binary is started with the candidate IP substituted into the outbound config
2. HTTP GET request is sent to `connectivitycheck.gstatic.com/generate_204` through the Xray SOCKS5 proxy
3. Success = **HTTP 204** response received
4. Measures full proxy round-trip latency

**Results:** Sorted by proxy latency (fastest first). Top `desiredIPCount` IPs are saved.

**Typical duration:** 5–15 seconds per IP. For 50 IPs, expect 5–10 minutes.

**Note:** Phase 2 requires the Xray-core binary to be available for your platform. On Web, Phase 2 is skipped and Phase 1 results are used.

## Result Interpretation

After the scan, the Results screen shows:

| Field | Meaning |
|-------|---------|
| Phase 1 Tested | Total candidate IPs tested for TLS |
| Phase 1 Passed | IPs with successful TLS handshake |
| Phase 2 Tested | IPs tested with live Xray proxy |
| Working IPs | IPs that returned HTTP 204 via proxy |

Each working IP shows its **proxy latency** (round-trip time through Xray, lower = better).

## Tuning for Your Network

### Fast Scan (fewer results, faster)
```
Phase 2 Test Depth: 20
Batch Size: 300
Max Samples per CIDR: 50
```
Expected time: 2–4 minutes

### Balanced Scan (default)
```
Phase 2 Test Depth: 50
Batch Size: 200
Max Samples per CIDR: 100
```
Expected time: 5–10 minutes

### Thorough Scan (better results, slower)
```
Phase 2 Test Depth: 100
Batch Size: 200
Max Samples per CIDR: 200
```
Expected time: 15–30 minutes

### Mobile Data
```
Batch Size: 100       (reduce concurrency on mobile)
Phase 2 Test Depth: 30
```

### No Working IPs Found

If Phase 2 finds 0 working IPs:
1. Verify your subscription URL is valid (use Fetch & Verify)
2. Check the config protocol is VLESS/WS — Reality configs may not work for all networks
3. Increase Phase 2 Test Depth (try 100)
4. Try scanning at a different time (ISP routing changes)
5. Check if Xray proxy actually works on your network using a standalone Xray client

### Phase 1 Finds 0 IPs

If Phase 1 finds no TLS successes:
1. Check your internet connection
2. Confirm port 443 is not blocked on your network
3. Try reducing Batch Size (some ISPs throttle high-concurrency connections)

## IP Database

The scanner tests IPs from bundled lists:
- `assets/ip_lists/ip.txt` — IPv4 Cloudflare CIDR ranges
- `assets/ip_lists/ipv6.txt` — IPv6 Cloudflare CIDR ranges

These are sourced from Cloudflare's published IP ranges and updated with each app release.

## Resource Usage

### Network Bandwidth
- Phase 1: Minimal (TLS handshakes only, < 1 MB total)
- Phase 2: Small (one HTTP 204 request per IP, < 5 MB total)

### Battery Impact (Mobile)
- Scan: moderate CPU + network during Phase 1 and Phase 2
- Recommendation: plug in device for long scans

### CPU Usage
- Phase 1: High concurrency, moderate CPU
- Phase 2: One Xray process at a time, low–moderate CPU

## Scheduling Recommendations

### How Often to Scan
- Heavy users: Every 6–12 hours
- Normal users: Every 1–2 days
- Light users: Weekly or on-demand

### When to Re-scan
- After switching networks (mobile data to WiFi and vice versa)
- When proxy connection becomes slow
- After ISP maintenance

### Best Times
- Off-peak hours (2 AM–6 AM local time)
- When device is charging and idle
