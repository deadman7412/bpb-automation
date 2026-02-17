# Distribution Materials

This document outlines the required materials for app distribution across all platforms.

## App Icon

### Icon Design Specifications

**Design Concept:**
- Icon: Cloud with sync/refresh symbol
- Colors: Blue gradient (Material 3 primary color)
- Style: Modern, clean, recognizable at all sizes

**Required Sizes:**

#### Android
- `mipmap-mdpi/ic_launcher.png` - 48x48
- `mipmap-hdpi/ic_launcher.png` - 72x72
- `mipmap-xhdpi/ic_launcher.png` - 96x96
- `mipmap-xxhdpi/ic_launcher.png` - 144x144
- `mipmap-xxxhdpi/ic_launcher.png` - 192x192
- `play_store_512.png` - 512x512 (Google Play Store)

#### iOS
- `Icon-App-20x20@1x.png` - 20x20
- `Icon-App-20x20@2x.png` - 40x40
- `Icon-App-20x20@3x.png` - 60x60
- `Icon-App-29x29@1x.png` - 29x29
- `Icon-App-29x29@2x.png` - 58x58
- `Icon-App-29x29@3x.png` - 87x87
- `Icon-App-40x40@1x.png` - 40x40
- `Icon-App-40x40@2x.png` - 80x80
- `Icon-App-40x40@3x.png` - 120x120
- `Icon-App-60x60@2x.png` - 120x120
- `Icon-App-60x60@3x.png` - 180x180
- `Icon-App-76x76@1x.png` - 76x76
- `Icon-App-76x76@2x.png` - 152x152
- `Icon-App-83.5x83.5@2x.png` - 167x167
- `Icon-App-1024x1024@1x.png` - 1024x1024 (App Store)

#### macOS
- `app_icon_16.png` - 16x16
- `app_icon_32.png` - 32x32
- `app_icon_64.png` - 64x64
- `app_icon_128.png` - 128x128
- `app_icon_256.png` - 256x256
- `app_icon_512.png` - 512x512
- `app_icon_1024.png` - 1024x1024

#### Windows
- `app_icon.ico` - Multi-resolution ICO (16, 32, 48, 256)

#### Linux
- `app_icon_16.png` - 16x16
- `app_icon_32.png` - 32x32
- `app_icon_64.png` - 64x64
- `app_icon_128.png` - 128x128
- `app_icon_256.png` - 256x256
- `app_icon_512.png` - 512x512

### Design Guidelines
- Use simple, recognizable symbol
- Ensure visibility at smallest sizes (16x16)
- Maintain brand consistency
- Follow platform-specific design guidelines
- Test on light and dark backgrounds

## Screenshots

### Required Screenshots Per Platform

#### Android (Google Play Store)
**Requirements:**
- Minimum 2 screenshots
- Recommended 4-8 screenshots
- Format: PNG or JPEG
- Dimensions: 16:9 or 9:16 aspect ratio
- Min: 320px, Max: 3840px

**Screenshots Needed:**
1. Home screen with scan button (showing app ready state)
2. Scan in progress (showing progress indicator and status)
3. Results screen (showing clean IP list with statistics)
4. Settings screen (showing credential configuration)
5. Configuration screen (showing scanner parameters)
6. Logs screen (showing real-time logging)

#### iOS (App Store)
**Requirements:**
- 6.5" display: 1284x2778 (3 screenshots minimum)
- 5.5" display: 1242x2208 (3 screenshots minimum)
- 12.9" iPad: 2048x2732 (3 screenshots minimum)

**Screenshots:** Same content as Android, sized appropriately

#### macOS (Mac App Store)
**Requirements:**
- 1280x800 minimum
- 2560x1600 maximum
- 3-5 screenshots recommended

**Screenshots:** Desktop-sized versions of main screens

#### Windows/Linux
**Requirements:**
- 1920x1080 recommended
- 3-5 screenshots for documentation

**Screenshots:** Desktop layouts

### Screenshot Guidelines
- Show actual app functionality
- Use light mode for primary screenshots
- Include one dark mode screenshot
- Avoid placeholder/dummy data
- Highlight key features
- Keep UI clean and uncluttered

## Release Notes Template

See `docs/release-notes-template.md` for the standard template used for all releases.

## Download Instructions

See `docs/download-install-guide.md` for platform-specific download and installation instructions.

## Installation Guides

### Per-Platform Guides

#### Android Installation
See [Android Installation Guide](install-android.md)

#### iOS Installation
See [iOS Installation Guide](install-ios.md)

#### macOS Installation
See [macOS Installation Guide](install-macos.md)

#### Linux Installation
See [Linux Installation Guide](install-linux.md)

#### Windows Installation
See [Windows Installation Guide](install-windows.md)

## Marketing Copy

### App Store Short Description (80 characters max)
"Find and update clean Cloudflare IPs for your BPB Panel automatically"

### App Store Long Description

**BPB Automation** helps you find the fastest Cloudflare IPs for your network and automatically updates your BPB Panel configuration.

**Key Features:**
- Scan for clean Cloudflare IPs from your device
- No VPS required - runs on your phone or computer
- Automatic BPB Panel updates via Cloudflare API
- No credentials needed for scanning
- Secure credential storage
- Cross-platform: Android, iOS, macOS, Linux, Windows
- Real-time scan progress
- Comprehensive logging
- Dark mode support

**How It Works:**
1. Download and install the app
2. (Optional) Configure Cloudflare credentials
3. Run a scan to find clean IPs
4. View results and optionally update BPB Panel

**Why Use This App:**
- Find IPs optimized for YOUR network and location
- Test from your actual device (mobile data, WiFi)
- No manual CSV editing
- Automated updates with one tap
- Completely secure - all data stays on your device

**Requirements:**
- Internet connection
- For auto-updates: Cloudflare account with BPB Panel

**Privacy:**
- No analytics or tracking
- No cloud storage
- All data stored locally
- Only connects to Cloudflare API

Perfect for BPB Panel users who want optimal performance without manual IP management.

### Keywords (for app stores)
cloudflare, bpb, clean ip, proxy, vpn, scanner, ip scanner, cloudflare scanner, bpb panel, worker, kv, automation

## Social Media Assets

### Twitter/X Post
"BPB Automation v1.0.0 is here! Find clean Cloudflare IPs and update your BPB Panel automatically. No VPS needed. Cross-platform support. Download now: [link]"

### Reddit Post Title
"BPB Automation v1.0.0 - Cross-platform tool for finding and updating clean Cloudflare IPs"

### Reddit Post Body
```
Hi everyone,

I'm excited to share BPB Automation v1.0.0 - a cross-platform app that automates finding and updating clean Cloudflare IPs for BPB Panel.

Features:
- Scan from your actual device (mobile/desktop)
- No VPS required
- One-tap BPB Panel updates
- No credentials needed for scanning
- Works on Android, iOS, macOS, Linux, Windows

The app wraps the Cloudflare Clean IP Scanner and provides a user-friendly interface with automatic BPB Panel updates via Cloudflare Workers KV API.

Download: [GitHub Releases]
Docs: [Link to docs]
Source: [GitHub]

Feedback welcome!
```

## File Naming Conventions

### Release Files
- Android: `bpb-automation-v1.0.0-android.apk`
- iOS: `bpb-automation-v1.0.0-ios.ipa`
- macOS: `bpb-automation-v1.0.0-macos.dmg`
- macOS (App): `bpb-automation-v1.0.0-macos.app.zip`
- Linux AppImage: `bpb-automation-v1.0.0-linux-x86_64.AppImage`
- Linux DEB: `bpb-automation_1.0.0_amd64.deb`
- Windows: `bpb-automation-v1.0.0-windows-setup.exe`
- Windows (Portable): `bpb-automation-v1.0.0-windows.zip`

### Screenshot Files
- `screenshot-android-01-home.png`
- `screenshot-android-02-scanning.png`
- `screenshot-android-03-results.png`
- `screenshot-android-04-settings.png`
- `screenshot-android-05-config.png`
- `screenshot-android-06-logs.png`
(repeat pattern for each platform)

## Checklist for Release

### Pre-Release
- [ ] App icon generated for all sizes
- [ ] Screenshots captured for all platforms
- [ ] Release notes finalized
- [ ] CHANGELOG.md updated
- [ ] Version numbers updated in code
- [ ] All tests passing
- [ ] Builds successful for all platforms
- [ ] Code signed (where applicable)

### Distribution Files
- [ ] Android APK generated and tested
- [ ] macOS .app and .dmg created
- [ ] Linux AppImage created
- [ ] Windows installer created
- [ ] All files named correctly
- [ ] Checksums generated (SHA256)

### Documentation
- [ ] README.md updated
- [ ] User guide complete
- [ ] Installation guides verified
- [ ] Download links tested
- [ ] Screenshots added to documentation

### Publishing
- [ ] GitHub release created
- [ ] Release notes published
- [ ] Download links updated
- [ ] Social media announcements prepared
- [ ] Community notifications sent

## Support Materials

### FAQ Document
Common questions and answers for distribution platforms.

### Troubleshooting Guide
Platform-specific troubleshooting steps.

### Video Tutorials (Optional)
- Quick start guide (2-3 minutes)
- Full setup walkthrough (5-10 minutes)
- Advanced configuration (5 minutes)

## Legal

### License
To be determined - add LICENSE file before distribution

### Privacy Policy
Required for app stores - see `docs/privacy-policy.md` (to be created)

### Terms of Service
Optional but recommended - see `docs/terms-of-service.md` (to be created)

---

Last Updated: 2026-02-16
Version: 1.0.0
