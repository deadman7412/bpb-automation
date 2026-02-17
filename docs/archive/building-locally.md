# Building BPB Automation Locally

Complete guide for building BPB Automation on all supported platforms.

## Prerequisites

### All Platforms
- **Flutter SDK** 3.38.5 or later ([Install Flutter](https://flutter.dev/docs/get-started/install))
- **Git** for cloning the repository
- **Code editor** (VS Code, Android Studio, or IntelliJ IDEA)

### Platform-Specific Requirements

#### Android
- **Android Studio** or Android SDK CLI tools
- **Java JDK** 17 or later
- **Android SDK** (API level 21+)
- **Android NDK** (for native code)

#### macOS/iOS
- **macOS** computer (required for macOS/iOS builds)
- **Xcode** 15.0 or later
- **CocoaPods** (`sudo gem install cocoapods`)
- **Developer account** (for code signing)

#### Linux
- **Linux** distribution (Ubuntu 20.04+ recommended)
- **Build tools**:
  ```bash
  sudo apt-get update
  sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev
  ```

#### Windows
- **Windows 10/11**
- **Visual Studio 2022** or Visual Studio Build Tools
  - Desktop development with C++ workload
  - Windows 10 SDK

---

## Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/your-username/bpb-automation.git
cd bpb-automation
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Verify Setup
```bash
flutter doctor -v
```

Fix any issues reported by `flutter doctor` before proceeding.

---

## Building for Different Platforms

### Android

#### Debug Build (APK)
```bash
flutter build apk --debug
```
Output: `build/app/outputs/flutter-apk/app-debug.apk`

#### Release Build (APK)
```bash
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`

#### Release Build (App Bundle - for Play Store)
```bash
flutter build appbundle --release
```
Output: `build/app/outputs/bundle/release/app-release.aab`

#### Signed Release (requires keystore)
1. Create `android/key.properties`:
   ```properties
   storePassword=<your-store-password>
   keyPassword=<your-key-password>
   keyAlias=<your-key-alias>
   storeFile=<path-to-keystore>
   ```

2. Build signed APK:
   ```bash
   flutter build apk --release
   ```

#### Install on Device
```bash
# Debug build
flutter install

# Or manually install APK
adb install build/app/outputs/flutter-apk/app-release.apk
```

---

### macOS

#### Enable macOS Support
```bash
flutter config --enable-macos-desktop
```

#### Debug Build
```bash
flutter build macos --debug
```
Output: `build/macos/Build/Products/Debug/bpb_automation.app`

#### Release Build
```bash
flutter build macos --release
```
Output: `build/macos/Build/Products/Release/bpb_automation.app`

#### Create DMG Installer
```bash
# Install create-dmg
brew install create-dmg

# Create DMG
create-dmg \
  --volname "BPB Automation" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --app-drop-link 600 185 \
  "BPB-Automation.dmg" \
  "build/macos/Build/Products/Release/bpb_automation.app"
```

#### Code Signing (for distribution)
```bash
# Sign the app
codesign --deep --force --verify --verbose --sign "Developer ID Application: YOUR NAME" \
  "build/macos/Build/Products/Release/bpb_automation.app"

# Verify signature
codesign --verify --deep --strict --verbose=2 \
  "build/macos/Build/Products/Release/bpb_automation.app"
```

#### Run Locally
```bash
flutter run -d macos
```

---

### Linux

#### Enable Linux Support
```bash
flutter config --enable-linux-desktop
```

#### Install Dependencies
```bash
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev
```

#### Debug Build
```bash
flutter build linux --debug
```
Output: `build/linux/x64/debug/bundle/`

#### Release Build
```bash
flutter build linux --release
```
Output: `build/linux/x64/release/bundle/`

#### Create Portable Package
```bash
cd build/linux/x64/release/bundle
tar -czf ../../../../BPB-Automation-Linux-x64.tar.gz *
```

#### Create AppImage (optional)
Requires `appimagetool`. See [AppImage documentation](https://appimage.org/) for details.

#### Run Locally
```bash
flutter run -d linux
```

---

### Windows

#### Enable Windows Support
```bash
flutter config --enable-windows-desktop
```

#### Debug Build
```bash
flutter build windows --debug
```
Output: `build\windows\x64\runner\Debug\`

#### Release Build
```bash
flutter build windows --release
```
Output: `build\windows\x64\runner\Release\`

#### Create ZIP Package
```powershell
cd build\windows\x64\runner\Release
Compress-Archive -Path * -DestinationPath ..\..\..\..\..\BPB-Automation-Windows-x64.zip
```

#### Create MSI Installer (optional)
Use [WiX Toolset](https://wixtoolset.org/) or [Inno Setup](https://jrsoftware.org/isinfo.php).

#### Run Locally
```bash
flutter run -d windows
```

---

### Web

#### Enable Web Support
```bash
flutter config --enable-web
```

#### Debug Build
```bash
flutter build web --debug
```

#### Release Build
```bash
flutter build web --release
```
Output: `build/web/`

#### Test Locally
```bash
flutter run -d chrome
# or
flutter run -d web-server
```

#### Deploy to Web Server
Upload the contents of `build/web/` to any static web hosting:
- Cloudflare Pages
- GitHub Pages
- Netlify
- Vercel
- Your own web server

---

## Development Workflow

### Run in Debug Mode
```bash
# List available devices
flutter devices

# Run on specific device
flutter run -d <device-id>

# Run with hot reload enabled (default)
flutter run

# Run in release mode
flutter run --release
```

### Hot Reload
When running in debug mode, press `r` to hot reload or `R` to hot restart.

### Run Tests
```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/services/scanner_service_test.dart

# Run with coverage
flutter test --coverage
```

### Analyze Code
```bash
# Run static analysis
flutter analyze

# Format code
flutter format .

# Fix common issues
dart fix --apply
```

### Clean Build
```bash
# Clean build artifacts
flutter clean

# Get dependencies again
flutter pub get

# Rebuild
flutter build <platform>
```

---

## Build Configurations

### Debug vs Release

**Debug Build:**
- Includes debugging symbols
- Larger file size
- Slower performance
- Hot reload enabled
- DevTools support

**Release Build:**
- Optimized for performance
- Smaller file size
- No debugging symbols
- Production-ready

### Environment Variables

Create `.env` file (never commit this):
```env
# Optional: Custom configuration
API_BASE_URL=https://api.cloudflare.com
LOG_LEVEL=info
```

---

## Troubleshooting

### Common Issues

#### "Flutter SDK not found"
```bash
# Add Flutter to PATH (Linux/macOS)
export PATH="$PATH:/path/to/flutter/bin"

# Verify
flutter doctor
```

#### "Android licenses not accepted"
```bash
flutter doctor --android-licenses
```

#### "CocoaPods not installed" (macOS)
```bash
sudo gem install cocoapods
pod setup
```

#### "GTK libraries not found" (Linux)
```bash
sudo apt-get install -y libgtk-3-dev
```

#### Build fails on Windows
- Ensure Visual Studio 2022 with C++ workload is installed
- Run build from "Developer Command Prompt for VS 2022"

#### "Gradle build failed" (Android)
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
flutter build apk
```

### Performance Issues

If builds are slow:
```bash
# Enable build caching
flutter config --enable-gradle-daemon

# Use multiple cores (Gradle)
echo "org.gradle.parallel=true" >> android/gradle.properties
echo "org.gradle.workers.max=4" >> android/gradle.properties
```

---

## Build Size Optimization

### Reduce APK/AAB Size (Android)
```bash
# Enable code shrinking
flutter build apk --release --shrink

# Split per ABI
flutter build apk --release --split-per-abi
```

### Reduce App Size (iOS/macOS)
```bash
# Strip debug symbols
flutter build ios --release --split-debug-info=./symbols

# Obfuscate Dart code
flutter build ios --release --obfuscate --split-debug-info=./symbols
```

---

## CI/CD Integration

### GitHub Actions
The project includes automated builds via GitHub Actions (see `.github/workflows/build.yml`).

Builds run on:
- Push to `main` or `develop`
- Pull requests to `main`
- Git tags (`v*`)

### Manual Workflow Trigger
Go to Actions tab on GitHub → Select "Build Multi-Platform" → Run workflow

---

## Platform-Specific Notes

### Android
- **Minimum SDK**: API 21 (Android 5.0)
- **Target SDK**: API 36 (Android 14)
- **Build time**: ~5-10 minutes
- **Output size**: ~65 MB (release APK)

### macOS
- **Minimum OS**: macOS 10.14+
- **Architecture**: Universal binary (x86_64 + arm64)
- **Build time**: ~3-5 minutes
- **Output size**: ~80 MB (release app)

### Linux
- **Tested on**: Ubuntu 20.04, 22.04, Fedora 38
- **Architecture**: x86_64
- **Build time**: ~3-5 minutes
- **Output size**: ~120 MB (bundle)

### Windows
- **Minimum OS**: Windows 10 1809+
- **Architecture**: x64
- **Build time**: ~5-7 minutes
- **Output size**: ~100 MB (release)

---

## Getting Help

- **Flutter Issues**: [Flutter GitHub](https://github.com/flutter/flutter/issues)
- **Build Problems**: Check `flutter doctor -v` output
- **Project Issues**: [BPB Automation Issues](https://github.com/your-repo/issues)
- **Documentation**: [Flutter Build Documentation](https://docs.flutter.dev/deployment)

---

## Next Steps

After building:
1. Test the build on target platform
2. Verify all features work correctly
3. Check app size and performance
4. Prepare for distribution (see [deployment.md](deployment.md))
