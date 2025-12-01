package uno.skkk.icarus

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray

/**
 * 课程小组件的远程视图服务
 * 用于支持 ListView 滑动
 */
class CoursesWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        val isCompact = intent.getBooleanExtra(EXTRA_COMPACT_MODE, false)
        return CoursesRemoteViewsFactory(applicationContext, isCompact)
    }
    
    companion object {
        const val EXTRA_COMPACT_MODE = "compact_mode"
    }
}

/**
 * 课程列表的远程视图工厂
 */
class CoursesRemoteViewsFactory(
    private val context: Context,
    private val isCompact: Boolean = false
) : RemoteViewsService.RemoteViewsFactory {

    companion object {
        private const val PREFS_NAME = "HomeWidgetPreferences"
        private const val KEY_TODAY_COURSES = "today_courses"
    }

    private var courses: List<CourseItem> = emptyList()

    override fun onCreate() {
        loadData()
    }

    override fun onDataSetChanged() {
        loadData()
    }

    private fun loadData() {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val coursesJson = prefs.getString(KEY_TODAY_COURSES, "[]") ?: "[]"
            
            courses = try {
                val jsonArray = JSONArray(coursesJson)
                (0 until jsonArray.length()).map { i ->
                    val obj = jsonArray.getJSONObject(i)
                    CourseItem(
                        name = obj.optString("name", "未知课程"),
                        location = obj.optString("location", ""),
                        startSection = obj.optInt("startSection", 0),
                        endSection = obj.optInt("endSection", 0),
                        startTime = obj.optString("startTime", ""),
                        endTime = obj.optString("endTime", "")
                    )
                }
            } catch (e: Exception) {
                emptyList()
            }
        } catch (e: Exception) {
            courses = emptyList()
        }
    }

    override fun onDestroy() {
        courses = emptyList()
    }

    override fun getCount(): Int = courses.size

    override fun getViewAt(position: Int): RemoteViews {
        val layoutId = if (isCompact) {
            R.layout.widget_course_list_item_compact
        } else {
            R.layout.widget_course_list_item
        }
        val views = RemoteViews(context.packageName, layoutId)
        
        if (position < 0 || position >= courses.size) {
            return views
        }
        
        val course = courses[position]
        
        views.setTextViewText(R.id.course_name, course.name)
        views.setTextViewText(R.id.course_start_time, course.startTime.ifEmpty { "--:--" })
        
        if (isCompact) {
            // 紧凑模式：简化节次显示
            views.setTextViewText(R.id.course_section, "${course.startSection}-${course.endSection}")
        } else {
            // 正常模式：显示完整信息
            views.setTextViewText(R.id.course_location, course.location.ifEmpty { "未知地点" })
            views.setTextViewText(R.id.course_end_time, course.endTime.ifEmpty { "--:--" })
            views.setTextViewText(R.id.course_section, "${course.startSection}-${course.endSection}节")
        }
        
        // 设置点击填充 Intent
        val fillInIntent = Intent()
        views.setOnClickFillInIntent(R.id.course_list_item_container, fillInIntent)
        
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 2

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true
}
