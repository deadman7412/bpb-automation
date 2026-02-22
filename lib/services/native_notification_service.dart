import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'log_service.dart';

class NativeNotificationService {
  NativeNotificationService._();
  static final NativeNotificationService instance =
      NativeNotificationService._();

  static const MethodChannel _channel = MethodChannel(
    'com.bpb.bpb_automation/native',
  );
  final LogService _log = LogService.instance;
  bool _permissionRequested = false;

  bool get _isIOSRuntime =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get _isAndroidRuntime =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isMobileRuntime => _isIOSRuntime || _isAndroidRuntime;

  Future<void> ensurePermissionIfNeeded() async {
    if (!_isIOSRuntime) return;
    if (_permissionRequested) return;
    _permissionRequested = true;
    try {
      await _channel.invokeMethod<bool>('requestNotificationPermission');
    } catch (e) {
      _log.logWarn('iOS notification permission request failed: $e');
    }
  }

  Future<void> notifySchedulerStarted({required String detail}) async {
    await _show('Scheduler started', detail);
  }

  Future<void> notifySchedulerFinished({required String detail}) async {
    await _show('Scheduler completed', detail);
  }

  Future<void> notifySchedulerFailed({required String detail}) async {
    await _show('Scheduler failed', detail);
  }

  Future<void> _show(String title, String body) async {
    if (!_isMobileRuntime) return;
    if (_isIOSRuntime) {
      await ensurePermissionIfNeeded();
    }
    try {
      await _channel.invokeMethod<bool>('showLocalNotification', {
        'title': title,
        'body': body,
      });
    } catch (e) {
      _log.logWarn('Failed to show native local notification: $e');
    }
  }
}
