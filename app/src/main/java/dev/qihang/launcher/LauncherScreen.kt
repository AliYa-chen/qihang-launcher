package dev.qihang.launcher

import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Full-bleed 3D canvas with native controls floating above the scene. */
class LauncherScreen(context: Context, private val gateway: VehicleGateway) : FrameLayout(context) {
    private val ink = Color.rgb(235, 241, 247)
    private val muted = Color.rgb(153, 168, 183)
    private val accent = Color.rgb(132, 217, 239)
    private val edge = Color.argb(110, 115, 145, 165)
    private val glass = Color.argb(235, 18, 27, 36)
    private val uiHandler = Handler(Looper.getMainLooper())
    private var sceneReady = false
    private var activePage = "home"

    /** Always fills the window. Showing native sheets never resizes this view. */
    val sceneContainer = FrameLayout(context).apply {
        id = View.generateViewId()
        setBackgroundColor(Color.rgb(18, 23, 31))
        contentDescription = "全屏三维车辆与环境"
    }

    private val clock = text("", 22f, ink)
    private var loadingOverlay: LoadingOverlay? = null
    private val notice = text("", 12f, ink).apply {
        gravity = Gravity.CENTER
        visibility = View.GONE
        setPadding(dp(16), dp(10), dp(16), dp(10))
        background = shape(Color.argb(220, 24, 36, 47), 18f)
    }
    private val sheetLayer = FrameLayout(context)
    private val dock = LinearLayout(context)
    private val tiles = linkedMapOf<String, ControlTile>()
    private val colorButtons = linkedMapOf<String, View>()
    private val cameraButtons = linkedMapOf<String, TextView>()
    private val navButtons = linkedMapOf<String, Pair<LinearLayout, IconView>>()
    private var diagnosticsText: TextView? = null
    private var sheet: View? = null
    private val stateListener: (VehicleState) -> Unit = { refresh(it) }
    private val hideNotice = Runnable { notice.animate().alpha(0f).setDuration(160).withEndAction { notice.visibility = View.GONE }.start() }
    private val tick = object : Runnable {
        override fun run() {
            clock.text = SimpleDateFormat("HH:mm", Locale.CHINA).format(Date())
            uiHandler.postDelayed(this, 30_000)
        }
    }

    init {
        setBackgroundColor(Color.rgb(14, 18, 24))
        addView(sceneContainer, LayoutParams(-1, -1))
        loadingOverlay = LoadingOverlay(context).also { addView(it, LayoutParams(-1, -1)) }
        addView(sheetLayer, LayoutParams(-1, -1))
        buildCornerStatus()
        buildDock()
        addView(dock, LayoutParams(dp(700), dp(68), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply { bottomMargin = dp(18) })
        addView(notice, LayoutParams(-2, -2, Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply { topMargin = dp(26) })
        gateway.addListener(stateListener)
        selectNav("home")
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        dock.layoutParams = (dock.layoutParams as LayoutParams).apply { width = minOf(dp(700), w - dp(48)) }
        sheet?.let { applySheetLayout(it, activePage in listOf("apps", "diagnostics")) }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        gateway.addListener(stateListener)
        uiHandler.removeCallbacks(tick)
        tick.run()
    }

    override fun onDetachedFromWindow() {
        uiHandler.removeCallbacks(tick)
        uiHandler.removeCallbacks(hideNotice)
        gateway.removeListener(stateListener)
        super.onDetachedFromWindow()
    }

    fun setSceneReady(ready: Boolean) {
        sceneReady = ready
        if (ready) {
            loadingOverlay?.let { overlay ->
                overlay.revealScene {
                    removeView(overlay)
                    if (loadingOverlay === overlay) loadingOverlay = null
                }
            }
        } else if (loadingOverlay == null) {
            loadingOverlay = LoadingOverlay(context).also { addView(it, 1, LayoutParams(-1, -1)) }
        }
        if (activePage == "diagnostics") updateDiagnostics()
    }

    fun showNotice(message: String) {
        if (message.isBlank()) return
        uiHandler.removeCallbacks(hideNotice)
        notice.animate().cancel()
        notice.text = message
        notice.visibility = View.VISIBLE
        notice.alpha = 1f
        uiHandler.postDelayed(hideNotice, 2600)
    }

    /** Allows Android back to close a sheet while keeping the 3D home alive. */
    fun dismissPanels(): Boolean {
        if (activePage == "home") return false
        selectNav("home")
        return true
    }

    fun refresh(state: VehicleState) {
        tiles["toggle_left_door"]?.update(state.leftDoor > .5f, "已打开", "已关闭")
        tiles["toggle_right_door"]?.update(state.rightDoor > .5f, "已打开", "已关闭")
        tiles["toggle_windows"]?.update(state.windows > .5f, "已降下", "已升起")
        tiles["toggle_trunk"]?.update(state.trunk > .5f, "已打开", "已关闭")
        tiles["toggle_lights"]?.update(state.lights, "已点亮", "已关闭")
        colorButtons.forEach { (hex, button) ->
            val selected = state.color.equals(hex, ignoreCase = true)
            button.background = shape(if (selected) Color.argb(220, 43, 67, 82) else Color.argb(145, 34, 46, 59), 14f, if (selected) accent else edge)
            button.isSelected = selected
        }
        cameraButtons.forEach { (preset, button) ->
            val selected = state.cameraPreset == preset
            button.background = shape(if (selected) Color.argb(230, 43, 67, 82) else Color.argb(145, 34, 46, 59), 14f, if (selected) accent else edge)
            button.setTextColor(if (selected) ink else muted)
            button.isSelected = selected
        }
        if (activePage == "diagnostics") updateDiagnostics()
    }

    private fun buildCornerStatus() {
        val status = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL; gravity = Gravity.END }
        clock.apply {
            setSingleLine(true)
            minWidth = dp(76)
            gravity = Gravity.END
        }
        status.addView(clock, LinearLayout.LayoutParams(-2, -2).apply { gravity = Gravity.END })
        addView(status, LayoutParams(-2, -2, Gravity.TOP or Gravity.END).apply { rightMargin = dp(32); topMargin = dp(20) })
    }

    private fun buildDock() {
        dock.orientation = LinearLayout.HORIZONTAL
        dock.gravity = Gravity.CENTER_VERTICAL
        dock.setPadding(dp(10), dp(8), dp(10), dp(8))
        dock.background = shape(glass, 23f, edge)
        dock.elevation = dp(8).toFloat()
        listOf(
            Triple("home", "桌面", Glyph.HOME), Triple("vehicle", "车控", Glyph.CAR),
            Triple("apps", "应用", Glyph.APPS), Triple("diagnostics", "诊断", Glyph.DIAGNOSTICS),
        ).forEach { (key, label, glyph) ->
            val item = LinearLayout(context).apply {
                gravity = Gravity.CENTER; isClickable = true; isFocusable = true; contentDescription = label
                setPadding(dp(8), 0, dp(8), 0)
                setOnClickListener { selectNav(if (activePage == key && key != "home") "home" else key) }
            }
            val icon = IconView(context, glyph, muted)
            item.addView(icon, LinearLayout.LayoutParams(dp(22), dp(22)))
            item.addView(text(label, 13f, ink).apply { setPadding(dp(7), 0, 0, 0) })
            navButtons[key] = item to icon
            dock.addView(item, LinearLayout.LayoutParams(0, dp(52), 1f))
        }
    }

    private fun selectNav(page: String) {
        activePage = page
        navButtons.forEach { (key, views) ->
            val selected = key == page
            views.first.background = shape(if (selected) Color.argb(235, 45, 67, 81) else Color.TRANSPARENT, 15f)
            views.second.iconColor = if (selected) accent else muted
            views.first.isSelected = selected
        }
        sheetLayer.removeAllViews()
        sheet = null; diagnosticsText = null
        tiles.clear(); colorButtons.clear(); cameraButtons.clear()
        when (page) {
            "vehicle" -> showVehicleControls()
            "apps" -> showApps()
            "diagnostics" -> showDiagnostics()
        }
        refresh(gateway.state)
    }

    private fun sheetColumn(title: String, expanded: Boolean = false): LinearLayout {
        val col = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(12), dp(20), dp(18))
            background = shape(glass, 21f, edge)
            elevation = dp(10).toFloat()
            isClickable = true
        }
        val heading = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
        heading.addView(text(title, 14f, ink, true), LinearLayout.LayoutParams(0, -2, 1f))
        heading.addView(IconView(context, Glyph.CLOSE, muted).apply {
            isClickable = true; isFocusable = true; contentDescription = "收起面板"
            setOnClickListener { selectNav("home") }
        }, LinearLayout.LayoutParams(dp(48), dp(48)))
        col.addView(heading, LinearLayout.LayoutParams(-1, dp(48)).apply { bottomMargin = dp(8) })
        sheetLayer.addView(col)
        sheet = col
        applySheetLayout(col, expanded)
        col.alpha = 0f
        col.animate().alpha(1f).setDuration(140).start()
        return col
    }

    private fun applySheetLayout(view: View, expanded: Boolean) {
        val available = if (width > 0) width else resources.displayMetrics.widthPixels
        val wantedWidth = minOf(dp(if (expanded) 1000 else 900), available - dp(64))
        val wantedHeight = if (expanded) minOf(dp(440), (if (height > 0) height else resources.displayMetrics.heightPixels) - dp(160)) else -2
        view.layoutParams = LayoutParams(wantedWidth, wantedHeight, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply { bottomMargin = dp(101) }
    }

    private fun showVehicleControls() {
        val col = sheetColumn("车辆操控")
        val row = LinearLayout(context)
        listOf(
            Triple("toggle_left_door", "左前门", Glyph.DOOR_LEFT), Triple("toggle_right_door", "右前门", Glyph.DOOR_RIGHT),
            Triple("toggle_windows", "车窗", Glyph.WINDOW), Triple("toggle_trunk", "尾门", Glyph.TRUNK), Triple("toggle_lights", "灯光", Glyph.LIGHTS),
        ).forEachIndexed { i, (action, label, glyph) ->
            val tile = ControlTile(action, label, glyph)
            tiles[action] = tile
            row.addView(tile, LinearLayout.LayoutParams(0, dp(68), 1f).apply { if (i > 0) leftMargin = dp(9) })
        }
        col.addView(row, LinearLayout.LayoutParams(-1, -2))
        val secondary = LinearLayout(context)
        val colors = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        colors.addView(text("车身颜色", 11f, muted), LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(6) })
        addAppearanceControls(colors)
        secondary.addView(colors, LinearLayout.LayoutParams(0, -2, 1f).apply { rightMargin = dp(18) })
        val cameras = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        cameras.addView(text("观察视角", 11f, muted), LinearLayout.LayoutParams(-1, -2).apply { bottomMargin = dp(6) })
        addCameraControls(cameras)
        secondary.addView(cameras, LinearLayout.LayoutParams(0, -2, 1f))
        col.addView(secondary, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(13) })
    }

    private inner class ControlTile(private val action: String, label: String, glyph: Glyph) : LinearLayout(context) {
        private val status = text("", 11f, muted)
        private val icon = IconView(context, glyph, ink)
        init {
            orientation = VERTICAL; gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(14), dp(9), dp(12), dp(9))
            isClickable = true; isFocusable = true; contentDescription = label
            val top = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
            top.addView(icon, LayoutParams(dp(23), dp(23)))
            top.addView(text(label, 13f, ink).apply { setPadding(dp(8), 0, 0, 0) })
            addView(top, LayoutParams(-1, -2))
            addView(status, LayoutParams(-2, -2).apply { topMargin = dp(7) })
            setOnClickListener { gateway.request(action) }
        }
        fun update(active: Boolean, activeLabel: String, idleLabel: String) {
            val pending = action in gateway.pendingActions
            status.text = if (pending) "执行中…" else if (active) activeLabel else idleLabel
            status.setTextColor(if (active || pending) accent else muted)
            icon.iconColor = if (active) accent else ink
            isEnabled = !pending
            alpha = if (pending) .65f else 1f
            background = RippleDrawable(ColorStateList.valueOf(Color.argb(45, 132, 217, 239)), shape(if (active) Color.rgb(35, 58, 72) else Color.argb(150, 38, 50, 63), 13f, if (active) Color.rgb(71, 115, 137) else edge), null)
        }
    }

    private fun addAppearanceControls(col: LinearLayout) {
        val row = LinearLayout(context)
        listOf(Triple("#DCE5E9", "冰川白", "color_white"), Triple("#507A9C", "雾海蓝", "color_blue"), Triple("#7B8793", "星岩灰", "color_silver")).forEachIndexed { i, (hex, label, action) ->
            val chip = LinearLayout(context).apply {
                gravity = Gravity.CENTER; isClickable = true; isFocusable = true; contentDescription = "车色：$label"
                setOnClickListener { gateway.request(action) }
            }
            chip.addView(View(context).apply { background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(Color.parseColor(hex)) } }, LinearLayout.LayoutParams(dp(17), dp(17)).apply { rightMargin = dp(7) })
            chip.addView(text(label, 11f, ink))
            colorButtons[hex] = chip
            row.addView(chip, LinearLayout.LayoutParams(0, dp(48), 1f).apply { if (i > 0) leftMargin = dp(7) })
        }
        col.addView(row, LinearLayout.LayoutParams(-1, -2))
    }

    private fun addCameraControls(col: LinearLayout) {
        val row = LinearLayout(context)
        listOf("home" to "默认视角", "front" to "正前方", "side" to "侧面").forEachIndexed { i, (preset, label) ->
            val button = text(label, 12f, muted).apply {
                gravity = Gravity.CENTER; isClickable = true; isFocusable = true; contentDescription = label
                setOnClickListener { gateway.request("camera_$preset") }
            }
            cameraButtons[preset] = button
            row.addView(button, LinearLayout.LayoutParams(0, dp(48), 1f).apply { if (i > 0) leftMargin = dp(7) })
        }
        col.addView(row, LinearLayout.LayoutParams(-1, -2))
    }

    private fun showApps() {
        val col = sheetColumn("应用中心", expanded = true)
        val scroll = ScrollView(context).apply { isVerticalScrollBarEnabled = false }
        val grid = GridLayout(context).apply { columnCount = 5 }
        val pm = context.packageManager
        val apps = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
            .filter { it.activityInfo.packageName != context.packageName }
            .distinctBy { it.activityInfo.packageName }
            .sortedBy { it.loadLabel(pm).toString().lowercase(Locale.ROOT) }
        apps.forEach { app ->
            val item = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER; setPadding(dp(10), dp(12), dp(10), dp(12))
                background = shape(Color.argb(195, 33, 45, 58), 15f, edge); isClickable = true; isFocusable = true
                setOnClickListener {
                    try {
                        context.startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setClassName(app.activityInfo.packageName, app.activityInfo.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    } catch (_: Exception) { android.widget.Toast.makeText(context, "暂时无法打开这个应用", android.widget.Toast.LENGTH_SHORT).show() }
                }
            }
            item.addView(ImageView(context).apply { setImageDrawable(app.loadIcon(pm)); contentDescription = null }, LinearLayout.LayoutParams(dp(38), dp(38)))
            item.addView(text(app.loadLabel(pm).toString(), 12f, ink).apply { gravity = Gravity.CENTER; maxLines = 2 }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(9) })
            grid.addView(item, GridLayout.LayoutParams().apply { width = 0; height = dp(104); columnSpec = GridLayout.spec(GridLayout.UNDEFINED, 1f); setMargins(dp(4), dp(4), dp(4), dp(4)) })
        }
        if (apps.isEmpty()) col.addView(text("尚未发现可启动的应用", 15f, muted))
        scroll.addView(grid, LayoutParams(-1, -2))
        col.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
    }

    private fun showDiagnostics() {
        val col = sheetColumn("运行诊断", expanded = true)
        val scroll = ScrollView(context)
        diagnosticsText = text("", 12f, ink).apply { typeface = Typeface.MONOSPACE; setLineSpacing(dp(4).toFloat(), 1f); setTextIsSelectable(true) }
        scroll.addView(diagnosticsText, LayoutParams(-1, -2))
        col.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        col.addView(horizontalButton("分享诊断日志", Glyph.SHARE, accent) {
            context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"; putExtra(Intent.EXTRA_SUBJECT, "启航桌面诊断"); putExtra(Intent.EXTRA_TEXT, diagnosticsReport())
            }, "分享诊断日志"))
        }, LinearLayout.LayoutParams(dp(190), dp(48)).apply { topMargin = dp(8) })
        updateDiagnostics()
    }

    private fun updateDiagnostics() { diagnosticsText?.text = diagnosticsReport() }

    private fun diagnosticsReport(): String = buildString {
        appendLine("启航桌面 / 交互验证版 0.1.1")
        appendLine("────────────────────────────────")
        appendLine("Android  ${Build.VERSION.RELEASE}  /  API ${Build.VERSION.SDK_INT}")
        appendLine("设备     ${Build.MANUFACTURER} ${Build.MODEL}")
        appendLine("架构     ${Build.SUPPORTED_ABIS.joinToString()}")
        appendLine("3D 场景  ${if (sceneReady) "已就绪" else "加载中 / 尚未收到就绪信号"}")
        appendLine("数据源   本地模拟；未连接车辆")
        appendLine("待确认   ${gateway.pendingActions.size} 项")
        appendLine()
        appendLine("当前状态")
        appendLine(gateway.state.toJson())
        appendLine()
        appendLine("最近指令（请求 → 模拟回执）")
        gateway.logs.takeLast(18).forEach { appendLine(it) }
    }

    private fun horizontalButton(label: String, glyph: Glyph, color: Int, action: () -> Unit): LinearLayout = LinearLayout(context).apply {
        gravity = Gravity.CENTER; isClickable = true; isFocusable = true; contentDescription = label
        addView(IconView(context, glyph, color), LinearLayout.LayoutParams(dp(21), dp(21)))
        addView(text(label, 12f, color).apply { setPadding(dp(7), 0, 0, 0) })
        setOnClickListener { action() }
    }

    private fun text(value: String, size: Float, color: Int, bold: Boolean = false) = TextView(context).apply {
        text = value; textSize = size; setTextColor(color); includeFontPadding = false
        typeface = Typeface.create("sans-serif", if (bold) Typeface.BOLD else Typeface.NORMAL)
    }
    private fun shape(color: Int, radius: Float, stroke: Int? = null) = GradientDrawable().apply {
        setColor(color); cornerRadius = dp(radius).toFloat(); if (stroke != null) setStroke(dp(1), stroke)
    }
    private fun dp(value: Int): Int = (value * resources.displayMetrics.density + .5f).toInt()
    private fun dp(value: Float): Int = (value * resources.displayMetrics.density + .5f).toInt()
}
