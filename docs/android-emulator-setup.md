# Android Emulator Setup and Testing Guide

This guide explains how to set up Android emulators for testing the BPB Automation app.

## Prerequisites

- Android Studio installed
- Flutter SDK installed and configured
- Sufficient disk space (at least 10GB free)
- Virtualization enabled in BIOS/UEFI

## Setting Up Android Emulator

### Method 1: Using Android Studio (Recommended)

1. **Open Android Studio**
   - Launch Android Studio
   - If you don't have a project, select "More Actions" > "Virtual Device Manager"
   - Or from an open project: Tools > Device Manager

2. **Create a New Virtual Device**
   - Click the "+" button or "Create Device"
   - Select a device definition (recommended: Pixel 7, Pixel 6, or Pixel 5)
   - Click "Next"

3. **Select System Image**
   - Choose an API level (recommended: API 33 - Android 13.0)
   - If not downloaded, click "Download" next to the system image
   - Wait for the download to complete
   - Click "Next"

4. **Configure AVD Settings**
   - Name: "Pixel_7_API_33" (or similar)
   - Startup orientation: Portrait
   - Advanced Settings (optional):
     - RAM: 2048 MB (minimum), 4096 MB (recommended)
     - Internal Storage: 2048 MB
     - SD Card: 512 MB or more
   - Click "Finish"

5. **Launch Emulator**
   - In Device Manager, find your emulator
   - Click the "Play" triangle button to start
   - Wait for the emulator to boot (first boot takes longer)

### Method 2: Using Command Line

```bash
# List available system images
sdkmanager --list | grep system-images

# Download a system image (example: Android 13, x86_64)
sdkmanager "system-images;android-33;google_apis;x86_64"

# Create AVD
avdmanager create avd -n Pixel_7_API_33 \
  -k "system-images;android-33;google_apis;x86_64" \
  -d "pixel_7"

# Launch emulator
emulator -avd Pixel_7_API_33
```

## Running the App on Emulator

### Using Flutter Command Line

```bash
# List connected devices (including emulators)
flutter devices

# Run in debug mode
flutter run

# Run in release mode
flutter run --release

# Run on specific device
flutter run -d emulator-5554
```

### Using Android Studio

1. Open the project in Android Studio
2. Select the emulator from the device dropdown (top toolbar)
3. Click the "Run" button (green play icon)
4. Or press Shift+F10 (Windows/Linux) or Control+R (Mac)

### Using VS Code

1. Open Command Palette (Ctrl+Shift+P or Cmd+Shift+P)
2. Type "Flutter: Select Device"
3. Choose your emulator
4. Press F5 to start debugging

## Installing APK on Emulator

### Method 1: Drag and Drop
1. Start the emulator
2. Download the APK file
3. Drag the APK file and drop it onto the emulator window
4. Wait for installation to complete
5. Find the app in the app drawer

### Method 2: Using ADB

```bash
# Install APK
adb install path/to/BPB-Automation-Android-Universal.apk

# Reinstall (overwrite existing)
adb install -r path/to/BPB-Automation-Android-Universal.apk

# Uninstall app
adb uninstall com.example.bpb_automation
```

## Common Issues and Solutions

### 1. Network Connectivity Issues

**Problem**: App shows "Failed host lookup" or DNS errors

**Solutions**:

A. **Set DNS manually (Quick Fix)**
```bash
# Set Google DNS
adb shell "setprop net.dns1 8.8.8.8"
adb shell "setprop net.dns2 8.8.4.4"

# Or use Cloudflare DNS
adb shell "setprop net.dns1 1.1.1.1"
adb shell "setprop net.dns2 1.0.0.1"
```

B. **Restart emulator with DNS**
```bash
# Stop emulator
adb emu kill

# Start with custom DNS
emulator -avd Pixel_7_API_33 -dns-server 8.8.8.8
```

C. **Check emulator network settings**
- Open Settings on emulator
- Go to Network & Internet > Internet
- Ensure Wi-Fi is connected
- If not, toggle Wi-Fi off and on

D. **Use Cold Boot**
- In Device Manager, click dropdown next to emulator
- Select "Cold Boot Now"
- This resets network configuration

### 2. Emulator Won't Start

**Problem**: Emulator fails to launch or crashes

**Solutions**:

A. **Check virtualization**
```bash
# On Linux
egrep -c '(vmx|svm)' /proc/cpuinfo
# Should return > 0

# On macOS (Intel)
sysctl -a | grep machdep.cpu.features | grep VMX
```

B. **Wipe emulator data**
- Device Manager > Click dropdown > "Wipe Data"
- Confirm and restart

C. **Increase RAM allocation**
- Device Manager > Edit device
- Advanced Settings > Increase RAM to 4096 MB

D. **Use x86_64 image instead of ARM**
- ARM images are slower on x86 machines
- Delete and recreate with x86_64 system image

### 3. App Crashes on Launch

**Problem**: App opens then immediately closes

**Solutions**:

A. **Check logs**
```bash
# View all logs
adb logcat

# Filter by app
adb logcat | grep "bpb_automation"

# Clear and monitor
adb logcat -c && adb logcat
```

B. **Verify API level compatibility**
- Minimum SDK in build.gradle should match or be lower than emulator API level
- Check: android/app/build.gradle → minSdkVersion

C. **Clear app data**
```bash
adb shell pm clear com.example.bpb_automation
```

### 4. Slow Performance

**Problem**: Emulator runs very slowly

**Solutions**:

A. **Enable hardware acceleration**
- macOS: Automatically uses Hypervisor.framework
- Windows: Install Intel HAXM or use WHPX
- Linux: Install KVM

B. **Reduce graphics**
- Device Manager > Edit device
- Graphics: Change to "Software" or "Hardware"

C. **Use smaller device**
- Try Pixel 4 or Nexus 5X instead of Pixel 7

D. **Close unnecessary apps**
- Free up RAM on your host machine
- Close other emulators

### 5. Keyboard Not Working

**Problem**: Cannot type in emulator

**Solution**:
- Click inside emulator window
- Press Ctrl+K (Windows/Linux) or Cmd+K (Mac) to toggle virtual keyboard
- Or enable in emulator: Settings > System > Languages & input > Physical keyboard

### 6. Screen Rotation Issues

**Problem**: Screen doesn't rotate

**Solution**:
```bash
# Enable auto-rotate
adb shell content insert --uri content://settings/system \
  --bind name:s:accelerometer_rotation --bind value:i:1
```

## Testing Network Connectivity

Before testing the app, verify emulator has internet access:

```bash
# Test DNS resolution
adb shell "ping -c 3 google.com"

# Test HTTPS connectivity
adb shell "curl -I https://api.cloudflare.com"

# Check DNS settings
adb shell "getprop net.dns1"
adb shell "getprop net.dns2"
```

## Debugging Network Issues

### Enable verbose logging in app

1. Open the app
2. Go to Settings
3. Look for debug/logging options
4. Enable verbose logging
5. Check Logs screen for detailed network information

### Monitor network traffic

```bash
# Monitor all network activity
adb shell "tcpdump -i any -s 0 -w /sdcard/capture.pcap"

# Download capture file
adb pull /sdcard/capture.pcap
# Open in Wireshark for analysis
```

### Check if Cloudflare API is reachable

```bash
# From host machine
curl -I https://api.cloudflare.com

# From emulator
adb shell "curl -I https://api.cloudflare.com"
```

## Emulator Best Practices

1. **Use x86_64 images** for better performance on Intel/AMD processors
2. **Allocate sufficient RAM** (4GB recommended)
3. **Enable hardware acceleration** (KVM, HAXM, or Hypervisor.framework)
4. **Keep system images updated** through SDK Manager
5. **Use API 30+** for best compatibility with modern apps
6. **Close unused emulators** to free up resources
7. **Snapshot feature**: Save emulator state for faster subsequent launches
8. **Cold Boot occasionally** to reset any network/state issues

## Recommended Emulator Configurations

### Minimum Configuration
- Device: Pixel 4
- API Level: 30 (Android 11)
- RAM: 2048 MB
- System Image: x86_64

### Recommended Configuration
- Device: Pixel 6 or Pixel 7
- API Level: 33 (Android 13)
- RAM: 4096 MB
- System Image: x86_64 with Google APIs

### Testing Configuration (Multiple API Levels)
1. Pixel 5 - API 29 (Android 10) - Test older devices
2. Pixel 6 - API 33 (Android 13) - Current stable
3. Pixel 7 - API 34 (Android 14) - Latest

## Additional Resources

- [Android Emulator Documentation](https://developer.android.com/studio/run/emulator)
- [ADB Command Reference](https://developer.android.com/studio/command-line/adb)
- [Flutter Device Testing](https://flutter.dev/docs/testing)
- [Emulator Networking](https://developer.android.com/studio/run/emulator-networking)

## Getting Help

If you encounter issues not covered here:

1. Check the app logs (Logs screen in app)
2. Run `adb logcat` for detailed Android logs
3. Check [GitHub Issues](https://github.com/deadman7412/bpb-automation/issues)
4. Create a new issue with:
   - Emulator configuration (device, API level)
   - Steps to reproduce
   - Relevant log output
   - Screenshots if applicable
