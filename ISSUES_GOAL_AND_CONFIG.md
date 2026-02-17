# Issues Found and Fixes

## Issue 1: Goal Progress Not Updating in Real-Time ✅

### Problem
The "Goal: X/Y clean IPs" display doesn't update during download testing within a batch. It only updates when a batch completes.

**Location:** `lib/services/dart_scanner_service.dart:337`

### Root Cause
```dart
cleanIPsFound: currentCleanCount,  // ❌ Static value passed at batch start
```

The `currentCleanCount` is passed in when Pareto download testing starts, but it's not incremented as individual download tests succeed. So the UI shows "Goal: 0/20" throughout the entire download testing phase.

### Fix
Track the clean IPs found in real-time during download testing:

```dart
// At start of _testDownloadsPareto
var cleanIPsFoundInThisBatch = 0;

// In the download test loop (line 324-326)
if (speedResult.isSuccessful) {
  successInBatch++;
  cleanIPsFoundInThisBatch++;  // ✅ Track real-time
}

// Update progress with real-time count (line 337)
cleanIPsFound: currentCleanCount + cleanIPsFoundInThisBatch,  // ✅ Live update
```

---

## Issue 2: Redundant Configuration Setting ✅

### Problem
**"IPs to Scan for Speed"** (`downloadCount`) setting is now **REDUNDANT** after Pareto migration.

**Why it's redundant:**
- Old algorithm: Test downloads for exactly N IPs (user-specified `downloadCount`)
- New algorithm: Test downloads using Pareto 20% rule until target met (ignores `downloadCount`)
- The setting exists in config but is **NOT USED** by `DartScannerService`

### Settings Analysis

#### KEEP (Still Used)
1. ✅ **Target Clean IPs** - Primary goal
2. ✅ **Minimum Acceptable IPs** - Safety net
3. ✅ **Batch Size** - IPs per batch
4. ✅ **Max Total IPs to Test** - Safety limit
5. ✅ **Download Test Percentage** - Pareto rule (20%)
6. ✅ **Threads** - Concurrency
7. ✅ **Test Count** - Latency iterations
8. ✅ **Latency Limit** - Max acceptable latency
9. ✅ **Latency Lower Limit** - Min acceptable latency
10. ✅ **Speed Limit** - Min download speed
11. ✅ **Test Port** - Port to test
12. ✅ **Test URL** - Download URL
13. ✅ **Disable Download** - Skip download tests
14. ✅ **HTTPing Mode** - HTTP vs ICMP
15. ✅ **Download Test Time** - Timeout per download

#### REMOVE (Redundant)
1. ❌ **IPs to Scan for Speed** (`downloadCount`) - NOT USED in Pareto algorithm

### Recommended Action
**Remove `downloadCount` setting from:**
1. Configuration screen UI
2. Keep in model for backward compatibility (set to ignored default)
3. Add migration note in docs

---

## Implementation Plan

### Fix 1: Real-Time Goal Progress Update

**File:** `lib/services/dart_scanner_service.dart`

**Changes:**
1. Add `cleanIPsFoundInThisBatch` counter
2. Increment on each successful download
3. Update progress emissions with live count

### Fix 2: Remove Redundant Setting

**File:** `lib/screens/config_screen.dart`

**Changes:**
1. Remove "IPs to Scan for Speed" slider from UI
2. Keep field in model (for backward compatibility)
3. Add comment explaining deprecation

**File:** `lib/models/scanner_config.dart`

**Changes:**
1. Mark `downloadCount` as `@deprecated`
2. Add documentation explaining it's no longer used
3. Keep default value for JSON compatibility

---

## Priority

**Issue 1 (Goal Update):** HIGH - User-visible UX issue
**Issue 2 (Redundant Setting):** MEDIUM - Confusing but not breaking
