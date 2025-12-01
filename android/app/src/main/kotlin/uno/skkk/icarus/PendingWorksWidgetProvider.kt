package uno.skkk.icarus

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * 未提交作业小组件 Provider
 * 支持莫奈动态取色、响应式布局和列表滑动
 */
class PendingWorksWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val PREFS_NAME = "HomeWidgetPreferences"
        private const val KEY_PENDING_WORKS = "pending_works"
        private const val KEY_WORKS_COUNT = "works_count"
        private const val KEY_WORKS_LAST_UPDATE = "works_last_update"
        private const val KEY_WORKS_NEED_LOGIN = "works_need_login"
        const val ACTION_REFRESH = "uno.skkk.icarus.ACTION_REFRESH_WORKS"
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle?
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        updateAppWidget(context, appWidgetManager, appWidgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        
        if (intent.action == ACTION_REFRESH || 
            intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, PendingWorksWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            
            // 通知数据变更
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.works_list)
            
            for (appWidgetId in appWidgetIds) {
                updateAppWidget(context, appWidgetManager, appWidgetId)
            }
        }
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        try {
            val views = RemoteViews(context.packageName, R.layout.pending_works_widget)
            
            // 获取小组件尺寸，判断是否使用紧凑模式
            val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
            val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 200)
            val isCompact = minWidth < 200 // 小于200dp使用紧凑模式
            
            // 获取数据
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val worksJson = prefs.getString(KEY_PENDING_WORKS, null)
            val worksCount = prefs.getInt(KEY_WORKS_COUNT, 0)
            val lastUpdate = prefs.getString(KEY_WORKS_LAST_UPDATE, null)
            val needLogin = prefs.getBoolean(KEY_WORKS_NEED_LOGIN, true)
            
            // 设置作业数量
            views.setTextViewText(R.id.widget_count, "$worksCount 项")
            
            // 设置更新时间
            val updateTimeText = formatUpdateTime(lastUpdate)
            views.setTextViewText(R.id.widget_update_time, updateTimeText)
            
            // 判断显示状态
            if (needLogin) {
                // 显示需要登录的提示
                views.setViewVisibility(R.id.works_list, View.GONE)
                views.setViewVisibility(R.id.empty_view, View.GONE)
                views.setViewVisibility(R.id.login_view, View.VISIBLE)
            } else {
                views.setViewVisibility(R.id.login_view, View.GONE)
                
                // 解析作业数据
                val works = parseWorks(worksJson)
                
                if (works.isEmpty()) {
                    // 没有未交作业
                    views.setViewVisibility(R.id.works_list, View.GONE)
                    views.setViewVisibility(R.id.empty_view, View.VISIBLE)
                } else {
                    // 有作业，显示列表
                    views.setViewVisibility(R.id.empty_view, View.GONE)
                    views.setViewVisibility(R.id.works_list, View.VISIBLE)
                    
                    // 设置 ListView 适配器，传递紧凑模式参数
                    val serviceIntent = Intent(context, WorksWidgetService::class.java).apply {
                        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                        putExtra(WorksWidgetService.EXTRA_COMPACT_MODE, isCompact)
                        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
                    }
                    views.setRemoteAdapter(R.id.works_list, serviceIntent)
                    views.setEmptyView(R.id.works_list, R.id.empty_view)
                }
            }
            
            // 设置点击事件 - 打开应用
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val pendingIntent = android.app.PendingIntent.getActivity(
                    context,
                    appWidgetId + 1000, // 使用不同的 requestCode
                    launchIntent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)
                
                // 设置列表项点击模板
                views.setPendingIntentTemplate(R.id.works_list, pendingIntent)
            }
            
            // 更新小组件
            appWidgetManager.updateAppWidget(appWidgetId, views)
            
        } catch (e: Exception) {
            // 发生错误时显示登录状态
            try {
                val errorViews = RemoteViews(context.packageName, R.layout.pending_works_widget)
                errorViews.setViewVisibility(R.id.works_list, View.GONE)
                errorViews.setViewVisibility(R.id.empty_view, View.GONE)
                errorViews.setViewVisibility(R.id.login_view, View.VISIBLE)
                
                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                if (launchIntent != null) {
                    val pendingIntent = android.app.PendingIntent.getActivity(
                        context,
                        appWidgetId + 1000,
                        launchIntent,
                        android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                    )
                    errorViews.setOnClickPendingIntent(R.id.widget_container, pendingIntent)
                }
                
                appWidgetManager.updateAppWidget(appWidgetId, errorViews)
            } catch (innerE: Exception) {
                // 忽略内部错误
            }
        }
    }

    private fun formatUpdateTime(lastUpdate: String?): String {
        if (lastUpdate.isNullOrEmpty()) {
            return "点击刷新"
        }
        return try {
            val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault())
            val date = dateFormat.parse(lastUpdate.substringBefore("."))
            val displayFormat = SimpleDateFormat("HH:mm 更新", Locale.getDefault())
            displayFormat.format(date!!)
        } catch (e: Exception) {
            "点击刷新"
        }
    }

    private fun parseWorks(worksJson: String?): List<WorkItem> {
        if (worksJson.isNullOrEmpty()) return emptyList()
        return try {
            val jsonArray = JSONArray(worksJson)
            (0 until jsonArray.length()).map { i ->
                val obj = jsonArray.getJSONObject(i)
                WorkItem(
                    name = obj.optString("name", "未知作业"),
                    courseName = obj.optString("courseName", ""),
                    remainingTime = obj.optString("remainingTime", ""),
                    isUrgent = obj.optBoolean("isUrgent", false),
                    isOverdue = obj.optBoolean("isOverdue", false)
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    override fun onEnabled(context: Context) {
        // 小组件首次添加
    }

    override fun onDisabled(context: Context) {
        // 最后一个小组件被移除
    }
}

/**
 * 作业数据类
 */
data class WorkItem(
    val name: String,
    val courseName: String,
    val remainingTime: String,
    val isUrgent: Boolean,
    val isOverdue: Boolean
)
