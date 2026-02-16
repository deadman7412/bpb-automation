# Download and Installation Guide

Complete guide for downloading and installing BPB Automation on all supported platforms.

## Quick Links

- [Android Installation](#android)
- [iOS Installation](#ios)
- [macOS Installation](#macos)
- [Linux Installation](#linux)
- [Windows Installation](#windows)

---

## Android

### System Requirements
- Android 5.0 (API 21) or later
- 50 MB free storage
- Internet connection

### Download
1. Go to [GitHub Releases](https://github.com/your-repo/bpb-automation/releases)
2. Download `bpb-automation-v1.0.0-android.apk`
3. File size: ~65 MB

### Installation

#### Method 1: Direct APK Install (Recommended)
1. Open the downloaded APK file
2. If prompted, enable "Install from Unknown Sources":
   - Android 8.0+: Settings > Apps > Special access > Install unknown apps
   - Android 7.0 and below: Settings > Security > Unknown sources
3. Tap "Install"
4. Wait for installation to complete
5. Tap "Open" to launch the app

#### Method 2: Using ADB (Advanced)
```bash
adb install bpb-automation-v1.0.0-android.apk
```

### First Launch
1. App will request storage permissions (needed for scanner binary)
2. Grant permissions when prompted
3. App is ready to use

### Updating
- Download new APK
- Install over existing version (settings preserved)

### Uninstallation
Settings > Apps > BPB Automation > Uninstall

---

## iOS

### System Requirements
- iOS 12.0 or later
- 50 MB free storage
- Internet connection

### Download

#### Method 1: TestFlight (Beta)
1. Install TestFlight from App Store
2. Open invitation link (provided separately)
3. Tap "Accept" and "Install"

#### Method 2: IPA Installation (Requires Developer Account)
1. Download `bpb-automation-v1.0.0-ios.ipa`
2. Use tool like AltStore, Sideloadly, or Xcode
3. Sign with your Apple Developer certificate
4. Install to device

### Installation via AltStore
1. Install AltStore on your computer
2. Connect iPhone/iPad
3. Drag IPA file to AltStore
4. Follow on-screen instructions

### First Launch
1. Trust the developer certificate:
   - Settings > General > Device Management
   - Tap on your certificate
   - Tap "Trust"
2. Launch app from home screen

### Updating
- TestFlight: Automatic updates
- IPA: Reinstall with new version

### Uninstallation
Long-press app icon > Remove App > Delete App

---

## macOS

### System Requirements
- macOS 10.15 (Catalina) or later
- 80 MB free storage
- Internet connection

### Download
1. Go to [GitHub Releases](https://github.com/your-repo/bpb-automation/releases)
2. Download `bpb-automation-v1.0.0-macos.dmg`
3. File size: ~79 MB

### Installation

#### Method 1: DMG (Recommended)
1. Open the downloaded DMG file
2. Drag "BPB Automation.app" to Applications folder
3. Eject the DMG

#### Method 2: ZIP
1. Download `bpb-automation-v1.0.0-macos.app.zip`
2. Extract the ZIP file
3. Move "BPB Automation.app" to Applications folder

### First Launch
1. Open Applications folder
2. Double-click "BPB Automation"
3. If blocked by Gatekeeper:
   - Right-click the app
   - Select "Open"
   - Click "Open" in the dialog

   Or use Terminal:
   ```bash
   xattr -cr "/Applications/BPB Automation.app"
   ```

4. App will launch successfully

### Granting Permissions
macOS may request permissions for:
- Network access (allow for scanning)
- Keychain access (allow for credential storage)

### Updating
- Download new version
- Replace old app in Applications folder

### Uninstallation
1. Move app to Trash from Applications folder
2. Empty Trash
3. (Optional) Remove preferences:
   ```bash
   rm -rf ~/Library/Preferences/com.bpb.bpb-automation.*
   rm -rf ~/Library/Application\ Support/com.bpb.bpb-automation
   ```

---

## Linux

### System Requirements
- Ubuntu 20.04 or later (or equivalent)
- GTK 3.0
- 80 MB free storage
- Internet connection

### Download
1. Go to [GitHub Releases](https://github.com/your-repo/bpb-automation/releases)
2. Choose your preferred format:
   - AppImage: `bpb-automation-v1.0.0-linux-x86_64.AppImage`
   - DEB: `bpb-automation_1.0.0_amd64.deb`

### Installation

#### Method 1: AppImage (Universal)
1. Download AppImage file
2. Make it executable:
   ```bash
   chmod +x bpb-automation-v1.0.0-linux-x86_64.AppImage
   ```
3. Run:
   ```bash
   ./bpb-automation-v1.0.0-linux-x86_64.AppImage
   ```

#### Method 2: DEB Package (Debian/Ubuntu)
```bash
sudo dpkg -i bpb-automation_1.0.0_amd64.deb
sudo apt-get install -f  # Install dependencies if needed
```

Launch from applications menu or terminal:
```bash
bpb-automation
```

#### Method 3: From Source
```bash
# Install Flutter
git clone https://github.com/your-repo/bpb-automation.git
cd bpb-automation
flutter pub get
flutter build linux --release
./build/linux/x64/release/bundle/bpb_automation
```

### Dependencies
If you encounter missing dependencies:

**Ubuntu/Debian:**
```bash
sudo apt-get install libgtk-3-0 libblkid1 liblzma5
```

**Fedora:**
```bash
sudo dnf install gtk3 libblkid xz-libs
```

**Arch:**
```bash
sudo pacman -S gtk3 util-linux xz
```

### Desktop Integration (AppImage)
```bash
# Make AppImage accessible
mkdir -p ~/.local/bin
mv bpb-automation-v1.0.0-linux-x86_64.AppImage ~/.local/bin/bpb-automation
chmod +x ~/.local/bin/bpb-automation

# Create desktop entry
cat > ~/.local/share/applications/bpb-automation.desktop <<EOF
[Desktop Entry]
Name=BPB Automation
Comment=Cloudflare IP Scanner for BPB Panel
Exec=$HOME/.local/bin/bpb-automation
Icon=bpb-automation
Terminal=false
Type=Application
Categories=Network;Utility;
EOF
```

### Updating
- AppImage: Download new version and replace old file
- DEB: Install new package (will upgrade automatically)

### Uninstallation
- AppImage: Delete the file
- DEB:
  ```bash
  sudo apt-get remove bpb-automation
  ```

---

## Windows

### System Requirements
- Windows 10 or later
- 80 MB free storage
- Internet connection
- Visual C++ Redistributables (usually pre-installed)

### Download
1. Go to [GitHub Releases](https://github.com/your-repo/bpb-automation/releases)
2. Download `bpb-automation-v1.0.0-windows-setup.exe`
3. File size: ~80 MB

### Installation

#### Method 1: Installer (Recommended)
1. Run `bpb-automation-v1.0.0-windows-setup.exe`
2. Click "Yes" if prompted by Windows SmartScreen:
   - Click "More info"
   - Click "Run anyway"
3. Follow installation wizard:
   - Choose installation directory
   - Select Start Menu folder
   - Choose whether to create desktop shortcut
4. Click "Install"
5. Launch app when installation completes

#### Method 2: Portable ZIP
1. Download `bpb-automation-v1.0.0-windows.zip`
2. Extract to desired location
3. Run `bpb_automation.exe`

### First Launch
1. Windows Defender may scan the app (this is normal)
2. If Windows SmartScreen blocks:
   - Click "More info"
   - Click "Run anyway"
3. App will launch successfully

### Permissions
App may request:
- Network access (allow for scanning)
- Firewall exception (allow for optimal performance)

### Updating
- Download new installer
- Run to upgrade (settings preserved)

### Uninstallation
- Installer version: Settings > Apps > BPB Automation > Uninstall
- Portable version: Delete folder

---

## Verifying Downloads

### Check SHA256 Checksums

#### macOS/Linux
```bash
shasum -a 256 bpb-automation-v1.0.0-*.{apk,dmg,AppImage,exe}
```

#### Windows (PowerShell)
```powershell
Get-FileHash bpb-automation-v1.0.0-windows-setup.exe -Algorithm SHA256
```

Compare output with checksums in release notes.

---

## Troubleshooting

### App Won't Install

**Android:**
- Enable "Install from Unknown Sources"
- Check storage space (need 100MB+)
- Try reinstalling

**iOS:**
- Check iOS version (12.0+ required)
- Trust developer certificate
- Try reinstalling via AltStore

**macOS:**
- Disable Gatekeeper temporarily
- Use terminal command to remove quarantine
- Check macOS version (10.15+ required)

**Linux:**
- Install missing dependencies
- Check file permissions (must be executable)
- Try different package format (AppImage vs DEB)

**Windows:**
- Disable Windows SmartScreen temporarily
- Install Visual C++ Redistributables
- Run installer as Administrator

### App Won't Launch

**All Platforms:**
1. Check system requirements
2. Verify download integrity (checksum)
3. Reinstall the app
4. Check logs (if app partially launches)
5. Report issue with system details

### Performance Issues

- Close other network-heavy applications
- Check internet connection
- Reduce scanner thread count in settings
- Try at different time of day

---

## Getting Help

- [User Guide](user-guide.md)
- [FAQ](user-guide.md#faq)
- [Troubleshooting](user-guide.md#troubleshooting)
- [GitHub Issues](https://github.com/your-repo/bpb-automation/issues)

---

## What's Next?

After installation:
1. Launch the app
2. (Optional) Configure Cloudflare credentials
3. Run your first scan
4. View results

See [User Guide](user-guide.md) for complete usage instructions.
