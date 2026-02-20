package com.bpb.bpb_automation

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.bpb.bpb_automation/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNativeLibraryDir" -> {
                        result.success(applicationInfo.nativeLibraryDir)
                    }
                    "startForegroundScanService" -> {
                        try {
                            ScanForegroundService.start(this)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error(
                                "FGS_START_FAILED",
                                e.message,
                                null
                            )
                        }
                    }
                    "stopForegroundScanService" -> {
                        try {
                            ScanForegroundService.stop(this)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error(
                                "FGS_STOP_FAILED",
                                e.message,
                                null
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
