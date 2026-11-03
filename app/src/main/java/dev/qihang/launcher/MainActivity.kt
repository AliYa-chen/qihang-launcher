package dev.qihang.launcher

import android.app.Activity
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import androidx.fragment.app.FragmentActivity
import androidx.activity.OnBackPressedCallback
import org.godotengine.godot.Godot
import org.godotengine.godot.GodotFragment
import org.godotengine.godot.GodotHost
import org.godotengine.godot.plugin.GodotPlugin

class MainActivity : FragmentActivity(), GodotHost {
    private lateinit var screen: LauncherScreen
    private lateinit var gateway: MockVehicleGateway
    private var engineFragment: GodotFragment? = null
    @Volatile private var vehicleBridge: VehicleBridge? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setDecorFitsSystemWindows(false)
        gateway = MockVehicleGateway()
        screen = LauncherScreen(this, gateway)
        screen.sceneContainer.id = 0x1234ABC
        setContentView(screen)
        gateway.addListener { state ->
            screen.refresh(state)
            vehicleBridge?.publish(state.toJson())
        }
        screen.refresh(gateway.state)

        val existing = supportFragmentManager.findFragmentByTag("godot") as? GodotFragment
        engineFragment = existing ?: GodotFragment().also {
            supportFragmentManager.beginTransaction()
                .replace(screen.sceneContainer.id, it, "godot")
                .commitNow()
        }
        // Register after the engine fragment: native sheets have precedence
        // over FragmentManager/engine callbacks for Android gesture back.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = handleLauncherBack()
        })
        immersive()
    }

    private fun immersive() {
        window.insetsController?.let {
            it.hide(WindowInsets.Type.systemBars())
            it.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) immersive()
    }

    override fun getActivity(): Activity = this
    override fun getGodot(): Godot? = engineFragment?.godot

    override fun getCommandLine(): MutableList<String> = mutableListOf(
        "--rendering-method", "gl_compatibility", "--max-fps", "30"
    )

    @Synchronized
    override fun getHostPlugins(godot: Godot): MutableSet<GodotPlugin> {
        val bridge = vehicleBridge ?: VehicleBridge(godot, gateway) {
            runOnUiThread {
                screen.setSceneReady(true)
            }
        }.also { vehicleBridge = it }
        return mutableSetOf(bridge)
    }

    override fun onGodotMainLoopStarted() {
        runOnUiThread { vehicleBridge?.publish(gateway.state.toJson()) }
    }

    override fun onDestroy() {
        gateway.close()
        super.onDestroy()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // GodotInputHandler consumes non-volume key events when its render view
        // is focused. Intercept physical/emulator BACK before focused-view
        // dispatch so it closes the native sheet rather than reaching Godot.
        if (event.keyCode == KeyEvent.KEYCODE_BACK) {
            if (event.action == KeyEvent.ACTION_UP && !event.isCanceled) handleLauncherBack()
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    private fun handleLauncherBack() {
        if (::screen.isInitialized && !screen.dismissPanels()) screen.showNotice("已在启航桌面")
    }

    @Deprecated("Android back dispatch is handled locally for the launcher prototype")
    override fun onBackPressed() {
        handleLauncherBack()
    }
}
