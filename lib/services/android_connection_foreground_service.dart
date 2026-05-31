import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'log_service.dart';

class AndroidConnectionForegroundService {
  static final AndroidConnectionForegroundService _instance =
      AndroidConnectionForegroundService._internal();
  static AndroidConnectionForegroundService get instance => _instance;
  AndroidConnectionForegroundService._internal();

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
          '[Proxy] Android notification permission denied. Connection notification may be hidden.',
        );
      }
    } catch (e) {
      _log.logWarn('[Proxy] Failed to request Android notification permission: $e');
    }
  }

  Future<void> start({
    required int socksPort,
    int? httpPort,
    required String ip,
  }) async {
    if (!Platform.isAndroid) return;
    await _ensureNotificationPermission();
    try {
      await _channel.invokeMethod<bool>('startConnectionForegroundService', {
        'socksPort': socksPort,
        'httpPort': httpPort,
        'ip': ip,
      });
      _log.logInfo('[Proxy] Android connection foreground service started');
    } catch (e) {
      _log.logWarn(
        '[Proxy] Failed to start Android connection foreground service: $e',
      );
    }
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('stopConnectionForegroundService');
      _log.logInfo('[Proxy] Android connection foreground service stopped');
    } catch (e) {
      _log.logWarn(
        '[Proxy] Failed to stop Android connection foreground service: $e',
      );
    }
  }

  Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('updateConnectionNotification', {
        'title': title,
        'text': text,
      });
    } catch (e) {
      _log.logWarn(
        '[Proxy] Failed to update Android connection notification: $e',
      );
    }
  }
}
