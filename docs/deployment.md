# Deployment Guide

This guide covers building and distributing the app for all supported platforms.

## Pre-Build Checklist

- [ ] All tests passing: `flutter test`
- [ ] No analyzer warnings: `flutter analyze`
- [ ] Code formatted: `dart format .`
- [ ] Version updated in `pubspec.yaml`
- [ ] CHANGELOG.md updated
- [ ] Scanner binaries bundled in assets
- [ ] No dev environment references in code
- [ ] No emojis in code or UI

## Version Numbering

Format: `MAJOR.MINOR.PATCH+BUILD`

Example: `1.0.0+1`

Update in `pubspec.yaml`:
```yaml
version: 1.0.0+1
```

## Android

### Debug Build (Testing)

```bash
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`

### Release Build (Production)

#### 1. Create Keystore (First Time Only)

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Save keystore password and key password securely.

#### 2. Configure Signing

Create `android/key.properties`:
```properties
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=<path-to-keystore>/upload-keystore.jks
```

Add to `android/.gitignore`:
```
key.properties
```

#### 3. Update build.gradle

In `android/app/build.gradle`:

```gradle
// Add before android block
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    // ... existing config

    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }

    buildTypes {
        release {
            signingConfig signingConfigs.release
            // ... other settings
        }
    }
}
```

#### 4. Build Release APK

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

#### 5. Build App Bundle (For Play Store)

```bash
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

### Optimization Options

```bash
# Smaller APK (separate per-ABI)
flutter build apk --release --split-per-abi

# Outputs:
# - app-armeabi-v7a-release.apk
# - app-arm64-v8a-release.apk
# - app-x86_64-release.apk

# Obfuscate code
flutter build apk --release --obfuscate --split-debug-info=build/debug-info
```

### Testing Release Build

```bash
# Install on device
flutter install --release

# Or via adb
adb install build/app/outputs/flutter-apk/app-release.apk
```

### Distribution

#### Sideload (Recommended for this app)
1. Share APK file directly
2. Users enable "Install from Unknown Sources"
3. Install APK

#### Google Play Store (Optional)
1. Create developer account ($25 one-time)
2. Upload app-release.aab
3. Follow Play Console setup

## iOS

### Prerequisites
- Apple Developer Account ($99/year)
- Xcode with command-line tools
- Valid signing certificate

### Debug Build

```bash
flutter build ios --debug
```

### Release Build

#### 1. Configure Xcode Project

```bash
open ios/Runner.xcworkspace
```

In Xcode:
1. Select Runner project
2. Update Bundle Identifier (e.g., `com.bpb.automation`)
3. Select Team (your Apple Developer account)
4. Update Version and Build numbers

#### 2. Build IPA

```bash
flutter build ios --release
```

#### 3. Create Archive

In Xcode:
1. Product → Archive
2. Wait for build to complete
3. Window → Organizer
4. Select archive
5. Distribute App

#### 4. Distribution Options

**Ad Hoc Distribution:**
- For testing on registered devices
- No App Store review needed
- Limited to 100 devices

**App Store:**
- Public distribution
- Requires App Store review
- In-app purchases, subscriptions available

**Enterprise:**
- Internal company distribution
- Requires Enterprise Developer account

### TestFlight Distribution

1. Upload to App Store Connect
2. Add internal/external testers
3. Share TestFlight link
4. Users install via TestFlight app

## macOS

### Debug Build

```bash
flutter build macos --debug
```

### Release Build

```bash
flutter build macos --release
```

Output: `build/macos/Build/Products/Release/bpb_automation.app`

### Code Signing

```bash
# Sign with Developer ID
codesign --deep --force --verify --verbose --sign "Developer ID Application: Your Name" build/macos/Build/Products/Release/bpb_automation.app
```

### Create DMG Installer

```bash
# Create DMG
hdiutil create -volname "BPB Clean IP Updater" -srcfolder build/macos/Build/Products/Release/bpb_automation.app -ov -format UDZO bpb-automation.dmg
```

### Notarization (Required for macOS 10.15+)

```bash
# Submit for notarization
xcrun altool --notarize-app --primary-bundle-id com.bpb.automation --username "your@email.com" --password "@keychain:AC_PASSWORD" --file bpb-automation.dmg

# Check status
xcrun altool --notarization-info <RequestUUID> --username "your@email.com" --password "@keychain:AC_PASSWORD"

# Staple ticket
xcrun stapler staple bpb-automation.dmg
```

## Linux

### Prerequisites

```bash
# Ubuntu/Debian
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev

# Fedora
sudo dnf install clang cmake ninja-build gtk3-devel

# Arch
sudo pacman -S clang cmake ninja gtk3
```

### Debug Build

```bash
flutter build linux --debug
```

### Release Build

```bash
flutter build linux --release
```

Output: `build/linux/x64/release/bundle/`

### Create AppImage

Install appimagetool:
```bash
wget https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
chmod +x appimagetool-x86_64.AppImage
```

Create AppDir structure:
```bash
mkdir -p AppDir/usr/bin
cp -r build/linux/x64/release/bundle/* AppDir/usr/bin/
cp linux/bpb-automation.desktop AppDir/
cp assets/icon.png AppDir/bpb-automation.png

./appimagetool-x86_64.AppImage AppDir bpb-automation.AppImage
```

### Create DEB Package

```bash
mkdir -p debian/DEBIAN
mkdir -p debian/usr/bin
mkdir -p debian/usr/share/applications

cp -r build/linux/x64/release/bundle/* debian/usr/bin/
cp linux/bpb-automation.desktop debian/usr/share/applications/

# Create control file
cat > debian/DEBIAN/control << EOF
Package: bpb-automation
Version: 1.0.0
Architecture: amd64
Maintainer: Your Name <your@email.com>
Description: BPB Panel Clean IP Auto-Updater
 Automatically scan and update clean Cloudflare IPs
EOF

dpkg-deb --build debian bpb-automation_1.0.0_amd64.deb
```

## Windows

### Prerequisites
- Visual Studio 2022 with C++ Desktop Development
- Windows 10 SDK

### Debug Build

```bash
flutter build windows --debug
```

### Release Build

```bash
flutter build windows --release
```

Output: `build/windows/runner/Release/`

### Create Installer (Inno Setup)

Install [Inno Setup](https://jrsoftware.org/isinfo.php)

Create `installer.iss`:
```inno
[Setup]
AppName=BPB Clean IP Updater
AppVersion=1.0.0
DefaultDirName={pf}\BPB Clean IP Updater
DefaultGroupName=BPB Clean IP Updater
OutputDir=build
OutputBaseFilename=bpb-automation-setup
Compression=lzma2
SolidCompression=yes

[Files]
Source: "build\windows\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\BPB Clean IP Updater"; Filename: "{app}\bpb_automation.exe"
Name: "{commondesktop}\BPB Clean IP Updater"; Filename: "{app}\bpb_automation.exe"

[Run]
Filename: "{app}\bpb_automation.exe"; Description: "Launch BPB Clean IP Updater"; Flags: nowait postinstall skipifsilent
```

Compile:
```bash
iscc installer.iss
```

### Portable ZIP

```bash
cd build/windows/runner/Release
zip -r ../../../../bpb-automation-windows.zip .
```

## Web

### Build for Web

```bash
flutter build web --release
```

Output: `build/web/`

### Deployment Options

#### 1. Static Hosting (Cloudflare Pages)

```bash
# Deploy to Cloudflare Pages
cd build/web
# Upload to Cloudflare Pages via dashboard or CLI
```

#### 2. VPS Deployment

```bash
# Copy to VPS
scp -r build/web/* user@vps:/var/www/bpb-updater/

# Nginx config
server {
    listen 80;
    server_name yourdomain.com;
    root /var/www/bpb-updater;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

#### 3. Docker Container

Create `Dockerfile`:
```dockerfile
FROM nginx:alpine
COPY build/web /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

Build and run:
```bash
docker build -t bpb-updater-web .
docker run -d -p 80:80 bpb-updater-web
```

### Web Limitations

The web version CANNOT execute binaries. For web deployment:

1. **Backend Service Required**: Create a backend API that:
   - Runs the scanner binary
   - Exposes REST endpoints
   - Handles Cloudflare API calls

2. **Alternative**: Use web as UI only, require users to run desktop/mobile app

## Size Optimization

### Reduce APK Size

```bash
# Enable R8 (already default)
# In android/app/build.gradle:
buildTypes {
    release {
        shrinkResources true
        minifyEnabled true
    }
}

# Build with size analysis
flutter build apk --analyze-size
```

### Reduce iOS Size

```bash
# Strip symbols
flutter build ios --release --split-debug-info=build/debug-info --obfuscate
```

### Reduce Desktop Size

```bash
# Use release mode
flutter build <platform> --release

# Strip symbols (Linux/macOS)
strip build/linux/x64/release/bundle/bpb_automation
```

## Continuous Deployment (Future)

### GitHub Actions Example

```yaml
name: Build and Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v3
        with:
          name: android-apk
          path: build/app/outputs/flutter-apk/app-release.apk

  build-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter build macos --release
      # ... upload steps

  # Similar jobs for other platforms
```

## Release Checklist

- [ ] Version bumped in pubspec.yaml
- [ ] CHANGELOG.md updated
- [ ] All tests passing
- [ ] Builds succeed on all platforms
- [ ] Tested on physical devices/VMs
- [ ] Release notes prepared
- [ ] Distribution files created
- [ ] Documentation updated
- [ ] Git tag created: `git tag v1.0.0`
- [ ] Tagged commit pushed: `git push origin v1.0.0`

## Distribution Channels

### Recommended Distribution

1. **GitHub Releases**: Upload all platform builds
2. **Direct Download**: Host on your own server
3. **Telegram Channel**: Share update notifications
4. **Documentation Site**: Link to downloads

### File Naming Convention

```
bpb-automation-v1.0.0-android.apk
bpb-automation-v1.0.0-windows.exe
bpb-automation-v1.0.0-macos.dmg
bpb-automation-v1.0.0-linux.AppImage
bpb-automation-v1.0.0-linux.deb
```

## Update Mechanism (Future)

Consider implementing:
- In-app update checker
- Download new versions
- Auto-update (desktop platforms)
- Update notifications

## Support

After release:
- Monitor GitHub issues
- Collect crash reports
- User feedback channels
- Version compatibility matrix
