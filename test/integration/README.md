# Integration Tests

current repository state.

The scanner is now validated primarily by:
- Service/model/unit tests in `test/services/` and `test/models/`
- Real-device scan runs with log verification (`app_log.txt` and runtime logs)

## Recommended Validation

Run fast automated validation:
```bash
flutter test --exclude-tags=integration
flutter analyze
```

Run scanner-focused suites:
```bash
flutter test test/services/config_tester_service_test.dart
flutter test test/services/xray_service_test.dart
flutter test test/services/ip_loader_test.dart test/services/ip_loader_subnet_test.dart
flutter test test/models/config_scan_result_test.dart
```

## Real-Network Validation

For true end-to-end confidence, run a scan on the target network/device and
inspect logs for:
- Phase 0 completion counts
- Phase 1a / 1b TLS pass rates
- Phase 2 proxy success/failure ratio
- Final summary (`Found X working IPs`)
