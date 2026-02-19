# User Guide

Complete guide for using BPB Automation.

## What This App Does

BPB Automation helps you:
- Find Cloudflare IPs that actually work as a proxy on your network
- Automatically update your BPB Panel configuration with the best IPs
- Keep your proxy connection optimal without manual IP hunting

The app fetches your BPB Panel's Xray subscription configs and tests real proxy connectivity on your device, so results are specific to your ISP and location.

## Installation

### Android

1. Download `bpb-automation.apk`
2. Enable "Install from Unknown Sources" in Settings > Security
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
4. Launch (may need to allow in System Settings > Privacy & Security)

### Linux

```bash
# AppImage
chmod +x bpb-automation.AppImage
./bpb-automation.AppImage

# DEB Package
sudo dpkg -i bpb-automation_3.0.0_amd64.deb
```

### Windows

1. Download `bpb-automation-setup.exe` or zip
2. Run installer or extract zip
3. Launch from Start Menu or extracted folder

## First-Time Setup

### Step 1: Enter Your Subscription URL

1. Open app
2. Tap **Configuration**
3. Enter your BPB Panel subscription URL in the URL field
4. Tap **Fetch & Verify** to confirm it works
5. Adjust scan parameters if needed (defaults work well for most users)
6. Tap **Save**

Your URL should look like:
```
https://your-worker.workers.dev/sub/YOUR-UUID
```

### Step 2: Choose Update Method (Optional)

You only need credentials if you want the app to automatically update your BPB Panel. If you prefer to copy IPs manually, skip this step.

Available methods:
- **Panel API (default):** Panel base URL + panel password
- **Cloudflare API (fallback):** API token + account ID + KV namespace ID

Setup guides:
- [Panel Setup Guide](panel-setup.md)
- [Cloudflare Setup Guide](cloudflare-setup.md)

### Step 3: Enter Credentials (Optional)

1. Tap **Settings**
2. Select **Update Method**
3. Enter credentials for that method
4. Tap **Validate**
5. Tap **Save**

## Basic Usage

### Running a Scan

1. Open app — main screen shows your status and last scan time
2. Tap **Start Scan**
3. The scan runs in two phases:
   - **Phase 1 (TLS)**: Tests all candidate IPs for TLS connectivity (10–30 seconds)
   - **Phase 2 (Proxy)**: Tests the best Phase 1 IPs with a real Xray proxy connection (several minutes)
4. When complete, you are taken to the Results screen

**You can leave the app during a scan.** Tap **View Current Scan** from the home screen to return.

### Understanding Results

The Results screen shows:

```
Found 5 Working IPs
Scan completed in 342 seconds

Scan Statistics:
  Phase 1 Tested: 743
  Phase 1 Passed: 152
  Phase 2 Tested: 50
  Working IPs: 5
```

Each working IP shows its **proxy latency** — the round-trip time through the Xray proxy. Lower is faster. IPs are already sorted best-first.

A working IP means: a real Xray proxy connection was made through this IP from your device, and the proxy responded correctly (HTTP 204). The result is specific to your current network.

### Updating BPB Panel

After scan:
1. Review the working IP list on the Results screen
2. Tap **Update BPB Panel**
3. Wait for confirmation:
   ```
   Updated BPB Panel with 5 IPs
   ```

Your BPB Panel now uses the new IPs.

### Copying IPs Manually

If you do not have credentials configured, or prefer manual update:
1. On the Results screen, tap the copy icon next to any IP to copy it
2. Tap the copy icon in the "Working IPs" header to copy all IPs at once
3. Paste into your BPB Panel's clean IP field manually

### Downloading Configs

The Results screen also has a **Download Configs** button. This generates Xray config files with the working IPs substituted in, and shares them via the platform share sheet (or downloads them on web/desktop). Useful if you want to use the configs directly in an Xray client.

## Screens

### Home Screen

- **Start Scan** / **View Current Scan** — start a new scan or return to the in-progress one
- Status card — shows current state and time since last scan
- Quick actions grid — fast navigation to Configuration, Settings, Results, Logs, About, Debug

### Configuration Screen

Where you set your BPB Panel subscription URL and scan parameters. See [Scanner Configuration Guide](scanner-configuration.md) for parameter details.

### Settings Screen

Where you configure auto-update method and credentials:
- **Panel API (default):** panel base URL + panel password
- **Cloudflare API (fallback):** API token + account ID + KV namespace ID

Credentials are stored encrypted on your device (with secure-storage fallback when needed).

### Scan Progress Screen

Live view of the running scan:
- Phase 1 progress bar with IP counts
- Phase 2 progress with current IP being tested
- Cancel button

### Results Screen

Displayed after scan completes (or tap **Results** from the home screen to see the last result):
- Summary card with working IP count and scan duration
- Stat cards: Phase 1/Phase 2 counts
- Working IP list with proxy latency per IP
- Update BPB Panel button
- Download Configs button
- Info button (shows protocol, SNI, success rates, timestamp)

### Logs Screen

Full log history with all scan events. Use the copy button to export logs.

## Best Practices

### Always Scan on the Network You Will Use

The scanner tests IPs from your device on your current network. IPs that work on mobile data may not be optimal on home WiFi, and vice versa.

- Using mobile data: scan on mobile data
- Using home WiFi: scan on home WiFi
- Using a VPS: scan on the VPS

### How Often to Scan

- Heavy usage: Every 6–12 hours
- Normal usage: Every 1–2 days
- Light usage: Weekly or when connection becomes slow

### When to Re-scan

- After switching networks
- When the proxy feels slow
- After ISP maintenance

## Troubleshooting

### No Working IPs Found

**Phase 2 returns 0 working IPs:**
1. Verify your subscription URL in Configuration — tap Fetch & Verify
2. Check that Xray actually works on your network (test with a standalone client)
3. Increase Phase 2 Test Depth (default 50; try 100)
4. Try scanning at a different time

**Phase 1 returns 0 IPs:**
1. Check internet connection
2. Port 443 may be blocked — check with another app
3. Reduce Batch Size (try 100) if ISP throttles high-concurrency connections

### Update Fails

**"Failed to update BPB Panel":**
1. Check which **Update Method** is selected in Settings
2. If using **Panel API**:
   - Verify panel base URL and password
   - Re-run **Validate** in Settings
3. If using **Cloudflare API**:
   - Verify API token, account ID, and namespace ID
   - Verify token has Workers KV Edit permission
4. Check internet connection
5. View Logs for the specific error message

### Scan Takes Very Long

Phase 2 runs one Xray proxy test at a time. With Phase 2 Test Depth = 50 and slow IPs, this can take 10–20 minutes.

To speed it up:
- Reduce Phase 2 Test Depth (Configuration > Phase 2 Test Depth, try 20–30)
- Reduce Max Samples per CIDR (smaller Phase 1 pool = fewer Phase 1 winners to test)

### Subscription URL Errors

**"Failed to fetch subscription":**
1. Check the URL is complete and correct
2. Make sure your BPB Panel Worker is deployed and running
3. Try opening the URL in a browser (should return JSON)
4. Check internet connection

### App Crashes

1. Restart app
2. Check device storage (50 MB+ free needed for Xray temp files)
3. View Logs before crashing if possible
4. Report issue with log contents

## FAQ

### Q: Do I need credentials to use the app?

No. Credentials are only required for the "Update BPB Panel" feature.

For auto-update you can use either:
- Panel API credentials (default method), or
- Cloudflare API credentials (fallback method).

You can always scan and copy working IPs without credentials.

### Q: What does "working IP" mean exactly?

A working IP successfully routed an HTTP request through a real Xray proxy connection and received HTTP 204 back from Google's connectivity check endpoint. This means the IP actually functions as a proxy on your network, not just that port 443 is open.

### Q: Why are results different on mobile data vs WiFi?

Different networks route to different Cloudflare edge servers. An IP that works well from mobile data may be slow or blocked from home WiFi, and vice versa. Always scan on the network you intend to use.

### Q: Do I need a VPS?

No. The app runs on your device. On web deployment (VPS), scanning works with the Phase 1 TLS test (Phase 2 requires the Xray binary, which cannot run in a browser).

### Q: Why does the scan take so long?

Phase 2 starts one Xray process per IP and waits for it to connect. This is intentional — it tests actual proxy connectivity. With the default 50 IPs and a 10-second timeout each, the worst case is ~8 minutes. In practice it's usually faster because working IPs respond quickly.

### Q: Can I use the IPs without updating BPB Panel automatically?

Yes. After scanning, tap the copy button next to any IP or use "Copy All IPs" to copy all working IPs. Paste them into your BPB Panel's clean IP field manually.

### Q: Is it safe?

All data stays local on your device. The app only connects to your BPB Panel subscription URL, to Cloudflare's connectivity check endpoint (via the proxy being tested), and the selected update API (Panel API and/or Cloudflare API). No analytics, no third-party services.

### Q: Can I use multiple BPB Panels?

Not yet. One panel per app instance. Multi-account support is planned.

### Q: Why does enabling IPv6 not work?

Your network must have native IPv6 connectivity. If your ISP does not provide IPv6, all IPv6 IPs will fail Phase 1 (TLS). Check if your network has IPv6 before enabling this option.

### Q: How do I check what version I'm running?

Tap **About** from the home screen Quick Actions grid.

## Privacy & Security

### What Data is Stored Locally

- Panel API credentials (encrypted with platform keychain)
- Cloudflare API credentials (encrypted with platform keychain)
- BPB Panel subscription URL
- Scan parameters
- Last scan result (working IPs + stats)
- App logs

### What Network Requests are Made

- **BPB Panel subscription URL**: to fetch Xray configs (user-initiated, on scan start)
- **Panel API** (`/login/authenticate`, `/panel/settings`, `/panel/update-settings`): used in Panel API mode on "Update BPB Panel"
- **Cloudflare API**: to read/write Workers KV `proxySettings` in Cloudflare API mode on "Update BPB Panel"
- **Cloudflare IPs**: TLS handshakes during Phase 1 (scan only)
- **Google connectivity check** (`connectivitycheck.gstatic.com/generate_204`): via Xray proxy during Phase 2 (scan only)

No telemetry, no analytics, no third-party tracking.

### Credential Security

- Panel and Cloudflare credentials are stored using the platform's secure encrypted keychain
- Credentials are only sent to the selected update API endpoints
- Can be deleted anytime from Settings

## Getting Help

### In-App

- **Logs** screen: full log history, all errors are logged here
- **About** screen: version info

### Documentation

- [Panel Setup Guide](panel-setup.md) — how to configure Panel API credentials
- [Panel API Reference](panel-api-reference.md) — complete BPB panel endpoints and methods
- [Cloudflare Setup Guide](cloudflare-setup.md) — how to get Cloudflare API credentials
- [Scanner Configuration Guide](scanner-configuration.md) — scan parameter tuning

### Reporting Issues

When reporting a bug:
1. Check Logs screen for error messages
2. Include your device/OS and app version
3. Describe the steps to reproduce the issue
4. Paste any relevant log lines
