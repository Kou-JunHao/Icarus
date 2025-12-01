package uno.skkk.icarus

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.SystemClock
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "uno.skkk.icarus/update"
        private const val STORAGE_PERMISSION_CODE = 100
        private const val NOTIFICATION_PERMISSION_CODE = 101
        private const val DOWNLOAD_FOLDER_NAME = "Icarus"
        
        // 通知相关
        private const val NOTIFICATION_CHANNEL_ID = "download_channel"
        private const val NOTIFICATION_CHANNEL_NAME = "下载通知"
        private const val DOWNLOAD_NOTIFICATION_ID = 1001
        
        // 通知取消广播
        private const val ACTION_NOTIFICATION_DISMISSED = "uno.skkk.icarus.NOTIFICATION_DISMISSED"
    }

    private var notificationManager: NotificationManager? = null
    private var downloadStartTime: Long = 0
    private var notificationDismissedReceiver: BroadcastReceiver? = null
    private var isNotificationDismissed: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 初始化通知管理器
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()
        registerNotificationDismissedReceiver()
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDownloadDir" -> {
                    val dir = getApkDownloadDirectory()
                    Log.d(TAG, "getDownloadDir: $dir")
                    result.success(dir)
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        val success = installApk(filePath)
                        result.success(success)
                    } else {
                        result.error("INVALID_ARGUMENT", "File path is required", null)
                    }
                }
                "clearApkCache" -> {
                    val success = clearApkFiles()
                    result.success(success)
                }
                "requestStoragePermission" -> {
                    val granted = requestStoragePermission()
                    result.success(granted)
                }
                "checkStoragePermission" -> {
                    val granted = checkStoragePermission()
                    result.success(granted)
                }
                "showDownloadNotification" -> {
                    val progress = call.argument<Int>("progress") ?: 0
                    val total = call.argument<Int>("total") ?: 100
                    val title = call.argument<String>("title") ?: "正在下载更新"
                    val content = call.argument<String>("content") ?: ""
                    showDownloadProgress(progress, total, title, content)
                    result.success(true)
                }
                "updateDownloadNotification" -> {
                    val progress = call.argument<Int>("progress") ?: 0
                    val total = call.argument<Int>("total") ?: 100
                    val title = call.argument<String>("title") ?: "正在下载更新"
                    val content = call.argument<String>("content") ?: ""
                    updateDownloadProgress(progress, total, title, content)
                    result.success(true)
                }
                "completeDownloadNotification" -> {
                    val filePath = call.argument<String>("filePath")
                    val title = call.argument<String>("title") ?: "下载完成"
                    val content = call.argument<String>("content") ?: "点击安装"
                    completeDownload(filePath, title, content)
                    result.success(true)
                }
                "cancelDownloadNotification" -> {
                    cancelDownloadNotification()
                    result.success(true)
                }
                "checkNotificationPermission" -> {
                    result.success(checkNotificationPermission())
                }
                "requestNotificationPermission" -> {
                    requestNotificationPermission()
                    result.success(true)
                }
                "startDownloadService" -> {
                    val url = call.argument<String>("url")
                    val filePath = call.argument<String>("filePath")
                    val version = call.argument<String>("version") ?: "未知"
                    val fileSize = call.argument<Number>("fileSize")?.toLong() ?: 0L
                    
                    if (url != null && filePath != null) {
                        startDownloadService(url, filePath, version, fileSize)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "URL and filePath are required", null)
                    }
                }
                "cancelDownloadService" -> {
                    cancelDownloadService()
                    result.success(true)
                }
                "isDownloadServiceRunning" -> {
                    result.success(DownloadService.isRunning)
                }
                "getLastDownloadError" -> {
                    // 返回最后的下载错误信息
                    if (lastDownloadErrorType != null) {
                        result.success(mapOf(
                            "error" to lastDownloadError,
                            "errorType" to lastDownloadErrorType
                        ))
                        // 返回后清除错误状态
                        lastDownloadError = null
                        lastDownloadErrorType = null
                    } else {
                        result.success(null)
                    }
                }
                "isDownloadCompleted" -> {
                    // 检查下载是否成功完成
                    if (downloadCompleted) {
                        result.success(mapOf(
                            "completed" to true,
                            "filePath" to completedFilePath
                        ))
                        // 返回后清除状态
                        downloadCompleted = false
                        completedFilePath = null
                    } else {
                        result.success(null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        // 注册下载服务广播接收器
        registerDownloadServiceReceiver()
    }
    
    private var downloadServiceReceiver: BroadcastReceiver? = null
    private var flutterMethodChannel: MethodChannel? = null
    
    // 存储最后的下载状态信息
    private var lastDownloadError: String? = null
    private var lastDownloadErrorType: String? = null
    private var downloadCompleted: Boolean = false
    private var completedFilePath: String? = null
    
    private fun registerDownloadServiceReceiver() {
        downloadServiceReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    DownloadService.BROADCAST_DOWNLOAD_PROGRESS -> {
                        val progress = intent.getLongExtra(DownloadService.EXTRA_PROGRESS, 0)
                        val total = intent.getLongExtra(DownloadService.EXTRA_TOTAL, 0)
                        // 清除错误状态
                        lastDownloadError = null
                        lastDownloadErrorType = null
                        downloadCompleted = false
                        Log.d(TAG, "Download progress: $progress / $total")
                    }
                    DownloadService.BROADCAST_DOWNLOAD_COMPLETE -> {
                        val filePath = intent.getStringExtra(DownloadService.EXTRA_FILE_PATH)
                        // 标记下载完成
                        downloadCompleted = true
                        completedFilePath = filePath
                        lastDownloadError = null
                        lastDownloadErrorType = null
                        Log.d(TAG, "Download complete: $filePath")
                    }
                    DownloadService.BROADCAST_DOWNLOAD_ERROR -> {
                        val error = intent.getStringExtra(DownloadService.EXTRA_ERROR)
                        val errorType = intent.getStringExtra(DownloadService.EXTRA_ERROR_TYPE)
                        // 存储错误信息以供 Flutter 查询
                        lastDownloadError = error
                        lastDownloadErrorType = errorType
                        Log.d(TAG, "Download error: $error, type: $errorType")
                    }
                }
            }
        }
        
        val filter = IntentFilter().apply {
            addAction(DownloadService.BROADCAST_DOWNLOAD_PROGRESS)
            addAction(DownloadService.BROADCAST_DOWNLOAD_COMPLETE)
            addAction(DownloadService.BROADCAST_DOWNLOAD_ERROR)
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(downloadServiceReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(downloadServiceReceiver, filter)
        }
    }
    
    /**
     * 启动下载服务
     */
    private fun startDownloadService(url: String, filePath: String, version: String, fileSize: Long) {
        val intent = Intent(this, DownloadService::class.java).apply {
            action = DownloadService.ACTION_START_DOWNLOAD
            putExtra(DownloadService.EXTRA_URL, url)
            putExtra(DownloadService.EXTRA_FILE_PATH, filePath)
            putExtra(DownloadService.EXTRA_VERSION, version)
            putExtra(DownloadService.EXTRA_FILE_SIZE, fileSize)
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        Log.d(TAG, "Download service started")
    }
    
    /**
     * 取消下载服务
     */
    private fun cancelDownloadService() {
        val intent = Intent(this, DownloadService::class.java).apply {
            action = DownloadService.ACTION_CANCEL_DOWNLOAD
        }
        startService(intent)
        Log.d(TAG, "Download service cancelled")
    }

    /**
     * 创建通知渠道
     */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                NOTIFICATION_CHANNEL_NAME,
                importance
            ).apply {
                description = "显示下载进度"
                setShowBadge(false)
            }
            notificationManager?.createNotificationChannel(channel)
        }
    }

    /**
     * 注册通知取消广播接收器
     */
    private fun registerNotificationDismissedReceiver() {
        notificationDismissedReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == ACTION_NOTIFICATION_DISMISSED) {
                    Log.d(TAG, "用户划掉了下载通知")
                    isNotificationDismissed = true
                }
            }
        }
        val filter = IntentFilter(ACTION_NOTIFICATION_DISMISSED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(notificationDismissedReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(notificationDismissedReceiver, filter)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        notificationDismissedReceiver?.let {
            unregisterReceiver(it)
        }
        downloadServiceReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to unregister download service receiver", e)
            }
        }
    }

    /**
     * 检查通知权限
     */
    private fun checkNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            NotificationManagerCompat.from(this).areNotificationsEnabled()
        }
    }

    /**
     * 请求通知权限
     */
    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (!checkNotificationPermission()) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_CODE
                )
            }
        }
    }

    /**
     * 显示下载进度通知
     */
    private fun showDownloadProgress(progress: Int, total: Int, title: String, content: String) {
        // 记录下载开始时间
        downloadStartTime = SystemClock.elapsedRealtime()
        isNotificationDismissed = false
        
        val builder = createProgressNotificationBuilder(progress, total, title, content)
        
        if (checkNotificationPermission()) {
            notificationManager?.notify(DOWNLOAD_NOTIFICATION_ID, builder.build())
        }
    }

    /**
     * 更新下载进度通知
     */
    private fun updateDownloadProgress(progress: Int, total: Int, title: String, content: String) {
        // 如果用户划掉了通知，不再更新
        if (isNotificationDismissed) {
            Log.d(TAG, "通知已被用户划掉，跳过更新")
            return
        }
        
        val builder = createProgressNotificationBuilder(progress, total, title, content)
        
        if (checkNotificationPermission()) {
            notificationManager?.notify(DOWNLOAD_NOTIFICATION_ID, builder.build())
        }
    }

    /**
     * 创建进度通知构建器
     * 支持 Android 16+ (API 36+) 的状态栏条状标签 (Live Updates / ProgressStyle)
     * 
     * 状态条状标签功能:
     * - setShortCriticalText: 在状态栏显示简短关键文本（最多7字符最佳）
     * - setWhen + setChronometerCountDown: 显示倒计时时间
     * - ProgressStyle: 带有进度点和分段的进度样式
     * - setRequestPromotedOngoing: 请求将通知提升为"进行中"状态
     * 
     * 状态条状标签外观规则:
     * - 始终包含一个图标
     * - 最大宽度 96dp
     * - 少于7个字符：显示整个文本
     * - 超过一半文字可显示：尽可能显示更多文字
     * - 不到一半文字可显示：仅显示图标
     */
    private fun createProgressNotificationBuilder(
        progress: Int,
        total: Int,
        title: String,
        content: String
    ): NotificationCompat.Builder {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 创建删除（划掉）通知的 PendingIntent
        // 使用 setDeleteIntent 检测已关闭的更新，避免重新发布用户已关闭的通知
        val deleteIntent = Intent(ACTION_NOTIFICATION_DISMISSED)
        val deletePendingIntent = PendingIntent.getBroadcast(
            this,
            0,
            deleteIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // 计算百分比用于状态栏显示
        val percent = if (total > 0) (progress * 100 / total) else 0
        
        val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(content)
            .setContentIntent(pendingIntent)
            .setDeleteIntent(deletePendingIntent) // 监听通知被划掉，防止用户完全停用实时更新
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setAutoCancel(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setWhen(System.currentTimeMillis() - (SystemClock.elapsedRealtime() - downloadStartTime))
            .setUsesChronometer(true) // 显示计时器（已用时间）
            .setShowWhen(true)

        // Android 16+ (API 36) 使用 ProgressStyle 和状态栏条状标签
        if (Build.VERSION.SDK_INT >= 36) {
            try {
                // 设置状态栏条状标签文本 - 显示百分比
                // 状态条状标签规则：少于7个字符显示整个文本
                builder.setShortCriticalText("$percent%")
                
                // 请求将通知提升为"进行中"状态
                builder.setRequestPromotedOngoing(true)
                
                // 创建 ProgressStyle 进度样式
                val progressStyle = createProgressStyle(percent)
                if (progressStyle != null) {
                    builder.setStyle(progressStyle)
                    Log.d(TAG, "已设置 ProgressStyle，进度: $percent%")
                }
                
                Log.d(TAG, "已设置状态栏条状标签: $percent%")
            } catch (e: Exception) {
                Log.d(TAG, "Android 16 ProgressStyle 设置失败: ${e.message}")
                // 回退到普通进度条
                if (total > 0) {
                    builder.setProgress(total, progress, false)
                } else {
                    builder.setProgress(0, 0, true)
                }
            }
        } else {
            // Android 16 以下使用普通进度条
            if (total > 0) {
                builder.setProgress(total, progress, false)
            } else {
                builder.setProgress(0, 0, true)
            }
        }

        return builder
    }

    /**
     * 创建 Android 16+ ProgressStyle
     * 带有进度点和分段的进度样式
     */
    private fun createProgressStyle(percent: Int): NotificationCompat.ProgressStyle? {
        if (Build.VERSION.SDK_INT < 36) return null
        
        return try {
            // 进度点颜色 - 浅紫色
            val pointColor = Color.valueOf(
                236f / 255f,
                183f / 255f,
                255f / 255f,
                1f
            ).toArgb()
            
            // 分段颜色 - 浅青色
            val segmentColor = Color.valueOf(
                134f / 255f,
                247f / 255f,
                250f / 255f,
                1f
            ).toArgb()
            
            val progressStyle = NotificationCompat.ProgressStyle()
            
            // 设置进度分段（每25%一段）
            progressStyle.setProgressSegments(
                listOf(
                    NotificationCompat.ProgressStyle.Segment(25).setColor(segmentColor),
                    NotificationCompat.ProgressStyle.Segment(25).setColor(segmentColor),
                    NotificationCompat.ProgressStyle.Segment(25).setColor(segmentColor),
                    NotificationCompat.ProgressStyle.Segment(25).setColor(segmentColor)
                )
            )
            
            // 根据进度设置已完成的进度点
            val completedPoints = mutableListOf<NotificationCompat.ProgressStyle.Point>()
            if (percent >= 25) {
                completedPoints.add(NotificationCompat.ProgressStyle.Point(25).setColor(pointColor))
            }
            if (percent >= 50) {
                completedPoints.add(NotificationCompat.ProgressStyle.Point(50).setColor(pointColor))
            }
            if (percent >= 75) {
                completedPoints.add(NotificationCompat.ProgressStyle.Point(75).setColor(pointColor))
            }
            if (percent >= 100) {
                completedPoints.add(NotificationCompat.ProgressStyle.Point(100).setColor(pointColor))
            }
            
            if (completedPoints.isNotEmpty()) {
                progressStyle.setProgressPoints(completedPoints)
            }
            
            // 设置当前进度
            progressStyle.setProgress(percent)
            
            // 设置进度追踪图标
            progressStyle.setProgressTrackerIcon(
                IconCompat.createWithResource(this, android.R.drawable.stat_sys_download)
            )
            
            progressStyle
        } catch (e: Exception) {
            Log.d(TAG, "创建 ProgressStyle 失败: ${e.message}")
            null
        }
    }

    /**
     * 下载完成通知
     * 使用 setShortCriticalText 显示 "完成" 状态
     */
    private fun completeDownload(filePath: String?, title: String, content: String) {
        val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(title)
            .setContentText(content)
            .setOngoing(false)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
        
        // Android 16+ 设置完成状态的条状标签
        if (Build.VERSION.SDK_INT >= 36) {
            try {
                builder.setShortCriticalText("完成")
                
                // 创建完成状态的 ProgressStyle
                val progressStyle = NotificationCompat.ProgressStyle()
                    .setProgress(100)
                    .setProgressTrackerIcon(
                        IconCompat.createWithResource(this, android.R.drawable.stat_sys_download_done)
                    )
                builder.setStyle(progressStyle)
            } catch (e: Exception) {
                Log.d(TAG, "设置完成通知 ProgressStyle 失败: ${e.message}")
            }
        }

        // 如果有文件路径，点击可安装
        if (filePath != null) {
            val file = File(filePath)
            if (file.exists()) {
                val intent = Intent(Intent.ACTION_VIEW)
                intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                
                val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    FileProvider.getUriForFile(
                        this,
                        "${applicationContext.packageName}.fileprovider",
                        file
                    )
                } else {
                    Uri.fromFile(file)
                }
                intent.setDataAndType(uri, "application/vnd.android.package-archive")
                
                val pendingIntent = PendingIntent.getActivity(
                    this,
                    0,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                builder.setContentIntent(pendingIntent)
                
                // Android 16+ 添加安装操作按钮
                if (Build.VERSION.SDK_INT >= 36) {
                    builder.addAction(
                        NotificationCompat.Action.Builder(null, "安装", pendingIntent).build()
                    )
                }
            }
        }

        if (checkNotificationPermission()) {
            notificationManager?.notify(DOWNLOAD_NOTIFICATION_ID, builder.build())
        }
    }

    /**
     * 取消下载通知
     */
    private fun cancelDownloadNotification() {
        notificationManager?.cancel(DOWNLOAD_NOTIFICATION_ID)
        isNotificationDismissed = false
        downloadStartTime = 0
    }

    /**
     * 检查存储权限
     */
    private fun checkStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ 不需要存储权限来访问应用创建的文件
            true
        } else {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    /**
     * 请求存储权限
     */
    private fun requestStoragePermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ 不需要存储权限
            return true
        }
        
        if (checkStoragePermission()) {
            return true
        }
        
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            STORAGE_PERMISSION_CODE
        )
        return false
    }

    /**
     * 获取 APK 下载目录
     * 返回: /storage/emulated/0/Download/Icarus/
     * 
     * 兼容 Android 8-16
     */
    private fun getApkDownloadDirectory(): String? {
        return try {
            // 获取公共 Download 目录
            val downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val appDownloadDir = File(downloadDir, DOWNLOAD_FOLDER_NAME)
            
            // 确保目录存在
            if (!appDownloadDir.exists()) {
                val created = appDownloadDir.mkdirs()
                Log.d(TAG, "创建目录: ${appDownloadDir.absolutePath}, 结果: $created")
                if (!created) {
                    // 如果无法创建公共目录，回退到应用私有目录
                    Log.w(TAG, "无法创建公共下载目录，使用应用私有目录")
                    return getExternalFilesDir(null)?.absolutePath ?: filesDir.absolutePath
                }
            }
            
            Log.d(TAG, "下载目录: ${appDownloadDir.absolutePath}")
            appDownloadDir.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "获取下载目录失败", e)
            // 回退到应用私有目录
            getExternalFilesDir(null)?.absolutePath ?: filesDir.absolutePath
        }
    }

    /**
     * 安装 APK 文件
     * 公共目录的文件可以被任何安装器访问
     */
    private fun installApk(filePath: String): Boolean {
        return try {
            val file = File(filePath)
            if (!file.exists()) {
                Log.e(TAG, "APK 文件不存在: $filePath")
                return false
            }

            Log.d(TAG, "准备安装 APK: $filePath, 大小: ${file.length()} bytes")

            val intent = Intent(Intent.ACTION_VIEW)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK

            // 判断文件是否在公共目录
            val isPublicDir = filePath.contains("/Download/")
            
            val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // Android 7.0+ 统一使用 FileProvider
                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                FileProvider.getUriForFile(
                    this,
                    "${applicationContext.packageName}.fileprovider",
                    file
                )
            } else {
                // Android 6.0 及以下直接使用 file:// URI
                Uri.fromFile(file)
            }

            Log.d(TAG, "安装 URI: $uri, 公共目录: $isPublicDir")
            intent.setDataAndType(uri, "application/vnd.android.package-archive")
            startActivity(intent)
            
            // 取消下载通知
            cancelDownloadNotification()
            
            true
        } catch (e: Exception) {
            Log.e(TAG, "安装 APK 失败", e)
            false
        }
    }

    /**
     * 清理下载的 APK 文件
     */
    private fun clearApkFiles(): Boolean {
        return try {
            var deletedCount = 0
            
            // 清理公共 Download/Icarus 目录中的 APK
            val downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val appDownloadDir = File(downloadDir, DOWNLOAD_FOLDER_NAME)
            if (appDownloadDir.exists()) {
                appDownloadDir.listFiles()?.forEach { file ->
                    if (file.isFile && file.name.endsWith(".apk")) {
                        if (file.delete()) {
                            deletedCount++
                            Log.d(TAG, "已删除: ${file.absolutePath}")
                        }
                    }
                }
            }
            
            // 清理应用私有目录中的 APK（兼容旧版本）
            val externalFilesDir = getExternalFilesDir(null)
            if (externalFilesDir != null && externalFilesDir.exists()) {
                externalFilesDir.listFiles()?.forEach { file ->
                    if (file.isFile && file.name.endsWith(".apk")) {
                        if (file.delete()) {
                            deletedCount++
                            Log.d(TAG, "已删除: ${file.absolutePath}")
                        }
                    }
                }
            }
            
            Log.d(TAG, "共删除 $deletedCount 个 APK 文件")
            true
        } catch (e: Exception) {
            Log.e(TAG, "清理 APK 文件失败", e)
            false
        }
    }
}
