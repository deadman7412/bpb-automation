# Scanner Configuration Guide

This document explains the Cloudflare IP Scanner parameters and how to configure them in the app.

## Overview

The Cloudflare Clean IP Scanner tests latency and download speeds across multiple Cloudflare IPs to find the fastest, most reliable connections for your network.

## Default Configuration

The app comes with sensible defaults that work well for most users:

```
Threads: 200
Test Count: 4
Download Test Count: 10
Latency Upper Limit: 200ms
Latency Lower Limit: 40ms
Speed Limit: 5 MB/s
Number of IPs to Use: 10
```

## Basic Settings (Main UI)

### Number of Clean IPs
- **What it does**: How many IPs to save in your BPB Panel
- **Default**: 10
- **Recommended**: 5-15
- **Why**: More IPs provide redundancy, but too many can slow config loading

## Advanced Settings (Advanced Menu)

### Threads (-n)
- **What it does**: Number of concurrent latency tests
- **Default**: 200
- **Range**: 1-1000
- **Impact**:
  - Higher = Faster scanning
  - Too high = May trigger ISP throttling
- **Recommended**:
  - Mobile: 100-200
  - WiFi: 200-400
  - VPS: 200-500

### Test Count (-t)
- **What it does**: Number of tests per IP
- **Default**: 4
- **Range**: 1-10
- **Impact**:
  - Higher = More accurate results
  - Higher = Slower scanning
- **Recommended**: 3-5

### Download Test Count (-dn)
- **What it does**: How many IPs to download-test (fastest latency)
- **Default**: 10
- **Range**: 0-100 (0 = disable download test)
- **Impact**:
  - Tests actual throughput
  - Most time-consuming part
- **Recommended**: 10-20

### Latency Upper Limit (-tl)
- **What it does**: Maximum acceptable latency (milliseconds)
- **Default**: 200
- **Range**: 1-1000
- **Impact**: IPs slower than this are filtered out
- **Recommended**:
  - Excellent connection: 100-150ms
  - Good connection: 150-200ms
  - Acceptable: 200-300ms

### Latency Lower Limit (-tll)
- **What it does**: Minimum latency threshold (milliseconds)
- **Default**: 40
- **Range**: 1-500
- **Impact**: IPs faster than this are excluded (suspiciously fast)
- **Recommended**: 30-50ms

### Speed Limit (-sl)
- **What it does**: Minimum download speed (MB/s)
- **Default**: 5
- **Range**: 0.1-100
- **Impact**: IPs slower than this are filtered out
- **Recommended**:
  - Fast connection: 10-20 MB/s
  - Normal: 5-10 MB/s
  - Slow: 1-5 MB/s

### Disable Download Test (-dd)
- **What it does**: Skip speed testing, sort by latency only
- **Default**: false (enabled)
- **When to enable**:
  - Quick scans needed
  - Limited bandwidth
  - Latency more important than speed
- **Impact**: Much faster scanning (30-60 seconds vs 3-5 minutes)

### HTTP Mode (-httping)
- **What it does**: Use HTTP protocol instead of TCP
- **Default**: false (TCP mode)
- **When to enable**:
  - TCP blocked by firewall
  - More accurate HTTP-specific testing
- **Impact**:
  - 2-second timeout (vs 1-second TCP)
  - Higher resource usage
  - Reduce threads if enabled (try 100-150)

## Scanning Process

### Phase 1: Latency Testing
```
[INFO] Starting latency tests...
[INFO] Testing 1000 IPs with 200 threads...
[INFO] Progress: 250/1000 (25%)
[INFO] Progress: 500/1000 (50%)
[INFO] Progress: 750/1000 (75%)
[OK] Latency testing complete: 234 IPs passed filters
```

**Duration**: 10-30 seconds (depending on threads)

### Phase 2: Speed Testing
```
[INFO] Starting download tests...
[INFO] Testing top 10 IPs for speed...
[INFO] Testing: 104.21.48.77 -> 12.5 MB/s
[INFO] Testing: 172.67.156.23 -> 15.2 MB/s
[OK] Speed testing complete
```

**Duration**: 2-5 minutes (depending on download test count)

### Phase 3: Results
```
[OK] Scan complete!
[INFO] Found 10 clean IPs
[INFO] Fastest: 172.67.156.23 (15.2 MB/s, 85ms)
[INFO] Slowest: 104.19.203.112 (8.1 MB/s, 142ms)
```

## Result Interpretation

### CSV Output Format
```
IP Address,Sent,Received,Loss Rate,Avg Latency,Download Speed
172.67.156.23,4,4,0.00%,85.2,15.2
104.21.48.77,4,4,0.00%,92.1,12.5
...
```

**Column Meanings:**
- **IP Address**: Cloudflare CDN IP
- **Sent**: Packets sent during test
- **Received**: Packets received back
- **Loss Rate**: Percentage of lost packets (0% is best)
- **Avg Latency**: Average response time in milliseconds (lower is better)
- **Download Speed**: Throughput in MB/s (higher is better)

### IP Selection Logic
1. Filter IPs by latency (within limits)
2. Filter by packet loss (0% preferred)
3. Run download tests on top N by latency
4. Sort final results by download speed
5. Take top N IPs for BPB Panel

## Network-Specific Recommendations

### Mobile Data (4G/5G)
```
Threads: 100-150
Latency Limit: 250ms
Speed Limit: 5 MB/s
Download Tests: 10
```

### Home WiFi
```
Threads: 200-300
Latency Limit: 200ms
Speed Limit: 10 MB/s
Download Tests: 15
```

### VPS/Server
```
Threads: 300-500
Latency Limit: 150ms
Speed Limit: 20 MB/s
Download Tests: 20
```

### Restricted Networks (Firewall/Proxy)
```
Threads: 100
HTTP Mode: Enabled
Latency Limit: 300ms
Download Tests: 5
```

## Troubleshooting

### Scan Takes Too Long
- Reduce thread count
- Reduce download test count
- Enable "Disable Download Test"
- Increase latency limit (fewer IPs to test)

### No IPs Found
- Increase latency upper limit (try 300-500ms)
- Decrease speed limit (try 1-3 MB/s)
- Check internet connection
- Try HTTP mode if TCP is blocked

### Inaccurate Results
- Increase test count (try 5-8)
- Run scan during off-peak hours
- Disable other network-heavy apps
- Try different times of day

### ISP Throttling
- Reduce thread count (try 50-100)
- Enable HTTP mode
- Add delays between tests (future feature)

## Performance Tips

### Quick Scan (1-2 minutes)
```
Threads: 300
Test Count: 3
Disable Download: Yes
```

### Accurate Scan (5-10 minutes)
```
Threads: 200
Test Count: 5
Download Tests: 20
```

### Balanced Scan (3-5 minutes)
```
Threads: 200
Test Count: 4
Download Tests: 10
```

## IP Database

The scanner tests IPs from built-in lists:
- `ip.txt` - IPv4 Cloudflare ranges
- `ipv6.txt` - IPv6 Cloudflare ranges (if enabled)

These are bundled with the app and updated periodically.

## Scheduling Recommendations

### How Often to Scan

- **Heavy Users**: Every 6-12 hours
- **Normal Users**: Every 24 hours
- **Light Users**: Weekly or on-demand

### Best Times to Scan

- Off-peak hours (2AM-6AM local time)
- When you experience slowdowns
- After ISP maintenance
- When changing networks (home/mobile/work)

## Advanced Use Cases

### Multiple ISPs
Run scans on each network separately:
1. Scan on mobile data -> Save results as "Mobile"
2. Scan on home WiFi -> Save results as "Home"
3. Manual switching based on current network

### Testing Specific IP Ranges
Future feature: Custom IP list input

### Continuous Monitoring
Future feature: Background scanning with notifications

## Command-Line Equivalent

For reference, the app runs commands similar to:

```bash
# Basic scan
./CloudflareScanner -n 200 -t 4 -dn 10 -tl 200 -o result.csv

# Fast scan (no download test)
./CloudflareScanner -n 300 -t 3 -dd -tl 200 -o result.csv

# Accurate scan
./CloudflareScanner -n 200 -t 5 -dn 20 -tl 150 -sl 10 -o result.csv

# HTTP mode
./CloudflareScanner -httping -n 150 -t 4 -dn 10 -tl 250 -o result.csv
```

## Resource Usage

### Network Bandwidth
- Latency test: Minimal (<1 MB total)
- Download test: ~10-50 MB per scan
- Total: 10-50 MB per scan

### Battery Impact (Mobile)
- Quick scan: ~1-2% battery
- Full scan: ~3-5% battery
- Recommendation: Run while charging for scheduled scans

### CPU Usage
- Moderate during scanning
- Minimal when idle
- No background activity unless scheduled

## Future Enhancements

Planned features:
- Custom IP lists
- Scan profiles (Quick/Balanced/Thorough)
- Comparison mode (before/after)
- Historical trends
- Automatic optimization based on network type
- IPv6 support toggle
