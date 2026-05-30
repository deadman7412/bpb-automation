# Xray-core Binaries

This directory contains Xray-core binaries used for Phase 2 proxy testing in config-based clean IP scanning.

## Version Information

- **Version**: v26.3.27
- **Release Date**: March 27, 2026
- **Source**: [XTLS/Xray-core](https://github.com/XTLS/Xray-core/releases/tag/v26.3.27)
- **Bundled Date**: May 30, 2026

## Included Platforms

### Android
- **Platform**: android-arm64-v8a
- **File**: `android-arm64/xray`
- **Size**: ~34 MB
- **SHA256**: `19101a8191d6d606da975f719c8cdb80b8710b87ab17edc00ef74b9e39588714`

### macOS (Intel)
- **Platform**: darwin-amd64
- **File**: `darwin-amd64/xray`
- **Size**: ~33 MB
- **SHA256**: `afd0eaebb77994a18f29b00c5f50a4f7fbb77da06e24352d43035f3cad3c3786`

### macOS (Apple Silicon)
- **Platform**: darwin-arm64
- **File**: `darwin-arm64/xray`
- **Size**: ~31 MB
- **SHA256**: `5d9dd24c0aba4b6cfcc6a33a5d67f854816ee17f392bf932ec8176da46f7e404`

### Linux
- **Platform**: linux-amd64
- **File**: `linux-amd64/xray`
- **Size**: ~34 MB
- **SHA256**: `8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed`

### Windows
- **Platform**: windows-amd64
- **File**: `windows-amd64/xray.exe`
- **Size**: ~33 MB
- **SHA256**: `15c2d007954ac53ba69b80ec91242786b3c0b71d52649165b4ca1d5cc96ef8f1`

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
