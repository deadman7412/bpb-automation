# Xray-core Binaries

This directory contains Xray-core binaries used for Phase 2 proxy testing in config-based clean IP scanning.

## Version Information

- **Version**: v26.2.6
- **Release Date**: February 6, 2026
- **Source**: [XTLS/Xray-core](https://github.com/XTLS/Xray-core/releases/tag/v26.2.6)
- **Bundled Date**: February 18, 2026

## Included Platforms

### Android
- **Platform**: android-arm64-v8a
- **File**: `android-arm64/xray`
- **Size**: ~34 MB
- **SHA256**: `d3dab5cf776d8619cea6f5317027c2a59004602cffb195dd9acb067038171287`

### macOS (Intel)
- **Platform**: darwin-amd64
- **File**: `darwin-amd64/xray`
- **Size**: ~33 MB
- **SHA256**: `c9f5f35e8ad3649a03c75291278eab2c470573bd0e0d34da506bab3a09673172`

### macOS (Apple Silicon)
- **Platform**: darwin-arm64
- **File**: `darwin-arm64/xray`
- **Size**: ~31 MB
- **SHA256**: `76fea3ec3610c2cc462ef39422ddc00e6d306b0c90223c983eaced6b12c8dee8`

### Linux
- **Platform**: linux-amd64
- **File**: `linux-amd64/xray`
- **Size**: ~34 MB
- **SHA256**: `3f650abf1fc4a4fbf5abe7fc9990a2658020907cd984214e9c075b4b00989fea`

### Windows
- **Platform**: windows-amd64
- **File**: `windows-amd64/xray.exe`
- **Size**: ~33 MB
- **SHA256**: `103da2750f4348a266ae61632c322f95cf3e18dce99eb588e685379f041e97c5`

## License

Xray-core is licensed under the Mozilla Public License Version 2.0 (MPL-2.0).

Full license: https://github.com/XTLS/Xray-core/blob/main/LICENSE

## Purpose

These binaries are used by the BPB Automation app to perform Phase 2 proxy testing:

1. Phase 1 (TLS Pre-filter): Tests candidate IPs with TLS handshake
2. Phase 2 (Proxy Testing): Uses Xray-core to verify actual proxy functionality

The Xray binary is started with a modified config (candidate IP substituted), then a SOCKS5 connection is established to test real-world proxy connectivity.

## Security Notes

- Binaries are extracted from official GitHub releases
- SHA256 checksums are provided for verification
- Binaries are bundled in the Flutter app assets at build time
- On first run, the appropriate binary is extracted to app's documents directory
- Execute permissions are set automatically on Unix-based systems

## Usage in App

The `XrayService` class handles:
- Platform detection
- Binary extraction to app directory
- Version tracking
- Process lifecycle management
- SOCKS5 connectivity testing

See `lib/services/xray_service.dart` for implementation details.

## Total Size Impact

Adding these binaries increases the app size by approximately:
- **Android APK**: +34 MB (android-arm64 only)
- **macOS App**: +64 MB (both amd64 and arm64)
- **Linux Build**: +34 MB (amd64 only)
- **Windows Build**: +33 MB (amd64 only)

The appropriate binary for each platform is bundled during the build process.

## Updating Binaries

To update to a newer version of Xray-core:

1. Download new binaries from [Xray-core releases](https://github.com/XTLS/Xray-core/releases)
2. Extract and replace binaries in respective directories
3. Calculate new SHA256 checksums
4. Update this README with new version info and checksums
5. Update version check in `XrayService` if needed
