# Integration Tests

## Pareto Scanner Integration Tests

The `pareto_scanner_integration_test.dart` file contains comprehensive end-to-end integration tests for the Pareto-based multi-batch scanning system.

### Test Scenarios

The test suite includes 13 tests covering:

**Network Tests (8 tests - SLOW, 30-60 min total):**
1. **Scenario 1** - Goal met in single batch (5 min timeout)
2. **Scenario 2** - Goal met across multiple batches (10 min timeout)
3. **Scenario 3** - Partial success (5 min timeout)
4. **Scenario 4** - Insufficient results (3 min timeout)
5. **Scenario 5** - No downloads found (5 min timeout)
6. **Scenario 6** - Exhausted all IPs (5 min timeout)
7. **Scenario 7** - Duplicate prevention (10 min timeout)
8. **Scenario 9** - Pareto efficiency (5 min timeout)

**Validation Tests (5 tests - FAST, <1 second total):**
9. **Scenario 8** - Platform-adaptive batch sizes
10. **Scenario 10** - Edge case: Zero target
11. **Scenario 10b** - Edge case: Min > target
12. **Scenario 10c** - Edge case: Batch size validation
13. **Status determination** - All status types

### Running the Tests

**IMPORTANT**: Network tests perform actual scans against Cloudflare IPs and take 30-60 minutes!
Network tests may fail in restricted environments due to rate limiting, firewalls, or network conditions.

#### RECOMMENDED: Run only fast validation tests (development workflow)
```bash
flutter test test/integration/pareto_scanner_integration_test.dart --exclude-tags=integration
```
This runs the 5 fast validation tests (<1 second total) and skips the 8 slow network tests.

**This is the recommended command for development and CI pipelines.**

#### Run ALL tests including slow network tests (30-60 minutes):
```bash
flutter test test/integration/pareto_scanner_integration_test.dart
```
OR to explicitly run only network tests:
```bash
flutter test test/integration/pareto_scanner_integration_test.dart --tags=integration
```

**WARNING**: Network tests may fail in CI environments, restricted networks, or due to:
- Cloudflare rate limiting (HTTP 429)
- Firewall/ISP blocking
- Network connectivity issues
- No clean IPs found in tested ranges

These failures are expected and do NOT indicate bugs in the code.

#### Run specific test by name:
```bash
flutter test test/integration/pareto_scanner_integration_test.dart --name="Scenario 8"
```

### Test Tags

Network tests are tagged with: `['integration', 'slow', 'network']`
- These tags allow skipping slow tests during development
- Validation tests have NO tags and always run

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
