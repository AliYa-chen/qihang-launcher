package dev.qihang.launcher

import android.os.Handler
import android.os.Looper
import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/** Transport boundary. This build connects only to the simulated gateway. */
class VehicleBridge(
    godot: Godot,
    private val gateway: VehicleGateway,
    private val onSceneReady: () -> Unit
) : GodotPlugin(godot) {
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var sceneReady = false

    override fun getPluginName(): String = "VehicleBridge"
    @Suppress("DEPRECATION")
    override fun getPluginMethods(): MutableList<String> = mutableListOf(
        "reportSceneReady", "getStateJson", "requestAction"
    )
    override fun getPluginSignals(): MutableSet<SignalInfo> =
        mutableSetOf(SignalInfo("state_changed", String::class.java))

    @UsedByGodot
    fun reportSceneReady() {
        Log.i("QihangBridge", "Scene handshake received")
        sceneReady = true
        main.post {
            onSceneReady()
            publish(gateway.state.toJson())
        }
    }

    @UsedByGodot
    fun getStateJson(): String = gateway.state.toJson()

    @UsedByGodot
    fun requestAction(action: String) {
        Log.i("QihangBridge", "Scene action: $action")
        main.post { gateway.request(action) }
    }

    fun publish(json: String) {
        if (sceneReady) runOnRenderThread {
            emitSignal("state_changed", json)
            Log.d("QihangBridge", "State delivered to scene")
        }
    }
}
