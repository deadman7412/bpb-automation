# Quick Test Reference Guide

## Summary

- Active test suites are unit/service/model/widget tests.
- Current recommended baseline is `flutter test --exclude-tags=integration`.

## Recommended Commands

### Full Validation Script (RECOMMENDED)
Run the project validation suite:
```bash
./scripts/run_validation_suite.sh
```
What it includes:
- `backend` static analysis (`dart analyze`)
- app static analysis (`flutter analyze --no-fatal-infos`)
- full test suite (`flutter test`)
- isolated backend/API smoke checks (security and scheduler API guards)

### Daily Development (RECOMMENDED)
Run all fast tests:
```bash
flutter test --exclude-tags=integration
```
**Expected:** all active non-integration tests pass.

### Scanner-Focused Regression
Run scanner-critical suites directly:
```bash
flutter test test/services/config_tester_service_test.dart
flutter test test/services/xray_service_test.dart
flutter test test/services/ip_loader_test.dart test/services/ip_loader_subnet_test.dart
flutter test test/models/config_scan_result_test.dart
```

### Static Analysis
Check for code issues:
```bash
flutter analyze
```
**Expected: No issues found**

## Test Failures

### If Fast Tests Fail
This indicates a real bug. Investigate and fix.

### If Real Network Scan Behaves Differently
Unit tests cannot fully model ISP routing and Cloudflare edge behavior.
Use app scan logs (`app_log.txt`) to validate Phase 0/1/2 behavior in your real network.

## CI/CD Integration

Use this in your CI pipeline:
```bash
./scripts/run_validation_suite.sh
```

## Test Coverage

| Test Type | Count | Duration | Command |
|-----------|-------|----------|---------|
| Unit/Service/Model/Widget tests | Varies by branch | ~seconds to ~minutes | `flutter test --exclude-tags=integration` |
| Scanner-focused regression | 4 suites | ~10-30s | Commands listed above |

## Current Status

✅ Fast test baseline passing
✅ 0 analysis issues  
✅ Scanner service tests passing

**Last verified: 2026-02-20**
