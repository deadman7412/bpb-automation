import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'log_service.dart';

class AndroidForegroundScanService {
  AndroidForegroundScanService._();
  static final AndroidForegroundScanService instance =
      AndroidForegroundScanService._();

  static const MethodChannel _channel = MethodChannel(
    'com.bpb.bpb_automation/native',
  );
  final LogService _log = LogService.instance;
  bool _notificationPermissionRequested = false;

  Future<void> _ensureNotificationPermission() async {
    if (!Platform.isAndroid) return;
    if (_notificationPermissionRequested) return;
    _notificationPermissionRequested = true;
    try {
      final granted = await _channel.invokeMethod<bool>(
        'requestNotificationPermission',
      );
      if (granted != true) {
        _log.logWarn(
          'Android notification permission denied. Foreground scan notification may be hidden.',
        );
      }
    } catch (e) {
      _log.logWarn('Failed to request Android notification permission: $e');
    }
  }

  Future<void> start() async {
    if (!Platform.isAndroid) return;
    await _ensureNotificationPermission();
    try {
      await _channel.invokeMethod<bool>('startForegroundScanService');
      _log.logInfo('Android foreground scan service started');
    } catch (e) {
      _log.logWarn('Failed to start Android foreground scan service: $e');
    }
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('stopForegroundScanService');
      _log.logInfo('Android foreground scan service stopped');
    } catch (e) {
      _log.logWarn('Failed to stop Android foreground scan service: $e');
    }
  }

  Future<void> updateProgress({
    required String title,
    required String text,
    required int progressCurrent,
    required int progressTotal,
    bool indeterminate = false,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('updateForegroundScanNotification', {
        'title': title,
        'text': text,
        'progressCurrent': progressCurrent,
        'progressTotal': progressTotal,
        'indeterminate': indeterminate,
      });
    } catch (e) {
      _log.logWarn('Failed to update Android foreground notification: $e');
    }
  }

  Future<void> showIndeterminate({
    required String title,
    required String text,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('updateForegroundScanNotification', {
        'title': title,
        'text': text,
        'progressCurrent': 0,
        'progressTotal': 0,
        'indeterminate': true,
      });
    } catch (e) {
      _log.logWarn('Failed to update Android foreground notification: $e');
    }
  }
}
