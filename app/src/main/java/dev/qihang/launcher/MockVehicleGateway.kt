package dev.qihang.launcher

import android.os.Handler
import android.os.Looper
import java.text.SimpleDateFormat
import java.util.Collections
import java.util.Date
import java.util.Locale

/** A local simulator. It never connects to vehicle hardware or a remote service. */
class MockVehicleGateway : VehicleGateway {
    private val handler = Handler(Looper.getMainLooper())
    private val listeners = Collections.synchronizedSet(linkedSetOf<(VehicleState) -> Unit>())
    private val entries = ArrayDeque<String>()
    private val pending = Collections.synchronizedSet(linkedSetOf<String>())
    @Volatile private var closed = false

    @Volatile override var state: VehicleState = VehicleState()
        private set

    override val logs: List<String> get() = synchronized(entries) { entries.toList() }
    override val pendingActions: Set<String> get() = synchronized(pending) { pending.toSet() }

    init {
        record("模拟服务就绪 · 等待交互")
    }

    override fun addListener(listener: (VehicleState) -> Unit) {
        if (closed) return
        listeners.add(listener)
        listener(state)
    }

    override fun removeListener(listener: (VehicleState) -> Unit) {
        listeners.remove(listener)
    }

    override fun request(action: String) {
        if (closed) return
        if (Looper.myLooper() != Looper.getMainLooper()) {
            handler.post { request(action) }
            return
        }
        if (action !in ACTIONS) {
            record("未识别的模拟操作：$action")
            publish()
            return
        }
        if (pending.contains(action)) return
        val isCamera = action.startsWith("camera_")
        pending.add(action)
        record("请求 · ${label(action)}")
        publish()
        handler.postDelayed({
            if (closed) return@postDelayed
            state = when (action) {
                "toggle_left_door" -> state.copy(leftDoor = if (state.leftDoor > .5f) 0f else 1f)
                "toggle_right_door" -> state.copy(rightDoor = if (state.rightDoor > .5f) 0f else 1f)
                "toggle_windows" -> state.copy(windows = if (state.windows > .5f) 0f else 1f)
                "toggle_trunk" -> state.copy(trunk = if (state.trunk > .5f) 0f else 1f)
                "toggle_lights" -> state.copy(lights = !state.lights)
                "color_white" -> state.copy(color = "#DCE5E9")
                "color_blue" -> state.copy(color = "#507A9C")
                "color_silver" -> state.copy(color = "#7B8793")
                "camera_home" -> state.copy(cameraPreset = "home", cameraRevision = state.cameraRevision + 1)
                "camera_front" -> state.copy(cameraPreset = "front", cameraRevision = state.cameraRevision + 1)
                "camera_side" -> state.copy(cameraPreset = "side", cameraRevision = state.cameraRevision + 1)
                "reset" -> VehicleState(cameraRevision = state.cameraRevision + 1)
                else -> state
            }
            pending.remove(action)
            record("模拟已确认 · ${label(action)}")
            publish()
        }, if (isCamera) 60L else 350L)
    }

    override fun logSnapshot(): String = buildString {
        appendLine("启航桌面 / 模拟交互日志")
        appendLine("数据来源：本地模拟；未连接车辆")
        appendLine("状态：${state.toJson()}")
        appendLine()
        logs.forEach { appendLine(it) }
    }

    override fun close() {
        closed = true
        handler.removeCallbacksAndMessages(null)
        listeners.clear()
        pending.clear()
    }

    private fun publish() {
        if (closed) return
        val snapshot = synchronized(listeners) { listeners.toList() }
        snapshot.forEach { it(state) }
    }

    private fun record(message: String) {
        val time = SimpleDateFormat("HH:mm:ss", Locale.CHINA).format(Date())
        synchronized(entries) {
            entries.addLast("$time  $message")
            while (entries.size > 80) entries.removeFirst()
        }
    }

    private fun label(action: String): String = when (action) {
        "toggle_left_door" -> "左前门"
        "toggle_right_door" -> "右前门"
        "toggle_windows" -> "车窗"
        "toggle_trunk" -> "尾门"
        "toggle_lights" -> "灯光"
        "color_white" -> "冰川白"
        "color_blue" -> "雾海蓝"
        "color_silver" -> "星岩灰"
        "camera_home" -> "默认视角"
        "camera_front" -> "车头视角"
        "camera_side" -> "侧面视角"
        "reset" -> "恢复初始状态"
        else -> action
    }

    companion object {
        val ACTIONS = setOf(
            "toggle_left_door", "toggle_right_door", "toggle_windows", "toggle_trunk", "toggle_lights",
            "color_white", "color_blue", "color_silver", "camera_home", "camera_front", "camera_side", "reset",
        )
    }
}
