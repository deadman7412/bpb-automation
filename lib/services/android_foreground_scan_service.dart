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

  Future<void> start() async {
    if (!Platform.isAndroid) return;
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
}
