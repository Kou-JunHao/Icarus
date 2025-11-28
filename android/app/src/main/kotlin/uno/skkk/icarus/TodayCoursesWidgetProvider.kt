package uno.skkk.icarus

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * 今日课程小组件 Provider
 */
class TodayCoursesWidgetProvider : AppWidgetProvider() {

    companion object {
        private const val PREFS_NAME = "HomeWidgetPreferences"
        private const val KEY_TODAY_COURSES = "today_courses"
        private const val KEY_CURRENT_WEEK = "current_week"
        private const val KEY_LAST_UPDATE = "last_update"
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

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val views = RemoteViews(context.packageName, R.layout.today_courses_widget)
        
        // 获取数据
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val coursesJson = prefs.getString(KEY_TODAY_COURSES, "[]") ?: "[]"
        val currentWeek = prefs.getInt(KEY_CURRENT_WEEK, 1)
        val lastUpdate = prefs.getString(KEY_LAST_UPDATE, "") ?: ""
        
        // 设置周次
        views.setTextViewText(R.id.widget_week, "第${currentWeek}周")
        
        // 设置更新时间
        val updateTimeText = if (lastUpdate.isNotEmpty()) {
            try {
                val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.getDefault())
                val date = dateFormat.parse(lastUpdate.substringBefore("."))
                val displayFormat = SimpleDateFormat("HH:mm 更新", Locale.getDefault())
                displayFormat.format(date!!)
            } catch (e: Exception) {
                "点击打开应用"
            }
        } else {
            "点击打开应用"
        }
        views.setTextViewText(R.id.widget_update_time, updateTimeText)
        
        // 解析课程数据
        val courses = try {
            val jsonArray = JSONArray(coursesJson)
            (0 until jsonArray.length()).map { i ->
                val obj = jsonArray.getJSONObject(i)
                CourseItem(
                    name = obj.getString("name"),
                    location = obj.optString("location", ""),
                    startSection = obj.getInt("startSection"),
                    endSection = obj.getInt("endSection"),
                    startTime = obj.optString("startTime", ""),
                    endTime = obj.optString("endTime", "")
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
        
        // 显示/隐藏空状态
        if (courses.isEmpty()) {
            views.setViewVisibility(R.id.courses_container, View.GONE)
            views.setViewVisibility(R.id.empty_view, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.courses_container, View.VISIBLE)
            views.setViewVisibility(R.id.empty_view, View.GONE)
            
            // 隐藏所有课程项，然后显示有数据的
            views.setViewVisibility(R.id.course_item_1, View.GONE)
            views.setViewVisibility(R.id.course_item_2, View.GONE)
            views.setViewVisibility(R.id.course_item_3, View.GONE)
            views.setViewVisibility(R.id.more_courses, View.GONE)
            
            // 填充课程数据（最多显示3节课）
            val maxDisplay = minOf(courses.size, 3)
            for (i in 0 until maxDisplay) {
                val course = courses[i]
                when (i) {
                    0 -> {
                        views.setViewVisibility(R.id.course_item_1, View.VISIBLE)
                        views.setTextViewText(R.id.course_1_name, course.name)
                        views.setTextViewText(R.id.course_1_location, course.location.ifEmpty { "未知地点" })
                        views.setTextViewText(R.id.course_1_start_time, course.startTime.ifEmpty { "--:--" })
                        views.setTextViewText(R.id.course_1_end_time, course.endTime.ifEmpty { "--:--" })
                        views.setTextViewText(R.id.course_1_section, "${course.startSection}-${course.endSection}节")
                    }
                    1 -> {
                        views.setViewVisibility(R.id.course_item_2, View.VISIBLE)
                        views.setTextViewText(R.id.course_2_name, course.name)
                        views.setTextViewText(R.id.course_2_location, course.location.ifEmpty { "未知地点" })
                        views.setTextViewText(R.id.course_2_start_time, course.startTime.ifEmpty { "--:--" })
                        views.setTextViewText(R.id.course_2_end_time, course.endTime.ifEmpty { "--:--" })
                        views.setTextViewText(R.id.course_2_section, "${course.startSection}-${course.endSection}节")
                    }
                    2 -> {
                        views.setViewVisibility(R.id.course_item_3, View.VISIBLE)
                        views.setTextViewText(R.id.course_3_name, course.name)
                        views.setTextViewText(R.id.course_3_location, course.location.ifEmpty { "未知地点" })
                        views.setTextViewText(R.id.course_3_start_time, course.startTime.ifEmpty { "--:--" })
                        views.setTextViewText(R.id.course_3_end_time, course.endTime.ifEmpty { "--:--" })
                        views.setTextViewText(R.id.course_3_section, "${course.startSection}-${course.endSection}节")
                    }
                }
            }
            
            // 如果还有更多课程，显示提示
            if (courses.size > 3) {
                views.setViewVisibility(R.id.more_courses, View.VISIBLE)
                views.setTextViewText(R.id.more_courses, "还有 ${courses.size - 3} 节课...")
            }
        }
        
        // 设置点击事件 - 打开应用
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pendingIntent = android.app.PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)
        
        // 更新小组件
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    override fun onEnabled(context: Context) {
        // 小组件首次添加
    }

    override fun onDisabled(context: Context) {
        // 最后一个小组件被移除
    }
}

/**
 * 课程数据类
 */
data class CourseItem(
    val name: String,
    val location: String,
    val startSection: Int,
    val endSection: Int,
    val startTime: String,
    val endTime: String
)
