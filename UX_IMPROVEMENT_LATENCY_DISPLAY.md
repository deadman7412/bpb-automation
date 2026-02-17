# UX Improvement: Preserve Latency Results During Download Testing

**Date:** 2026-02-17
**Issue:** Pass/Fail counters reset to 0 during download testing, confusing users
**Status:** FIXED

---

## Problem

When the scanner transitions from latency testing to download testing, the UI shows:
```
Batch 6: Testing downloads for 1/24 IPs (top 75%)
Pass: 0    Fail: 0    Total: 1091
```

This is confusing because:
1. Users lose context about latency test results
2. Progress appears to restart, making it look like something went wrong
3. The 0/0 counters don't convey useful information

### Root Cause

During download testing, the `ScanProgress` updates use fresh counters:
- `successfulIPs` = download test successes (starts at 0)
- `failedIPs` = download test failures (starts at 0)

This overwrites the latency test results that were showing before.

---

## Solution

**Preserve latency results and display them during download testing.**

### Implementation

1. **Added new fields to `ScanProgress` model:**
   - `lastBatchLatencyPass`: Stores the latency pass count
   - `lastBatchLatencyFail`: Stores the latency fail count

2. **Updated `DartScannerService`:**
   - Pass latency results (`batchSuccessfulIPs`, `batchFailedIPs`) to `_testDownloadsPareto()`
   - Include these values in all progress updates during download testing

3. **Updated `home_screen.dart` UI:**
   - During download testing: Show "Latency Results: Pass: X Fail: Y"
   - During other stages: Show normal "Pass: X Fail: Y"

### New UI Behavior

**During latency testing:**
```
Batch 6: Latency 150/150
Pass: 45    Fail: 105    Total: 1091
```

**During download testing:**
```
Batch 6: Testing downloads for 1/24 IPs (top 75%)
Latency Results:
Pass: 45    Fail: 105    Total: 1091
```

---

## Benefits

✅ **Maintains context** - Users see latency results throughout the scan
✅ **No confusing reset** - Counters never drop to 0
✅ **Clear visual continuity** - Smooth transition between stages
✅ **Better UX** - Users understand both phases of testing

---

## Files Modified

### Model
- `lib/models/scan_progress.dart`
  - Added `lastBatchLatencyPass` and `lastBatchLatencyFail` fields
  - Updated `copyWith()`, `toJson()`, `fromJson()` methods

### Service
- `lib/services/dart_scanner_service.dart`
  - Added `latencyPass` and `latencyFail` parameters to `_testDownloadsPareto()`
  - Updated progress emissions to include latency results
  - Passed `batchSuccessfulIPs` and `batchFailedIPs` from latency test

### UI
- `lib/screens/home_screen.dart`
  - Conditional rendering based on scan stage
  - Show "Latency Results:" label during download testing
  - Preserve normal display during latency testing

---

## Testing

✅ All 31 ScanProgress tests passing
✅ No analysis issues
✅ Backward compatible (new fields are optional)

---

## Alternative Approaches Considered

### Option 2: Hide Pass/Fail During Downloads
**Pros:** Clean, no misleading zeros
**Cons:** Loses information, empty space looks unfinished

### Option 3: Show Download Pass/Fail
**Pros:** Shows current progress  
**Cons:** More complex, redundant (goal progress already shows this)

**Selected Option 1** because it provides the best user experience by maintaining context while clearly differentiating the testing stages.

---

## Summary

[OK] Latency results now preserved during download testing
[OK] Clear "Latency Results:" label shows context
[OK] No more confusing 0/0 counters
[OK] Smooth UX transition between test stages
[OK] All tests passing, zero breaking changes

Users now have continuous visibility into test results throughout the entire scanning process.
