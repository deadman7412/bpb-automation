# Scanner Binaries

This directory contains platform-specific Cloudflare Clean IP Scanner binaries.

## Version Information

**Source**: [Cloudflare-Clean-IP-Scanner](https://github.com/bia-pain-bache/Cloudflare-Clean-IP-Scanner)
**Release**: v2.2.5
**Downloaded**: 2026-02-15

## Supported Platforms

| Platform | Architecture | Binary Name | Directory |
|----------|-------------|-------------|-----------|
| Android | ARM64 | CloudflareScanner | android-arm64/ |
| macOS | Intel (AMD64) | CloudflareScanner | darwin-amd64/ |
| macOS | Apple Silicon (ARM64) | CloudflareScanner | darwin-arm64/ |
| Linux | AMD64 | CloudflareScanner | linux-amd64/ |
| Windows | AMD64 | CloudflareScanner.exe | windows-amd64/ |

## SHA256 Checksums

```
83c3b6581c1f0507361b0551f019b95a660f0c5317edd7b197994d815f0665b1  android-arm64/CloudflareScanner
8892a612f89bea8ff8a280b4be6e21785763871f361ee035cc97e84a0fb2ffbd  darwin-amd64/CloudflareScanner
a40dffff90d6c55e1ed66dbc0d4af003fbf55fe19379f62469e953f57e44f3c2  darwin-arm64/CloudflareScanner
f9e2ec6e7a12aa6087148b35b65ab3d3c6d0a98080b4d4c80f91a83fbcfc2725  linux-amd64/CloudflareScanner
502488713767fe957cc78ca43f4029c10a7f3bbc0dddf5853e9316009ad93cd7  windows-amd64/CloudflareScanner.exe
```

## Verification

To verify the integrity of a binary:

```bash
# macOS/Linux
shasum -a 256 path/to/CloudflareScanner

# Windows
certutil -hashfile path\to\CloudflareScanner.exe SHA256
```

Compare the output with the checksums listed above.

## Binary Details

Each binary directory contains:
- **CloudflareScanner** (or CloudflareScanner.exe on Windows) - Main executable
- **README.md** - Scanner documentation
- **ip.txt** - Default IPv4 ranges to scan
- **ipv6.txt** - Default IPv6 ranges to scan

## Usage Notes

### Execute Permissions (Unix/Linux/macOS)

Before running the scanner on Unix-based systems, ensure execute permissions are set:

```bash
chmod +x CloudflareScanner
```

The app will handle this automatically during binary extraction.

### Platform-Specific Notes

**Android**: Binary is ARM64 only. Most modern Android devices (2015+) support ARM64.

**macOS**: Two binaries provided:
- Intel (darwin-amd64) for Intel Macs
- Apple Silicon (darwin-arm64) for M1/M2/M3 Macs

**Linux**: AMD64 binary. Tested on Ubuntu/Debian-based distributions.

**Windows**: Requires Windows 10 or later (64-bit).

## Scanner Parameters

The scanner accepts various command-line parameters for configuration. See [docs/scanner-configuration.md](../../docs/scanner-configuration.md) for details.

## Updates

To update to a newer version:
1. Download new binaries from GitHub releases
2. Extract to the appropriate directories
3. Update version information in this README
4. Generate new SHA256 checksums
5. Update app version if needed

## Security

All binaries are:
- Downloaded from official GitHub releases
- SHA256 checksums verified
- Executed in sandboxed environment (platform-dependent)
- Never modified after download

## License

Binaries are from the Cloudflare-Clean-IP-Scanner project.
See the original repository for license information.
