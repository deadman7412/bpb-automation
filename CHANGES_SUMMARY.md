# BPB Automation - Critical Bug Fixes Summary

**Date**: 2026-02-17

## Overview

Fixed critical bugs causing poor-quality IP results and UI configuration not being applied to the scanner.

## Critical Bug Fixes

### 1. EWMA Alpha Value Bug (CRITICAL - Root Cause of Poor Results)

**Problem**: Scanner was using wrong EWMA alpha value (0.2 instead of 0.064516129), causing it to overestimate IPs with inconsistent/bursty performance. This led to "bullshit" IPs that looked good in tests but performed poorly in real-world VPN usage.

**Files Changed**:
- `lib/utils/ewma.dart`: Changed default alpha from 0.2 → 0.064516129
- `lib/services/speed_tester.dart`: Use default EWMA() without explicit alpha

**Impact**: This is the most important fix. The slower decay rate (0.0645) now requires sustained speed over the full 10-second test, properly filtering out unreliable IPs just like the Go scanner does.

**Mathematical Background**:
- Go scanner uses: `DECAY = 2/(30+1) = 0.064516129`
- Old (wrong): alpha=0.2 → reacts quickly to bursts → overestimates inconsistent IPs
- New (correct): alpha=0.0645 → requires sustained performance → identifies truly reliable IPs

### 2. Default Filter Values

**Problem**: Default filters were too strict (maxLatency=200ms, maxLossRate=0.1, minSpeed=5.0 MB/s), different from Go scanner defaults.

**Files Changed**:
- `lib/models/scanner_config.dart`: Updated defaults and presets

**Changes**:
```dart
// OLD defaults:
maxLatency: 200ms
maxLossRate: 0.1 (10%)
minDownloadSpeed: 5.0 MB/s

// NEW defaults (match Go scanner):
maxLatency: 9999ms (no filter)
maxLossRate: 1.0 (100%, no filter)
minDownloadSpeed: 0.0 MB/s (no filter)
```

**Also Updated**:
- Validation range for maxLatency: 50-500 → 50-9999
- All preset configs (mobile/desktop/fast/balanced/quality)

### 3. testAllIPs Feature - Backend

**Problem**: Backend supported testAllIPs but it wasn't exposed in the UI.

**Files Changed**:
- `lib/models/scanner_config.dart`: Added `testAllIPs` boolean field (default: false)
- `lib/services/dart_scanner_service.dart`: Wired testAllIPs to IPLoader (line 120-123)

**Behavior**:
- `testAllIPs=false` (default): Tests ~696 IPs (1 random per /24 subnet) - FAST (~30 sec)
- `testAllIPs=true`: Tests ~5956 IPs (ALL 256 per /24 subnet) - SLOW (~4 min)

**Rationale**: Default is statistically valid due to Cloudflare Anycast - all IPs in same /24 route to same server.

### 4. testAllIPs Feature - UI Integration

**Problem**: Added testAllIPs to backend but forgot to wire it up in the UI config screen.

**Files Changed**:
- `lib/screens/config_screen.dart`: Added testAllIPs parameter to all ScannerConfig constructors (14 places)
- `lib/screens/config_screen.dart`: Added testAllIPs to equality check in `_configsEqual()`
- `lib/screens/config_screen.dart`: Added new SwitchListTile widget in Advanced Settings

**UI Changes**:
- New toggle: "Test All IPs" in Advanced Settings section
- Subtitle explains: "Test all ~5956 IPs (slower, ~4 min) vs default ~696 IPs (faster, ~30 sec). Default tests 1 random IP per /24 subnet, which is statistically valid due to Cloudflare Anycast."

## Verification Status

### ✅ COMPLETED
- [x] EWMA alpha value fixed in lib/utils/ewma.dart
- [x] EWMA usage fixed in lib/services/speed_tester.dart  
- [x] Default filter values updated in scanner_config.dart
- [x] Preset configs updated (mobile/desktop/fast/balanced/quality)
- [x] Validation ranges updated (maxLatency: 50-9999)
- [x] testAllIPs field added to ScannerConfig model
- [x] testAllIPs wired to IPLoader in dart_scanner_service.dart
- [x] testAllIPs added to all ScannerConfig constructors in config_screen.dart (14 places)
- [x] testAllIPs added to equality check
- [x] Test All IPs UI toggle added to Advanced Settings
- [x] Code compiles without errors (`flutter analyze` passes)
- [x] macOS debug build successful

### ⏳ NEEDS TESTING
- [ ] **CRITICAL**: Run scanner and verify IPs now perform well in actual VPN usage (EWMA fix validation)
- [ ] Verify "Target Clean IPs" setting from UI is respected during scan
- [ ] Verify "Test All IPs" toggle actually tests 696 vs 5956 IPs
- [ ] Test preset selection properly updates all fields including testAllIPs
- [ ] Compare side-by-side results with Go scanner on same network
- [ ] Verify storage/loading of all config parameters works correctly

## Testing Instructions

### Test 1: EWMA Fix Validation (CRITICAL)
1. Run a scan with default settings (should take ~30 sec with 696 IPs)
2. Export results to CSV
3. Use the top IPs in a real VPN config (e.g., V2Ray, WireGuard)
4. **Expected**: IPs should now perform well with consistent speed/latency
5. **Compare**: Results should match quality of Go scanner's output

### Test 2: UI Config Application
1. Open Configuration screen
2. Change "Target Clean IPs" to 10 (note: default is 5)
3. Save configuration
4. Return to home screen and start scan
5. Watch logs - should say "Goal: Find 10 clean IPs"
6. **Expected**: Scanner stops after finding 10 IPs, not 5

### Test 3: Test All IPs Toggle
1. Open Configuration → Advanced Settings
2. Enable "Test All IPs" toggle
3. Save configuration
4. Start scan
5. Watch logs - should say "CIDR samples: ALL (testAllIPs=true)"
6. **Expected**: Scan takes ~4 minutes and tests 5956 IPs
7. Disable toggle, start new scan
8. Watch logs - should say "CIDR samples: 1 per range"  
9. **Expected**: Scan takes ~30 seconds and tests 696 IPs

### Test 4: Preset Selection
1. Open Configuration
2. Select "Mobile" preset
3. Verify all fields update (threads, latency, etc.)
4. Save configuration
5. Close and reopen app
6. **Expected**: Config persists correctly

## Algorithm Verification (Already Confirmed Correct)

The 5-phase scanning algorithm matches Go scanner exactly:

1. ✅ Load IPs (1 per /24 subnet by default, ALL with testAllIPs flag)
2. ✅ Test ALL IPs concurrently for latency
3. ✅ Sort by [loss rate ASC, latency ASC]
4. ✅ Test downloads serially with early exit when target reached
5. ✅ Sort final results by [download speed DESC]

**Verified Files**:
- `lib/services/ip_loader.dart` - /24 sampling logic
- `lib/services/latency_tester.dart` - TCP latency testing
- `lib/services/speed_tester.dart` - Download testing with EWMA
- `lib/services/dart_scanner_service.dart` - Phase orchestration and sorting

## Next Steps

1. **IMMEDIATE**: Test EWMA fix by running scanner and using IPs in real VPN
2. **HIGH**: Verify UI config values are applied during scan (especially targetCleanIPs)
3. **MEDIUM**: Test testAllIPs toggle (696 vs 5956 IPs)
4. **FUTURE**: Consider refactoring config_screen.dart to use `.copyWith()` instead of full constructors

## Files Modified

### Core Algorithm Fixes
- `lib/utils/ewma.dart` - EWMA alpha value
- `lib/services/speed_tester.dart` - EWMA usage
- `lib/models/scanner_config.dart` - Default values, validation, testAllIPs field

### Backend Integration
- `lib/services/dart_scanner_service.dart` - testAllIPs integration

### UI Changes
- `lib/screens/config_screen.dart` - testAllIPs parameter propagation and UI toggle

## References

- Go Scanner: https://github.com/bia-pain-bache/Cloudflare-Clean-IP-Scanner
- EWMA Library: https://github.com/VividCortex/ewma (DECAY = 0.064516129)
- Go Scanner Algorithm: main.go, task/tcping.go, task/download.go, task/ip.go, utils/csv.go
