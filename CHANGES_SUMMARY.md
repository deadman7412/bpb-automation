# BPB Automation - Change Summary

**Last Updated**: 2026-02-18

## Recent Updates (v2.1.0)

### 1. Multi-Round Sampling Algorithm (NEW - Major Improvement)

**Problem**: Sometimes only 7-8 clean IPs found when target is 10, requiring manual deep scan.

**Solution**: Implemented intelligent multi-round sampling that automatically retries up to 5 rounds to reach target.

**Files Changed**:
- `lib/services/dart_scanner_service.dart`: Complete refactor to support multi-round strategy

**How It Works**:
```
Round 1: Test ~696 random IPs → find 7 clean IPs (need 3 more)
Round 2: Test NEW ~696 random IPs → find 4 clean IPs (11/10 total - TARGET MET!)
Stop early, sort all 11 IPs by speed, return top 10
```

**Features**:
- **Up to 5 rounds** before suggesting deep scan
- **Early exit** when target reached (mid-round if needed)
- **Duplicate IP filtering** across rounds using Set tracker
- **Accumulates results** across all rounds
- **Final sort** by speed after all rounds complete
- **Smart target calculation** per round (overall_target - already_found)

**Benefits**:
- 🚀 **Faster**: Multiple 30-sec rounds vs one 4-min deep scan
- 📊 **Better coverage**: Tests different random IPs from each /24 subnet per round
- ✅ **Automatic recovery**: No manual intervention needed when first round insufficient
- 🎯 **Guaranteed results**: Continues until target met or 5 rounds exhausted

**Algorithm Structure**:
```
executeScan() - Main entry point:
  ├─ Multi-round loop (max 5 rounds)
  ├─ Track: allCleanResults[], testedIPs Set, totalIPsTested
  ├─ For each round:
  │   ├─ _executeSingleRound()
  │   ├─ Accumulate results
  │   └─ Early exit if target reached
  ├─ Final sort by speed (ALL results)
  └─ Return with status

_executeSingleRound() - Per-round execution (4 phases):
  ├─ Phase 1: Load IPs, filter duplicates from previous rounds
  ├─ Phase 2: Latency test (concurrent)
  ├─ Phase 3: Filter by latency/loss criteria
  └─ Phase 4: Download test (serial, early exit when round target met)
```

**Progress Messages**:
- Shows round number: "Round 2/5"
- Shows accumulated progress: "Found 11/10 total (4 this round)"
- Shows per-round completion: "Round 2 complete: +4 clean IPs found"

**Status After 5 Rounds**:
- If target met → `success` status
- If insufficient → `insufficient` status with message:
  ```
  "After 5 rounds, only 8/10 clean IPs found.
   Consider: (1) Run deep scan (test all 5,956 IPs),
            (2) Lower quality filters, or
            (3) Accept current results"
  ```

---

### 2. UI Improvements

#### Desktop Layout - Wider Content Area
**Files Changed**: `lib/screens/home_screen.dart`

**Changes**:
- Added `ConstrainedBox` with `maxWidth: 900px`
- Progress cards and buttons now fully visible on desktop
- Better use of screen space on larger displays

#### Simplified Configuration Presets
**Files Changed**: 
- `lib/models/scanner_config.dart`
- `lib/screens/config_screen.dart`
- `test/models/scanner_config_test.dart`

**Changes**:
- Removed confusing presets: Fast, Balanced, Quality
- Kept only: **Mobile**, **Desktop**, **Custom** (auto-detected)
- Updated tests to match

**Preset Details**:
- **Mobile**: Conservative (5 IPs, 100 threads, stricter filters)
- **Desktop**: Balanced (10 IPs, 200 threads, relaxed filters)
- **Custom**: Automatically selected when user modifies any setting

#### Fixed Autoscroll in Logs
**Files Changed**: `lib/screens/logs_screen.dart`

**Changes**:
- Added `_previousLogCount` tracker to detect new logs
- Replaced unreliable `Future.microtask()` with `WidgetsBinding.addPostFrameCallback()`
- Uses `jumpTo()` instead of `animateTo()` for instant scroll
- New logs now correctly appear at bottom while viewing

#### Export Logs to File
**Files Changed**: `lib/screens/logs_screen.dart`

**Changes**:
- Added platform-specific file saving using `path_provider`
- Export locations:
  - Android: External storage
  - iOS: Documents directory
  - Desktop: Downloads directory
- Filename format: `bpb_automation_logs_2026-02-18T14-30-45.txt`
- New popup menu with 3 options:
  - Export to File (saves to disk)
  - Copy to Clipboard (quick copy)
  - Clear Logs (remove all)
- Success message shows file path with "Copy Path" action

---

### 3. Documentation Cleanup

**Changes**:
- Moved 13 obsolete docs to `docs/archive/`
- Kept only 7 core docs in `docs/`:
  - `architecture.md` - Technical architecture
  - `cloudflare-setup.md` - Credential setup guide
  - `scanner-configuration.md` - Scanner parameters
  - `development.md` - Developer setup
  - `deployment.md` - Building and distribution
  - `user-guide.md` - End-user documentation
  - `project-timeline.md` - Project phases and tasks

**Archived Docs** (moved to `docs/archive/`):
- Migration docs (dart-scanner-implementation-plan, pareto-scanner-migration, etc.)
- Developer-specific docs (android-emulator-setup, app-icon-setup)
- Redundant guides (building-locally, distribution-materials, download-install-guide)
- Internal docs (state-management, go-scanner-alignment)

---

## Previous Critical Fixes (v2.0.0)

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
- Preset configs updated to match

### 3. testAllIPs Feature

**Problem**: Backend supported testAllIPs but it wasn't exposed in the UI.

**Files Changed**:
- `lib/models/scanner_config.dart`: Added `testAllIPs` boolean field (default: false)
- `lib/services/dart_scanner_service.dart`: Wired testAllIPs to IPLoader
- `lib/screens/config_screen.dart`: Added UI toggle in Advanced Settings

**Behavior**:
- `testAllIPs=false` (default): Tests ~696 IPs (1 random per /24 subnet) - FAST (~30 sec)
- `testAllIPs=true`: Tests ~5956 IPs (ALL 256 per /24 subnet) - SLOW (~4 min)

**Rationale**: Default is statistically valid due to Cloudflare Anycast - all IPs in same /24 route to same server.

---

## Testing Status

### ✅ VERIFIED
- [x] Multi-round algorithm implemented and compiles
- [x] Desktop layout wider (900px max width)
- [x] Config presets simplified to Mobile/Desktop/Custom
- [x] Logs autoscroll fixed
- [x] Export logs to file working
- [x] Documentation cleanup complete
- [x] All code compiles without errors (`flutter analyze` passes)

### ⏳ NEEDS TESTING
- [ ] Multi-round algorithm behavior in real-world scanning
  - Does it run multiple rounds when target not met?
  - Does early exit work when target reached?
  - Are duplicate IPs properly filtered across rounds?
- [ ] EWMA fix validation - IPs perform well in actual VPN usage
- [ ] UI config values applied during scan
- [ ] testAllIPs toggle (696 vs 5956 IPs)

---

## References

- Go Scanner: https://github.com/bia-pain-bache/Cloudflare-Clean-IP-Scanner
- EWMA Library: https://github.com/VividCortex/ewma (DECAY = 0.064516129)
