package com.bpb.bpb_automation

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.bpb.bpb_automation/native"
    private val SCHEDULER_NOTIFICATION_CHANNEL_ID = "bpb_scheduler_events"

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
                    "updateForegroundScanNotification" -> {
                        try {
                            val title = call.argument<String>("title")
                            val text = call.argument<String>("text")
                            val progressCurrent = call.argument<Int>("progressCurrent")
                            val progressTotal = call.argument<Int>("progressTotal")
                            val indeterminate = call.argument<Boolean>("indeterminate")
                            ScanForegroundService.update(
                                context = this,
                                title = title,
                                text = text,
                                progressCurrent = progressCurrent,
                                progressTotal = progressTotal,
                                indeterminate = indeterminate
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error(
                                "FGS_UPDATE_FAILED",
                                e.message,
                                null
                            )
                        }
                    }
                    "resetForegroundScanNotification" -> {
                        try {
                            ScanForegroundService.reset(this)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error(
                                "FGS_RESET_FAILED",
                                e.message,
                                null
                            )
                        }
                    }
                    "showLocalNotification" -> {
                        try {
                            val title = call.argument<String>("title") ?: "BPB Automation"
                            val body = call.argument<String>("body") ?: ""
                            showLocalNotification(title = title, body = body)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error(
                                "LOCAL_NOTIFICATION_FAILED",
                                e.message,
                                null
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun showLocalNotification(title: String, body: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(
                this,
                android.Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
            if (!granted) {
                throw IllegalStateException("POST_NOTIFICATIONS permission is not granted")
            }
        }

        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                SCHEDULER_NOTIFICATION_CHANNEL_ID,
                "Scheduler events",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Scheduler start, completion, and failure events"
                setShowBadge(true)
            }
            manager.createNotificationChannel(channel)
        }

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, SCHEDULER_NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        val notificationId = (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
        manager.notify(notificationId, notification)
    }
}
