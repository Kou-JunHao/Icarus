package uno.skkk.icarus

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * APK 下载前台服务
 * 
 * 解决应用进入后台后网络请求被中断的问题
 */
class DownloadService : Service() {

    companion object {
        private const val TAG = "DownloadService"
        private const val CHANNEL_ID = "download_service_channel"
        private const val NOTIFICATION_ID = 9527
        
        const val ACTION_START_DOWNLOAD = "uno.skkk.icarus.START_DOWNLOAD"
        const val ACTION_CANCEL_DOWNLOAD = "uno.skkk.icarus.CANCEL_DOWNLOAD"
        
        const val EXTRA_URL = "download_url"
        const val EXTRA_FILE_PATH = "file_path"
        const val EXTRA_VERSION = "version"
        const val EXTRA_FILE_SIZE = "file_size"
        
        // 下载状态广播
        const val BROADCAST_DOWNLOAD_PROGRESS = "uno.skkk.icarus.DOWNLOAD_PROGRESS"
        const val BROADCAST_DOWNLOAD_COMPLETE = "uno.skkk.icarus.DOWNLOAD_COMPLETE"
        const val BROADCAST_DOWNLOAD_ERROR = "uno.skkk.icarus.DOWNLOAD_ERROR"
        
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_TOTAL = "total"
        const val EXTRA_ERROR = "error"
        
        @Volatile
        var isRunning = false
            private set
    }

    private var downloadJob: Job? = null
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var wakeLock: PowerManager.WakeLock? = null
    
    private var currentUrl: String? = null
    private var currentFilePath: String? = null
    private var currentVersion: String? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        isRunning = true
        Log.d(TAG, "DownloadService created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_DOWNLOAD -> {
                val url = intent.getStringExtra(EXTRA_URL)
                val filePath = intent.getStringExtra(EXTRA_FILE_PATH)
                val version = intent.getStringExtra(EXTRA_VERSION) ?: "未知"
                val fileSize = intent.getLongExtra(EXTRA_FILE_SIZE, 0)
                
                if (url != null && filePath != null) {
                    currentUrl = url
                    currentFilePath = filePath
                    currentVersion = version
                    startForegroundService(version)
                    startDownload(url, filePath, version, fileSize)
                } else {
                    Log.e(TAG, "Missing download parameters")
                    stopSelf()
                }
            }
            ACTION_CANCEL_DOWNLOAD -> {
                cancelDownload()
            }
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        cancelDownload()
        releaseWakeLock()
        serviceScope.cancel()
        Log.d(TAG, "DownloadService destroyed")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "下载服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "应用更新下载"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun startForegroundService(version: String) {
        val notification = createNotification(version, 0, 0, "准备下载...")
        
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            acquireWakeLock()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start foreground service", e)
        }
    }

    private fun createNotification(
        version: String,
        progress: Int,
        total: Int,
        content: String
    ): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val cancelIntent = Intent(this, DownloadService::class.java).apply {
            action = ACTION_CANCEL_DOWNLOAD
        }
        val cancelPendingIntent = PendingIntent.getService(
            this,
            1,
            cancelIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("正在下载更新 v$version")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setProgress(total, progress, total == 0)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "取消", cancelPendingIntent)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    private fun updateNotification(version: String, progress: Int, total: Int, content: String) {
        val notification = createNotification(version, progress, total, content)
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "Icarus:DownloadWakeLock"
            ).apply {
                acquire(30 * 60 * 1000L) // 30分钟超时
            }
            Log.d(TAG, "WakeLock acquired")
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                Log.d(TAG, "WakeLock released")
            }
        }
        wakeLock = null
    }

    private fun startDownload(url: String, filePath: String, version: String, expectedSize: Long) {
        downloadJob?.cancel()
        
        downloadJob = serviceScope.launch {
            try {
                Log.d(TAG, "Starting download: $url -> $filePath")
                
                val file = File(filePath)
                file.parentFile?.mkdirs()
                if (file.exists()) {
                    file.delete()
                }

                val connection = URL(url).openConnection() as HttpURLConnection
                connection.apply {
                    requestMethod = "GET"
                    connectTimeout = 60000
                    readTimeout = 60000
                    setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36")
                    setRequestProperty("Accept", "*/*")
                    instanceFollowRedirects = true
                }

                connection.connect()
                
                val responseCode = connection.responseCode
                if (responseCode != HttpURLConnection.HTTP_OK) {
                    throw Exception("HTTP error: $responseCode")
                }

                val total = if (connection.contentLength > 0) {
                    connection.contentLength.toLong()
                } else {
                    expectedSize
                }

                var received = 0L
                val buffer = ByteArray(8192)
                var lastProgressUpdate = 0L

                connection.inputStream.use { input ->
                    FileOutputStream(file).use { output ->
                        var bytesRead: Int
                        while (input.read(buffer).also { bytesRead = it } != -1) {
                            if (!isActive) {
                                throw CancellationException("Download cancelled")
                            }
                            
                            output.write(buffer, 0, bytesRead)
                            received += bytesRead

                            // 每100ms或每1%更新一次进度
                            val now = System.currentTimeMillis()
                            if (now - lastProgressUpdate > 100 || 
                                (total > 0 && received * 100 / total != (received - bytesRead) * 100 / total)) {
                                lastProgressUpdate = now
                                
                                withContext(Dispatchers.Main) {
                                    val percent = if (total > 0) (received * 100 / total).toInt() else 0
                                    val receivedMB = String.format("%.1f", received / 1024.0 / 1024.0)
                                    val totalMB = String.format("%.1f", total / 1024.0 / 1024.0)
                                    
                                    updateNotification(
                                        version,
                                        percent,
                                        100,
                                        "$receivedMB MB / $totalMB MB ($percent%)"
                                    )
                                    
                                    sendProgressBroadcast(received, total)
                                }
                            }
                        }
                    }
                }

                connection.disconnect()

                // 验证文件
                if (file.exists() && file.length() > 0) {
                    Log.d(TAG, "Download complete: ${file.length()} bytes")
                    withContext(Dispatchers.Main) {
                        sendCompleteBroadcast(filePath)
                        showCompleteNotification(version, filePath)
                    }
                } else {
                    throw Exception("Downloaded file is empty or missing")
                }

            } catch (e: CancellationException) {
                Log.d(TAG, "Download cancelled")
                withContext(Dispatchers.Main) {
                    sendErrorBroadcast("cancelled")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Download failed", e)
                withContext(Dispatchers.Main) {
                    sendErrorBroadcast(e.message ?: "unknown")
                    showErrorNotification(version, e.message ?: "下载失败")
                }
            } finally {
                withContext(Dispatchers.Main) {
                    stopSelf()
                }
            }
        }
    }

    private fun cancelDownload() {
        downloadJob?.cancel()
        downloadJob = null
        
        // 删除未完成的文件
        currentFilePath?.let {
            try {
                val file = File(it)
                if (file.exists()) {
                    file.delete()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete incomplete file", e)
            }
        }
        
        sendErrorBroadcast("cancelled")
        stopSelf()
    }

    private fun sendProgressBroadcast(received: Long, total: Long) {
        sendBroadcast(Intent(BROADCAST_DOWNLOAD_PROGRESS).apply {
            setPackage(packageName)
            putExtra(EXTRA_PROGRESS, received)
            putExtra(EXTRA_TOTAL, total)
        })
    }

    private fun sendCompleteBroadcast(filePath: String) {
        sendBroadcast(Intent(BROADCAST_DOWNLOAD_COMPLETE).apply {
            setPackage(packageName)
            putExtra(EXTRA_FILE_PATH, filePath)
        })
    }

    private fun sendErrorBroadcast(error: String) {
        sendBroadcast(Intent(BROADCAST_DOWNLOAD_ERROR).apply {
            setPackage(packageName)
            putExtra(EXTRA_ERROR, error)
        })
    }

    private fun showCompleteNotification(version: String, filePath: String) {
        // 停止前台服务
        stopForeground(STOP_FOREGROUND_REMOVE)
        
        // 显示完成通知
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("下载完成")
            .setContentText("v$version 已下载完成，点击安装")
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID + 1, notification)
    }

    private fun showErrorNotification(version: String, error: String) {
        stopForeground(STOP_FOREGROUND_REMOVE)
        
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("下载失败")
            .setContentText("v$version 下载失败: $error")
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID + 2, notification)
    }
}
