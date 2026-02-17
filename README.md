# BPB Automation

Cross-platform application for automatically scanning and updating clean Cloudflare IPs in BPB Panel.

## Overview

BPB Automation helps you find the fastest Cloudflare IPs for your network and automatically updates your BPB Panel configuration via Cloudflare Workers KV API.

## Key Features

- **Pure Dart IP scanner** - Native implementation, no binary dependencies
- **Subnet-aware IP selection** - One IP per /24 subnet for maximum routing diversity
- **EWMA quality scoring** - Sustained throughput measurement, not peak speed
- **Loss-rate-first sorting** - Prioritizes connection stability over raw speed
- Scan for clean Cloudflare IPs from your actual network
- TCP latency testing (1s aggressive timeout) + HTTPS download speed testing
- Automatic BPB Panel settings update via API
- Cross-platform support: Android, iOS, macOS, Linux, Windows, Web
- Offline-first design (no hosting required)
- No sandboxing issues (works on all platforms including macOS)
- Secure credential storage
- User-friendly interface (no terminal needed)
- Real-time progress tracking with detailed statistics
- Advanced scanner configuration options

## Supported Platforms

- Android (Primary)
- macOS
- Linux
- Windows
- Web (requires VPS backend)
- iOS (coming soon)

## Quick Start

### Installation

Download the appropriate version for your platform:
- Android: `bpb-automation.apk`
- macOS: `bpb-automation.dmg`
- Linux: `bpb-automation.AppImage` or `.deb`
- Windows: `bpb-automation-setup.exe`

### Setup

1. Install the app
2. Run your first scan (no credentials needed for scanning)
3. Get your Cloudflare credentials (see [Cloudflare Setup Guide](docs/cloudflare-setup.md))
4. Enter credentials in app settings
5. Update BPB Panel with clean IPs

**Note:** Cloudflare credentials are only required for updating BPB Panel. You can scan and view clean IPs without credentials.

## Documentation

- [User Guide](docs/user-guide.md) - Complete usage instructions
- [Cloudflare Setup](docs/cloudflare-setup.md) - How to get credentials
- [Scanner Configuration](docs/scanner-configuration.md) - Scanner parameters explained
- [Development Guide](docs/development.md) - For developers
- [Deployment Guide](docs/deployment.md) - Building and distributing

## Requirements

### For Users
- Internet connection

**For Scanning Only:**
- No additional requirements

**For BPB Panel Updates:**
- Cloudflare account with BPB Panel installed
- API token with Workers KV Edit permission
- Account ID and KV Namespace ID

### For Developers
- Flutter SDK (latest stable)
- Platform-specific tools (Android Studio, Xcode, etc.)
- See [Development Guide](docs/development.md)

## Testing

### Run All Tests (Recommended for CI)
```bash
# Run unit tests only (excludes integration tests)
flutter test --exclude-tags=integration
```

### Run Specific Test Suites
```bash
# Run only model tests
flutter test test/models/

# Run only service tests
flutter test test/services/

# Run integration tests (requires network access)
flutter test --tags=integration
```

### Test Categories
- **Unit Tests** - Fast, isolated tests for models and services (338 tests)
- **Integration Tests** - Slow, network-dependent tests against real Cloudflare IPs
  - Tagged with `@Tags(['integration'])`
  - May fail in CI due to rate limiting or network restrictions
  - Should be run manually or in separate CI job with proper network access

**Note:** Integration tests use real network requests to Cloudflare and may be rate-limited (HTTP 429). For reliable CI/CD, always use `--exclude-tags=integration`.

## How It Works

### Scanner Algorithm (Aligned with Go Scanner)

1. **IP Loading with Subnet Diversity**
   - Loads Cloudflare IP ranges from CIDR notation
   - IPv4: Selects one random IP per /24 subnet (ensures routing diversity)
   - IPv6: Pure random sampling across /32 ranges
   - Result: IPs connect through different Cloudflare edge servers

2. **Latency Testing**
   - TCP socket connection to port 443
   - Aggressive 1-second timeout (matches Go scanner)
   - 2 attempts per IP
   - Measures connection establishment time

3. **Speed Testing (EWMA Quality Score)**
   - Downloads from speed.cloudflare.com
   - Samples speed every 100ms using EWMA (Exponentially Weighted Moving Average)
   - Calculates sustained throughput quality (not peak speed)
   - Normalization factor: timeout/120 (matches Go scanner)

4. **Multi-Criteria Sorting**
   - Priority 1: Loss rate (lower is better) - MOST IMPORTANT
   - Priority 2: Latency (lower is better)
   - Priority 3: Quality score (higher is better)

5. **BPB Panel Update**
   - Updates Workers KV via Cloudflare API
   - Only modifies cleanIPs field (preserves other settings)
   - Your proxy connection uses the new optimized IPs

**Why This Algorithm Works Better:**
- Different /24 subnets = different network routes to your ISP
- EWMA quality score filters out inconsistent IPs with brief speed bursts
- Loss-rate-first sorting prioritizes connection stability
- Result: More reliable BPB Panel connections

**Technical Implementation:**
- Pure Dart - no external binaries or sandboxing issues
- TCP socket connections for latency measurement
- Raw HTTPS with manual HTTP protocol for speed testing
- Configurable concurrency (1-1000 threads)
- EWMA-based quality scoring (alpha=0.2)

## Why Use This App

- **Better IP Quality** - Subnet-aware selection ensures routing diversity
- **More Reliable** - EWMA scoring favors sustained performance over peaks
- **Network-Specific** - Tests from your actual network (mobile ISP, WiFi)
- **No VPS Required** - Runs directly on your device
- **Automated Updates** - No manual CSV editing or configuration
- **Secure** - All data stays local, encrypted credentials
- **Clean IPs Specific to You** - Optimized for your location and ISP routing

## Security & Privacy

- Credentials encrypted with platform keychain
- No cloud storage or third-party services
- No analytics or tracking
- Only connects to Cloudflare API
- All network requests user-initiated

## Contributing

Contributions welcome. Please follow the guidelines in [Development Guide](docs/development.md).

## License

To be determined.

## Credits

- [Cloudflare-Clean-IP-Scanner](https://github.com/bia-pain-bache/Cloudflare-Clean-IP-Scanner) - Algorithm aligned with Go scanner implementation
  - Subnet-aware IPv4 selection (one IP per /24 subnet)
  - EWMA quality scoring methodology
  - Loss-rate-first sorting priority
- [BPB-Worker-Panel](https://github.com/bia-pain-bache/BPB-Worker-Panel) - Panel software
- IP lists sourced from Cloudflare's official IP ranges
- EWMA implementation inspired by github.com/VividCortex/ewma

## Support

For issues and questions:
- Check [User Guide](docs/user-guide.md)
- Review [Troubleshooting](docs/user-guide.md#troubleshooting)
- See logs in app (Settings > View Logs)

## Roadmap

- [x] Core scanning functionality
- [x] Cloudflare API integration
- [x] Multi-platform support
- [ ] Scheduled auto-scans
- [ ] Multi-account support
- [ ] Custom IP lists
- [ ] Cloud backup (optional)
- [ ] In-app updates

## Version

Current: 1.0.0 (Initial Release)

See CHANGELOG.md for version history.

