package com.bpb.bpb_automation

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.pm.ServiceInfo
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class ScanForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var currentTitle: String = "BPB scan running"
    private var currentText: String = "Local scan continues while screen is locked"
    private var progressCurrent: Int = 0
    private var progressTotal: Int = 0
    private var indeterminate: Boolean = true

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_UPDATE -> {
                applyUpdateIntent(intent)
                notifyUpdated()
                return START_NOT_STICKY
            }
            ACTION_RESET -> {
                resetNotificationState()
                notifyUpdated()
                return START_NOT_STICKY
            }
            else -> {}
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                buildNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle(currentTitle)
            .setContentText(currentText)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)
        if (progressTotal > 0) {
            builder.setProgress(progressTotal, progressCurrent.coerceIn(0, progressTotal), indeterminate)
        } else {
            builder.setProgress(0, 0, indeterminate)
        }
        return builder.build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Scan execution",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps local scan active in foreground"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "bpb_automation:scan_fg_wakelock"
        ).apply {
            setReferenceCounted(false)
            acquire(WAKELOCK_TIMEOUT_MS)
        }
    }

    private fun releaseWakeLock() {
        val lock = wakeLock
        if (lock != null && lock.isHeld) {
            lock.release()
        }
        wakeLock = null
    }

    private fun resetNotificationState() {
        currentTitle = "BPB scan running"
        currentText = "Local scan continues while screen is locked"
        progressCurrent = 0
        progressTotal = 0
        indeterminate = true
    }

    private fun applyUpdateIntent(intent: Intent) {
        intent.getStringExtra(EXTRA_TITLE)?.let { currentTitle = it }
        intent.getStringExtra(EXTRA_TEXT)?.let { currentText = it }
        if (intent.hasExtra(EXTRA_PROGRESS_TOTAL)) {
            progressTotal = intent.getIntExtra(EXTRA_PROGRESS_TOTAL, 0)
        }
        if (intent.hasExtra(EXTRA_PROGRESS_CURRENT)) {
            progressCurrent = intent.getIntExtra(EXTRA_PROGRESS_CURRENT, 0)
        }
        if (intent.hasExtra(EXTRA_INDETERMINATE)) {
            indeterminate = intent.getBooleanExtra(EXTRA_INDETERMINATE, false)
        }
    }

    private fun notifyUpdated() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    companion object {
        private const val CHANNEL_ID = "bpb_scan_foreground"
        private const val NOTIFICATION_ID = 11042
        private const val WAKELOCK_TIMEOUT_MS = 30 * 60 * 1000L
        private const val ACTION_UPDATE = "com.bpb.bpb_automation.action.UPDATE_SCAN_NOTIFICATION"
        private const val ACTION_RESET = "com.bpb.bpb_automation.action.RESET_SCAN_NOTIFICATION"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_PROGRESS_CURRENT = "progress_current"
        private const val EXTRA_PROGRESS_TOTAL = "progress_total"
        private const val EXTRA_INDETERMINATE = "indeterminate"

        fun start(context: Context) {
            val intent = Intent(context, ScanForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context, ScanForegroundService::class.java)
            context.stopService(intent)
        }

        fun update(
            context: Context,
            title: String?,
            text: String?,
            progressCurrent: Int?,
            progressTotal: Int?,
            indeterminate: Boolean?
        ) {
            val intent = Intent(context, ScanForegroundService::class.java).apply {
                action = ACTION_UPDATE
                if (title != null) putExtra(EXTRA_TITLE, title)
                if (text != null) putExtra(EXTRA_TEXT, text)
                if (progressCurrent != null) putExtra(EXTRA_PROGRESS_CURRENT, progressCurrent)
                if (progressTotal != null) putExtra(EXTRA_PROGRESS_TOTAL, progressTotal)
                if (indeterminate != null) putExtra(EXTRA_INDETERMINATE, indeterminate)
            }
            context.startService(intent)
        }

        fun reset(context: Context) {
            val intent = Intent(context, ScanForegroundService::class.java).apply {
                action = ACTION_RESET
            }
            context.startService(intent)
        }
    }
}
