# Integration Tests

## Pareto Scanner Integration Tests

The `pareto_scanner_integration_test.dart` file contains comprehensive end-to-end integration tests for the Pareto-based multi-batch scanning system.

### Test Scenarios

The test suite covers all 10 migration requirements:

1. **Goal met in single batch** - Verifies successful completion with minimal batching
2. **Goal met across multiple batches** - Tests multi-batch scanning loop
3. **Partial success** - Tests graceful degradation (min met, target not met)
4. **Insufficient results** - Tests failure case (below minimum)
5. **No downloads found** - Tests downloads disabled mode
6. **Exhausted all IPs** - Tests IP pool exhaustion handling
7. **Duplicate prevention** - Verifies no IP tested twice across batches
8. **Pareto 20% efficiency** - Validates 20% incremental download testing
9. **Platform-adaptive batch sizes** - Tests mobile vs desktop batch sizing
10. **Edge cases** - Zero IPs, invalid config, network failures

### Running the Tests

**IMPORTANT**: These are real integration tests that perform actual network scans against Cloudflare IPs. They do NOT use mocking.

#### Run all integration tests:
```bash
flutter test test/integration/
```

#### Run specific test:
```bash
flutter test test/integration/pareto_scanner_integration_test.dart
```

### Test Execution Time

These tests make real network calls and can take **30-60 minutes** to complete:
- Each test has a 3-10 minute timeout
- Tests perform actual latency and download testing
- Network conditions affect test duration
- Total runtime: 30-90 minutes depending on network

### Requirements

- Active internet connection
- Access to Cloudflare IP ranges
- Sufficient network bandwidth for download tests
- Flutter test environment with bindings initialized

### Test Structure

Each test:
1. Creates a realistic `ScannerConfig`
2. Executes real scan via `DartScannerService.executeScan()`
3. Tracks progress updates via stream
4. Validates final status, clean IPs, and batch tracking
5. Verifies Pareto download testing behavior
6. Ensures no duplicate IPs across batches

### Expected Results

All tests should pass with proper network connectivity. If tests fail:
- Check internet connection
- Verify Cloudflare IPs are accessible
- Check network firewall settings
- Review test output for specific error messages

### Development Notes

- Tests use `TestWidgetsFlutterBinding.ensureInitialized()` for Flutter services
- Progress tracking verifies batch-by-batch behavior
- Status determination tests cover all 4 status types (success, partial, insufficient, failed)
- Download testing verifies Pareto principle (20% incremental batching)

### Phase 8 Validation

These tests validate completion of Phase 8 of the Pareto scanner migration:
- Multi-batch scanning loop
- Goal-oriented scanning (target clean IPs)
- Pareto download testing
- Duplicate prevention
- Status determination
- Graceful degradation
