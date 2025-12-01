package uno.skkk.icarus

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray

/**
 * 作业小组件的远程视图服务
 * 用于支持 ListView 滑动
 */
class WorksWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        val isCompact = intent.getBooleanExtra(EXTRA_COMPACT_MODE, false)
        return WorksRemoteViewsFactory(applicationContext, isCompact)
    }
    
    companion object {
        const val EXTRA_COMPACT_MODE = "compact_mode"
    }
}

/**
 * 作业列表的远程视图工厂
 */
class WorksRemoteViewsFactory(
    private val context: Context,
    private val isCompact: Boolean = false
) : RemoteViewsService.RemoteViewsFactory {

    companion object {
        private const val PREFS_NAME = "HomeWidgetPreferences"
        private const val KEY_PENDING_WORKS = "pending_works"
    }

    private var works: List<WorkItem> = emptyList()

    override fun onCreate() {
        loadData()
    }

    override fun onDataSetChanged() {
        loadData()
    }

    private fun loadData() {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val worksJson = prefs.getString(KEY_PENDING_WORKS, "[]") ?: "[]"
            
            works = try {
                val jsonArray = JSONArray(worksJson)
                (0 until jsonArray.length()).mapNotNull { i ->
                    val obj = jsonArray.getJSONObject(i)
                    val isOverdue = obj.optBoolean("isOverdue", false)
                    // 过滤掉已超时作业
                    if (isOverdue) {
                        null
                    } else {
                        WorkItem(
                            name = obj.optString("name", "未知作业"),
                            courseName = obj.optString("courseName", ""),
                            remainingTime = obj.optString("remainingTime", ""),
                            isUrgent = obj.optBoolean("isUrgent", false),
                            isOverdue = false
                        )
                    }
                }.sortedWith(compareBy(
                    // 紧急作业优先
                    { !it.isUrgent },
                    // 按剩余时间排序
                    { parseRemainingTimeToMinutes(it.remainingTime) }
                ))
            } catch (e: Exception) {
                emptyList()
            }
        } catch (e: Exception) {
            works = emptyList()
        }
    }

    /**
     * 将剩余时间字符串解析为分钟数
     */
    private fun parseRemainingTimeToMinutes(time: String): Int {
        if (time.isEmpty() || time == "未设置截止时间") {
            return 999999 // 无截止时间放到最后
        }

        var totalMinutes = 0

        // 解析天数
        val daysPattern = Regex("(\\d+)\\s*天")
        daysPattern.find(time)?.let {
            totalMinutes += (it.groupValues[1].toIntOrNull() ?: 0) * 24 * 60
        }

        // 解析小时数
        val hoursPattern = Regex("(\\d+)\\s*小时")
        hoursPattern.find(time)?.let {
            totalMinutes += (it.groupValues[1].toIntOrNull() ?: 0) * 60
        }

        // 解析分钟数
        val minutesPattern = Regex("(\\d+)\\s*分钟?")
        minutesPattern.find(time)?.let {
            totalMinutes += it.groupValues[1].toIntOrNull() ?: 0
        }

        return totalMinutes
    }

    override fun onDestroy() {
        works = emptyList()
    }

    override fun getCount(): Int = works.size

    override fun getViewAt(position: Int): RemoteViews {
        val layoutId = if (isCompact) {
            R.layout.widget_work_list_item_compact
        } else {
            R.layout.widget_work_list_item
        }
        val views = RemoteViews(context.packageName, layoutId)
        
        if (position < 0 || position >= works.size) {
            return views
        }
        
        val work = works[position]
        
        views.setTextViewText(R.id.work_name, work.name)
        views.setTextViewText(R.id.work_time, formatRemainingTime(work.remainingTime, isCompact))
        
        if (!isCompact) {
            // 正常模式：显示课程名
            views.setTextViewText(R.id.work_course, work.courseName.ifEmpty { "未知课程" })
        }
        
        // 显示/隐藏紧急图标（只有紧急作业显示）
        if (work.isUrgent) {
            views.setViewVisibility(R.id.work_urgent_icon, android.view.View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.work_urgent_icon, android.view.View.GONE)
        }
        
        // 设置点击填充 Intent
        val fillInIntent = Intent()
        views.setOnClickFillInIntent(R.id.work_list_item_container, fillInIntent)
        
        return views
    }

    private fun formatRemainingTime(time: String, compact: Boolean = false): String {
        if (time.isEmpty() || time == "未设置截止时间") {
            return if (compact) "-" else "无截止"
        }
        val formatted = time.replace("剩余", "").replace("时间", "").trim()
        // 紧凑模式下进一步简化
        if (compact) {
            return formatted
                .replace("小时", "h")
                .replace("分钟", "m")
                .replace("天", "d")
                .replace(" ", "")
        }
        return formatted
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 2

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = true
}
