# User Guide

Complete guide for using BPB Automation.

## What This App Does

BPB Automation helps you:
- Find the fastest Cloudflare IPs for your network
- Automatically update your BPB Panel configuration
- Keep your proxy connection optimal
- Work from any device (mobile, desktop)

## Installation

### Android

1. Download `bpb-automation.apk`
2. Enable "Install from Unknown Sources" in Settings
3. Open APK file and install
4. Launch app

### iOS

1. Install via TestFlight (link provided separately)
2. Or install IPA with signing certificate
3. Launch app

### macOS

1. Download `.dmg` file
2. Open DMG
3. Drag app to Applications folder
4. Launch (may need to allow in Security & Privacy settings)

### Linux

**AppImage:**
```bash
chmod +x bpb-automation.AppImage
./bpb-automation.AppImage
```

**DEB Package:**
```bash
sudo dpkg -i bpb-automation_1.0.0_amd64.deb
```

### Windows

1. Download `bpb-automation-setup.exe`
2. Run installer
3. Follow installation wizard
4. Launch from Start Menu or Desktop shortcut

## First-Time Setup

### Quick Start (Scan Only)

**Want to just scan for clean IPs?** You can start immediately:

1. Open app
2. Tap "Start Scan"
3. Wait for scan to complete (3-5 minutes)
4. View and copy clean IP results

No credentials needed for scanning!

### Full Setup (Scan + Auto-Update)

**Want to automatically update BPB Panel?** You'll need Cloudflare credentials:

#### Step 1: Get Cloudflare Credentials

You need three pieces of information. See [Cloudflare Setup Guide](cloudflare-setup.md) for detailed instructions.

**Quick Summary:**

1. **Account ID**: Found in Cloudflare Dashboard under Account Details
2. **KV Namespace ID**: Found in Workers & Pages > KV section
3. **API Token**: Create at Profile > API Tokens with Workers KV Edit permission

#### Step 2: Enter Credentials in App

1. Open app
2. Go to Settings (gear icon)
3. Enter:
   - Cloudflare API Token
   - Account ID
   - KV Namespace ID
4. Tap "Save"
5. App will validate credentials

If validation succeeds, you'll see:
```
[OK] Credentials validated successfully
```

If validation fails:
```
[ERROR] Invalid credentials. Please check and try again.
```

## Basic Usage

### Running a Scan

1. Open app
2. Main screen shows "Start Scan" button
3. Tap "Start Scan"
4. Wait for scan to complete (3-5 minutes)
5. Review results
6. (Optional) Tap "Update BPB" to update your panel

**Note:** You can scan without credentials. Credentials are only required for the "Update BPB" feature.

### Understanding Results

After scan completes, you'll see:

```
[OK] Scan complete
[INFO] Found 10 clean IPs
[INFO] Top IP: 172.67.156.23 (Quality: 15.2, Latency: 85ms, Loss: 0%)
```

**IP List shows:**
- IP Address
- Quality Score (EWMA-based sustained throughput)
- Latency (ms)
- Loss Rate (%)

**What is Quality Score?**
- Measures sustained download performance, not peak speed
- Based on EWMA (Exponentially Weighted Moving Average)
- Higher is better (typical range: 5-20)
- More reliable than raw speed for BPB Panel connections
- Favors consistent throughput over brief bursts

**Indicators:**
- **Green**: Excellent (0% loss, low latency, high quality)
- **Yellow**: Good (some packet loss or higher latency)
- **Red**: Acceptable (works but not optimal)

**Sorting Priority:**
1. Loss rate (0% is best) - MOST IMPORTANT
2. Latency (lower is better)
3. Quality score (higher is better)

### Updating BPB Panel

After scan:
1. Review IP list
2. Tap "Update BPB Panel"
3. Wait for confirmation
4. See success message:
   ```
   [OK] BPB Panel updated successfully
   [INFO] 10 clean IPs saved
   ```

Your BPB Panel now uses the new clean IPs.

## Advanced Features

### Advanced Scanner Settings

Go to Settings > Advanced Configuration

**Threads**: How many IPs to test simultaneously
- Default: 200
- Mobile: 100-150
- Fast WiFi: 300-400

**Latency Limit**: Maximum acceptable latency
- Default: 200ms
- Fast connection: 150ms
- Slow connection: 300ms

**Download Test Count**: How many IPs to speed test
- Default: 10
- Quick scan: 5
- Thorough scan: 20

**Disable Download Test**: Skip speed testing
- Enable for quick scans (30 seconds)
- Results sorted by latency only

See [Scanner Configuration Guide](scanner-configuration.md) for details.

### Viewing Logs

1. Go to Settings > View Logs
2. See all scan history
3. Check for errors
4. Export logs (long press)

**Log Format:**
```
[2025-02-15 14:30:45] [INFO] Starting IP scan...
[2025-02-15 14:31:12] [OK] Scan completed
[2025-02-15 14:31:15] [INFO] Updating Cloudflare KV...
[2025-02-15 14:31:18] [OK] Update successful
```

### Scheduled Scans (Coming Soon)

Future feature:
- Auto-scan every 6/12/24 hours
- Background operation
- Notifications on update

## Best Practices

### When to Scan

**Important:** Always scan from the network you'll actually use!

- When connection is slow
- After changing networks (WiFi to mobile data)
- Once daily for heavy users
- Weekly for light users
- After ISP maintenance

**Why Network Matters:**
- Scanner selects IPs with best routing to YOUR network
- Different networks get different Cloudflare edge servers
- IPs are optimized per /24 subnet for routing diversity
- Mobile data IPs won't work optimally on WiFi and vice versa

### Where to Scan

Scan from the network you'll actually use:
- Mobile data: Scan on mobile data
- Home WiFi: Scan on home WiFi
- Work network: Scan on work network

Clean IPs differ by network, so scan where you'll use the proxy.

### How Often to Update

- Heavy usage: Daily
- Normal usage: 2-3 times per week
- Light usage: Weekly or as needed

### Optimal Scan Times

- Off-peak hours (2AM-6AM)
- When network is idle
- Not while streaming/downloading

## Troubleshooting

### Scan Fails

**Problem**: Scan doesn't complete or finds no IPs

**Solutions**:
1. Check internet connection
2. Try increasing latency limit to 300-500ms
3. Decrease quality score limit to 1-3
4. Enable "HTTP Mode" in Advanced Settings
5. Reduce threads to 100

**Understanding Quality Score Limits:**
- Default limit: 5
- If no IPs found, lower to 2-3
- Quality score measures sustained throughput
- Lower limits accept IPs with less consistent performance

### Update Fails

**Problem**: "Failed to update BPB Panel"

**Solutions**:
1. Verify Cloudflare credentials
2. Check internet connection
3. Ensure API token has Workers KV Edit permission
4. Check Workers KV namespace exists
5. View logs for detailed error

### Slow Scans

**Problem**: Scan takes 10+ minutes

**Solutions**:
1. Reduce Download Test Count to 5
2. Reduce Threads to 100
3. Enable "Disable Download Test"
4. Increase latency limit (fewer IPs to test)

### App Crashes

**Problem**: App closes unexpectedly

**Solutions**:
1. Restart app
2. Clear app cache (Settings > Storage)
3. Reinstall app
4. Check device storage (need 50MB+ free)
5. Report issue with logs

### Permission Denied (Android)

**Problem**: "Permission denied" error

**Solutions**:
1. Grant storage permission in Settings
2. Reinstall app
3. Check if device is rooted (may cause issues)

### Invalid Credentials

**Problem**: "Invalid API token"

**Solutions**:
1. Copy token again (ensure no extra spaces)
2. Check token hasn't expired
3. Verify token has correct permissions
4. Create new token if needed

See [Cloudflare Setup Guide](cloudflare-setup.md) for credential help.

## FAQ

### Q: Do I need Cloudflare credentials to use the app?
**A**: No, not for scanning. Credentials are only required if you want to automatically update your BPB Panel. You can scan and view clean IPs without any credentials.

### Q: What is "Quality Score" and how is it different from speed?
**A**: Quality Score is an EWMA-based metric that measures **sustained throughput quality**, not peak speed:
- Peak speed can be misleading (brief bursts don't represent real performance)
- Quality score emphasizes consistency (80% weight to historical average)
- Higher quality score = more reliable BPB Panel connection
- Roughly correlates with MB/s but filters out unreliable IPs

### Q: Why does the scanner select IPs from different subnets?
**A**: **Routing diversity improves BPB Panel performance:**
- Each /24 subnet connects through different Cloudflare edge servers
- Different edge servers have different routing paths to your ISP
- Result: More stable connections even if raw speed is similar
- This is why scanner IPs work better than random Cloudflare IPs

### Q: Do I need a VPS?
**A**: No. The app runs on your device.

### Q: Will it work on mobile data?
**A**: Yes, and you SHOULD scan on mobile data if that's what you'll use.

### Q: How much data does a scan use?
**A**: 10-50 MB per scan.

### Q: Does it work offline?
**A**: The app loads offline, but needs internet to scan and update.

### Q: Can I use the clean IPs manually?
**A**: Yes! After scanning, you can copy the IP list and manually add them to your BPB Panel configuration.

### Q: Is it safe?
**A**: Yes. All data stays local. Only connects to Cloudflare API.

### Q: Can I use multiple BPB Panels?
**A**: Currently one panel per app. Future: multi-account support.

### Q: How do I backup settings?
**A**: Settings > Export Settings (coming soon)

### Q: Can I use custom IP lists?
**A**: Not yet. Future feature.

### Q: Why are results different on VPS vs mobile?
**A**: Network routes differ. Always scan on the network you'll use.

### Q: How to uninstall?
**A**:
- Android: Settings > Apps > BPB Clean IP Updater > Uninstall
- iOS: Long press app icon > Remove App
- macOS: Drag to Trash from Applications
- Windows: Settings > Apps > Uninstall
- Linux: `sudo apt remove bpb-automation`

## Privacy & Security

### What Data is Stored

**Locally on Device:**
- Cloudflare credentials (encrypted)
- Scanner settings
- Scan history
- Logs

**Not Stored:**
- No cloud backups
- No analytics sent
- No tracking

### What Network Requests are Made

**Only to Cloudflare API:**
- Read current settings
- Write updated settings
- No third-party services
- No telemetry

### Credential Security

- Encrypted storage (platform keychain)
- Never sent anywhere except Cloudflare
- Can be deleted anytime

## Getting Help

### In-App Help
- Settings > Help
- Settings > View Logs
- Settings > About

### Documentation
- See `docs/` folder for detailed guides
- [Cloudflare Setup](cloudflare-setup.md)
- [Scanner Configuration](scanner-configuration.md)

### Reporting Issues
- Check logs first
- Include error messages
- Report device/OS version
- Describe steps to reproduce

## Updates

### Checking for Updates
- Settings > Check for Updates (coming soon)
- Follow release announcements

### Installing Updates
- Download new version
- Install over existing (settings preserved)
- Or uninstall and reinstall

## Tips & Tricks

1. **Quick Scan**: Enable "Disable Download Test" for 30-second scans
2. **Best Results**: Scan during off-peak hours
3. **Battery Saver**: Plug in device during scan
4. **Network Test**: Compare before/after scan speeds
5. **Multiple Networks**: Scan on each network you use

## Changelog

See release notes for version history and new features.

## License

To be determined.

## Credits

- Scanner: [Cloudflare-Clean-IP-Scanner](https://github.com/bia-pain-bache/Cloudflare-Clean-IP-Scanner)
- BPB Panel: [BPB-Worker-Panel](https://github.com/bia-pain-bache/BPB-Worker-Panel)
