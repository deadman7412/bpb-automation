# Development Guide

## Prerequisites

### Required Tools
- Flutter SDK (latest stable channel)
- Dart SDK (bundled with Flutter)
- Git

### Platform-Specific Requirements

#### Android
- Android Studio
- Android SDK (API 21+)
- Android NDK (for native code)
- Java JDK 11+

#### iOS/macOS
- Xcode (latest)
- CocoaPods
- macOS (required for iOS/macOS builds)

#### Linux
- Required packages:
  ```bash
  sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev
  ```

#### Windows
- Visual Studio 2022 (with C++ Desktop Development)
- Windows 10 SDK

## Project Setup

### 1. Clone Repository
```bash
cd /path/to/your/projects
git clone <repository-url> bpb-automation
cd bpb-automation
```

### 2. Install Flutter Dependencies
```bash
flutter pub get
```

### 3. Download Scanner Binaries

Download from [GitHub Releases](https://github.com/bia-pain-bache/Cloudflare-Clean-IP-Scanner/releases/tag/v2.2.5):

```bash
mkdir -p assets/binaries

# Android
wget https://github.com/bia-pain-bache/Cloudflare-Clean-IP-Scanner/releases/download/v2.2.5/CloudflareScanner_android-arm64.zip
unzip CloudflareScanner_android-arm64.zip -d assets/binaries/android-arm64/

# macOS Intel
wget https://github.com/bia-pain-bache/Cloudflare-Clean-IP-Scanner/releases/download/v2.2.5/CloudflareScanner_darwin-amd64.zip
unzip CloudflareScanner_darwin-amd64.zip -d assets/binaries/darwin-amd64/

# macOS Apple Silicon
wget https://github.com/bia-pain-bache/Cloudflare-Clean-IP-Scanner/releases/download/v2.2.5/CloudflareScanner_darwin-arm64.zip
unzip CloudflareScanner_darwin-arm64.zip -d assets/binaries/darwin-arm64/

# Linux
wget https://github.com/bia-pain-bache/Cloudflare-Clean-IP-Scanner/releases/download/v2.2.5/CloudflareScanner_linux-amd64.zip
unzip CloudflareScanner_linux-amd64.zip -d assets/binaries/linux-amd64/

# Windows
wget https://github.com/bia-pain-bache/Cloudflare-Clean-IP-Scanner/releases/download/v2.2.5/CloudflareScanner_windows-amd64.zip
unzip CloudflareScanner_windows-amd64.zip -d assets/binaries/windows-amd64/
```

### 4. Verify Project Structure
```bash
tree -L 3
```

Expected structure:
```
bpb-automation/
├── CLAUDE.md
├── README.md
├── docs/
├── lib/
├── assets/
│   └── binaries/
│       ├── android-arm64/
│       ├── darwin-amd64/
│       ├── darwin-arm64/
│       ├── linux-amd64/
│       └── windows-amd64/
├── test/
└── pubspec.yaml
```

## Development Workflow

### Running on Different Platforms

#### Android (Emulator)
```bash
flutter emulators --launch <emulator-id>
flutter run
```

#### Android (Physical Device)
```bash
# Enable USB debugging on device
# Connect via USB
flutter devices
flutter run -d <device-id>
```

#### iOS Simulator
```bash
open -a Simulator
flutter run
```

#### macOS
```bash
flutter run -d macos
```

#### Linux
```bash
flutter run -d linux
```

#### Windows
```bash
flutter run -d windows
```

#### Web
```bash
flutter run -d chrome
```

### Hot Reload
- Press `r` in terminal to hot reload
- Press `R` to hot restart
- Press `q` to quit

### Debugging

#### VS Code
1. Install Flutter extension
2. Open project
3. Press F5 or Run -> Start Debugging

#### Android Studio
1. Open project
2. Select device
3. Click Run (Shift+F10)

#### Chrome DevTools
```bash
flutter run --observatory-port=9200
# Then open DevTools in browser
```

## Code Style and Standards

### Dart Style Guide
Follow [Effective Dart](https://dart.dev/guides/language/effective-dart)

### Formatting
```bash
# Format all files
dart format .

# Check formatting
dart format --set-exit-if-changed .
```

### Linting
```bash
# Run analyzer
flutter analyze

# Fix auto-fixable issues
dart fix --apply
```

### Critical Rules

#### NO EMOJIS
```dart
// WRONG
print("Scan complete!");
String message = "Success";

// CORRECT
print("[OK] Scan complete");
String message = "[OK] Success";
```

#### Tagged Logging
```dart
// WRONG
print("Scanning...");
debugPrint("Error occurred");

// CORRECT
log("[INFO] Scanning...");
log("[ERROR] Error occurred: ${e.toString()}");
```

#### No Dev Environment References

Do not reference the development machine, local paths, or developer identity anywhere in code, comments, or docs. Use generic placeholders when a path or name is needed in examples.

## Testing

### Unit Tests
```bash
flutter test

# With coverage
flutter test --coverage
```

### Widget Tests
```bash
flutter test test/widget_test.dart
```

### Integration Tests
```bash
flutter test integration_test/
```

### Test Structure
```
test/
├── models/
│   ├── clean_ip_test.dart
│   └── proxy_settings_test.dart
├── services/
│   ├── scanner_service_test.dart
│   ├── cloudflare_api_service_test.dart
│   └── storage_service_test.dart
└── widgets/
    └── scan_button_test.dart
```

## Build Process

### Debug Builds

```bash
# Android
flutter build apk --debug

# iOS
flutter build ios --debug

# Desktop
flutter build macos --debug
flutter build linux --debug
flutter build windows --debug
```

### Release Builds

See [deployment.md](deployment.md) for detailed instructions.

## Dependencies

### Core Dependencies
```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.1.0                    # HTTP client
  path_provider: ^2.1.1           # File paths
  flutter_secure_storage: ^9.0.0  # Credential storage
  shared_preferences: ^2.2.2      # App preferences
  csv: ^5.1.1                     # CSV parsing
  intl: ^0.18.1                   # Date formatting
```

### Dev Dependencies
```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
  build_runner: ^2.4.6
  json_serializable: ^6.7.1
```

## Project Structure Details

### lib/main.dart
Entry point, app initialization

### lib/models/
Data models with JSON serialization
- `clean_ip.dart`
- `proxy_settings.dart`
- `scanner_config.dart`
- `credentials.dart`

### lib/services/
Business logic layer
- `scanner_service.dart` - Binary execution
- `cloudflare_api_service.dart` - API calls
- `storage_service.dart` - Local storage
- `log_service.dart` - Logging

### lib/screens/
UI screens
- `home_screen.dart` - Main screen
- `settings_screen.dart` - Configuration
- `results_screen.dart` - Scan results
- `logs_screen.dart` - Log viewer
- `advanced_config_screen.dart` - Advanced settings

### lib/widgets/
Reusable UI components
- `scan_button.dart`
- `ip_list_tile.dart`
- `log_entry.dart`
- `credential_form.dart`

## Common Development Tasks

### Adding a New Screen
1. Create file in `lib/screens/`
2. Extend StatefulWidget or StatelessWidget
3. Add route in main.dart
4. Navigate using `Navigator.push()`

### Adding a New Model
1. Create file in `lib/models/`
2. Define class with fields
3. Add `fromJson()` and `toJson()` methods
4. Generate code: `flutter pub run build_runner build`

### Adding a New Service
1. Create file in `lib/services/`
2. Define class with methods
3. Use dependency injection or singleton pattern
4. Write tests in `test/services/`

### Updating Dependencies
```bash
flutter pub upgrade
flutter pub outdated
```

## Debugging Tips

### Common Issues

#### Binary Not Found
```dart
// Check binary extraction
final appDir = await getApplicationDocumentsDirectory();
final binaryPath = '${appDir.path}/CloudflareScanner';
print('[INFO] Binary path: $binaryPath');
print('[INFO] Exists: ${File(binaryPath).existsSync()}');
```

#### Permission Denied (Unix)
```bash
# Set execute permission
chmod +x assets/binaries/*/CloudflareScanner
```

#### API Call Failing
```dart
// Enable detailed logging
final response = await http.get(url, headers: headers);
print('[INFO] Status: ${response.statusCode}');
print('[INFO] Body: ${response.body}');
```

### Performance Profiling
```bash
flutter run --profile
# Press 'P' to show performance overlay
```

### Memory Leaks
```bash
flutter run --profile
# Use DevTools to inspect memory
```

## Version Control

### Git Workflow
```bash
# Create feature branch
git checkout -b feature/scanner-improvements

# Make changes
git add .
git commit -m "[FEAT] Improve scanner performance"

# Push
git push origin feature/scanner-improvements

# Create PR
```

### Commit Message Format
```
[TYPE] Brief description

Detailed description if needed

Types:
- [FEAT] New feature
- [FIX] Bug fix
- [REFACTOR] Code refactoring
- [DOCS] Documentation
- [TEST] Tests
- [STYLE] Code style
- [PERF] Performance improvement
```

### Gitignore
Ensure these are ignored:
```
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
build/
*.log
*.iml
.idea/
.vscode/
*.apk
*.ipa
*.exe
```

## Continuous Integration (Future)

### GitHub Actions (Planned)
```yaml
name: Build and Test
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter test
      - run: flutter analyze
```

## Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Dart Language Tour](https://dart.dev/guides/language/language-tour)
- [Flutter Cookbook](https://docs.flutter.dev/cookbook)
- [API Reference](https://api.flutter.dev/)
- [Package Repository](https://pub.dev/)

## Getting Help

- Check [docs/](../) for documentation
- Review [GitHub Issues](https://github.com/bia-pain-bache/Cloudflare-Clean-IP-Scanner/issues)
- Flutter Community: [discord.gg/flutter](https://discord.gg/flutter)
