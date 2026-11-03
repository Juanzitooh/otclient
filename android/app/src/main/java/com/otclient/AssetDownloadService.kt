package com.otclient

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class AssetDownloadService : Service() {
    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Download de dados do Elemental",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Progresso do download inicial dos dados do jogo"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(true)
            stopSelf(startId)
            return START_NOT_STICKY
        }

        val status = intent?.getStringExtra(EXTRA_STATUS).orEmpty()
            .ifBlank { "Preparando download dos dados" }
        val progress = intent?.getIntExtra(EXTRA_PROGRESS, -1) ?: -1
        val detail = intent?.getStringExtra(EXTRA_DETAIL).orEmpty()
        startForeground(NOTIFICATION_ID, buildNotification(status, progress, detail))
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTimeout(startId: Int, fgsType: Int) {
        stopForeground(true)
        stopSelf(startId)
    }

    private fun buildNotification(status: String, progress: Int, detail: String): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Elemental")
            .setContentText(detail.ifBlank { status })
            .setSubText(status)
            .setContentIntent(openApp)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setProgress(100, progress.coerceIn(0, 100), progress < 0)
            .build()
    }

    companion object {
        const val ACTION_UPDATE = "com.otclient.action.UPDATE_ASSET_DOWNLOAD"
        const val ACTION_STOP = "com.otclient.action.STOP_ASSET_DOWNLOAD"
        const val EXTRA_STATUS = "status"
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_DETAIL = "detail"
        private const val CHANNEL_ID = "elemental_asset_downloads"
        private const val NOTIFICATION_ID = 7171
    }
}
