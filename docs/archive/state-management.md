# State Management Strategy

## Overview

This application uses a lightweight, service-based state management approach appropriate for its complexity level. We avoid heavy state management frameworks (Provider, Riverpod, Bloc) in favor of a simpler architecture that's easier to understand and maintain.

## Architecture Components

### 1. Singleton Services (Global State)

All core services use the singleton pattern for global access:

- **StorageService**: Manages credentials and app preferences
- **LogService**: Centralized logging with in-memory buffer and file persistence
- **ScannerService**: Binary management and scan execution
- **CloudflareApiService**: API communication with retry logic

**Benefits**:
- Single source of truth
- Easy to access from any screen
- Thread-safe (Dart is single-threaded)
- No dependency injection needed

**Example**:
```dart
final storage = StorageService.instance;
final credentials = await storage.getCredentials();
```

### 2. Local UI State (StatefulWidget)

Each screen manages its own UI state using StatefulWidget and setState():

- Loading indicators
- Form inputs
- Temporary selections
- UI preferences (sort order, filter selections)

**Benefits**:
- Simple and straightforward
- Built-in to Flutter
- No external dependencies
- Clear lifecycle management

**Example**:
```dart
class _HomeScreenState extends State<HomeScreen> {
  bool _isScanning = false;

  void _startScan() {
    setState(() => _isScanning = true);
    // ... scanning logic
  }
}
```

### 3. Persistent Storage

Two storage mechanisms for different data types:

#### flutter_secure_storage (Encrypted)
- API tokens
- Account IDs
- KV Namespace IDs
- Any sensitive credentials

Platform-specific encryption:
- Android: Android Keystore
- iOS: iOS Keychain
- macOS: macOS Keychain

#### shared_preferences (Plain Text)
- Scanner configuration
- App preferences (num IPs to use, auto-update)
- Last scan time
- UI preferences

**Benefits**:
- Automatic persistence across app restarts
- Platform-optimized
- Simple key-value API

### 4. Navigation with Data Passing

Route arguments used to pass data between screens:

```dart
// Passing data
Navigator.pushNamed(context, '/results', arguments: scanResults);

// Receiving data
final args = ModalRoute.of(context)?.settings.arguments;
if (args != null && args is List<CleanIP>) {
  _results = args;
}
```

**Benefits**:
- Simple and explicit
- Type-safe
- No global state pollution
- Clear data flow

### 5. Real-time Updates (Streams)

LogService provides a broadcast stream for real-time log updates:

```dart
Stream<LogEntry> get logStream => _logController.stream;
```

**Usage**:
```dart
StreamBuilder<LogEntry>(
  stream: LogService.instance.logStream,
  builder: (context, snapshot) {
    // Update UI with new log entry
  },
)
```

**Benefits**:
- Reactive updates
- No polling needed
- Multiple listeners supported
- Automatic cleanup

## State Lifecycle

### App Launch
1. Services initialize (singletons created lazily)
2. StorageService loads from SharedPreferences
3. Screens load their initial state from storage
4. Scanner binary extracted if needed (version check)

### During Scan
1. Home screen sets `_isScanning = true` (local state)
2. Scanner service streams output (real-time)
3. Log service broadcasts log entries (stream)
4. Progress updates via setState()

### Scan Completion
1. Results passed to results screen via route arguments
2. Scan time saved to SharedPreferences
3. Results displayed from route arguments (not stored)
4. User can update BPB or navigate away

### BPB Update
1. Results screen calls CloudflareApiService
2. API service reads current settings (KV read)
3. Updates only cleanIPs field
4. Writes back to KV (preserving other fields)
5. Success/failure via callback
6. Preference saved (num IPs to use)

### App Close
1. SharedPreferences auto-saves (platform managed)
2. Logs flushed to file
3. SecureStorage auto-saves (platform managed)
4. No manual cleanup needed

## State Persistence Matrix

| State Type | Storage | Persists Across... | Example |
|------------|---------|-------------------|---------|
| Credentials | SecureStorage | App restarts | API token |
| Scanner config | SharedPreferences | App restarts | Thread count |
| Last scan time | SharedPreferences | App restarts | DateTime |
| Scan results | Route arguments | Navigation only | List<CleanIP> |
| Loading states | setState | Nothing | isScanning |
| Logs | File + memory | App restarts | LogEntry list |

## Design Decisions

### Why Not Provider/Riverpod?

**Reasons**:
1. App complexity doesn't warrant it
2. Singleton services already provide global state
3. No complex widget tree dependencies
4. Would add unnecessary complexity
5. Easier onboarding for contributors

### Why Not Bloc?

**Reasons**:
1. Overkill for this app's event complexity
2. More boilerplate code
3. Services already handle business logic
4. Events/states are simple enough for direct calls

### When to Refactor?

Consider state management framework if:
- App grows to 15+ screens
- Complex widget tree dependencies
- Multiple simultaneous scan workflows
- Real-time multi-user collaboration
- Undo/redo functionality needed

## Best Practices

1. **Keep UI State Local**: Don't store in services unless needed globally
2. **Use Services for Business Logic**: Not just data storage
3. **Log State Changes**: Important for debugging
4. **Validate Before Persist**: Don't save invalid states
5. **Clear Error States**: Don't persist temporary error states

## Example Patterns

### Pattern 1: Load and Display

```dart
@override
void initState() {
  super.initState();
  _loadConfig();
}

Future<void> _loadConfig() async {
  final config = await StorageService.instance.getScannerConfig();
  setState(() => _config = config);
}
```

### Pattern 2: Update and Persist

```dart
Future<void> _saveConfig() async {
  await StorageService.instance.saveScannerConfig(_config);
  LogService.instance.logOk('Configuration saved');

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Configuration saved')),
  );
}
```

### Pattern 3: Async Operation with States

```dart
Future<void> _performAction() async {
  setState(() => _isLoading = true);

  try {
    await SomeService.instance.doSomething();
    setState(() => _isLoading = false);
    _showSuccess();
  } catch (e) {
    setState(() => _isLoading = false);
    _showError(e);
  }
}
```

## Conclusion

Our state management approach is:
- **Simple**: Easy to understand and maintain
- **Appropriate**: Matches app complexity
- **Testable**: Services can be mocked
- **Scalable**: Can migrate to framework if needed
- **Performant**: No unnecessary rebuilds

This approach serves the app's current needs without over-engineering. If requirements change significantly, we can migrate to a more complex solution incrementally.
