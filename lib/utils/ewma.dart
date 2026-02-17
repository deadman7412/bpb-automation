/// Exponentially Weighted Moving Average (EWMA) implementation
///
/// Matches the behavior of github.com/VividCortex/ewma library used by
/// the original Cloudflare-Clean-IP-Scanner Go project.
///
/// EWMA provides a smoothed average that weights recent values more heavily
/// than older values, making it ideal for measuring sustained throughput
/// quality rather than just raw speed.
class EWMA {
  /// The current EWMA value
  double _value = 0.0;

  /// Whether the EWMA has been initialized with at least one value
  bool _initialized = false;

  /// Decay factor for the exponential weighting
  /// Default matches the SimpleEWMA from the Go library
  final double _alpha;

  /// Create a new EWMA with optional custom decay factor
  ///
  /// The default alpha of 0.2 means new values have 20% weight
  /// and the existing average has 80% weight, providing smooth averaging.
  EWMA([this._alpha = 0.2]) {
    if (_alpha <= 0 || _alpha > 1) {
      throw ArgumentError('Alpha must be between 0 and 1');
    }
  }

  /// Add a new value to the moving average
  ///
  /// For the first value, it becomes the initial average.
  /// Subsequent values are weighted exponentially.
  void add(double value) {
    if (!_initialized) {
      _value = value;
      _initialized = true;
    } else {
      // EWMA formula: new_avg = alpha * new_value + (1 - alpha) * old_avg
      _value = (_alpha * value) + ((1 - _alpha) * _value);
    }
  }

  /// Get the current EWMA value
  double get value => _value;

  /// Check if the EWMA has been initialized
  bool get isInitialized => _initialized;

  /// Reset the EWMA to initial state
  void reset() {
    _value = 0.0;
    _initialized = false;
  }

  /// Create an EWMA with custom decay corresponding to a time window
  ///
  /// This factory matches the Go library's NewMovingAverage() behavior
  /// which uses alpha = 2 / (N + 1) where N is the window size.
  factory EWMA.withWindow(int windowSize) {
    if (windowSize < 1) {
      throw ArgumentError('Window size must be at least 1');
    }
    final alpha = 2.0 / (windowSize + 1);
    return EWMA(alpha);
  }
}
