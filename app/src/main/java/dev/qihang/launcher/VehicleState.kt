package dev.qihang.launcher

import org.json.JSONObject

/** Boundary shared by the simulator and future vehicle-service adapters. */
interface VehicleGateway : AutoCloseable {
    val state: VehicleState
    val logs: List<String>
    val pendingActions: Set<String>
    fun addListener(listener: (VehicleState) -> Unit)
    fun removeListener(listener: (VehicleState) -> Unit)
    fun request(action: String)
    fun logSnapshot(): String
    override fun close()
}

/** Renderer-independent vehicle state. Fractions are normalized to 0..1. */
data class VehicleState(
    val leftDoor: Float = 0f,
    val rightDoor: Float = 0f,
    val windows: Float = 0f,
    val trunk: Float = 0f,
    val lights: Boolean = false,
    val color: String = "#DCE5E9",
    val cameraPreset: String = "home",
    val cameraRevision: Int = 0,
    val simulation: Boolean = true,
) {
    fun toJson(): String = JSONObject().apply {
        put("leftDoor", leftDoor.toDouble())
        put("rightDoor", rightDoor.toDouble())
        put("windows", windows.toDouble())
        put("trunk", trunk.toDouble())
        put("lights", lights)
        put("color", color)
        put("cameraPreset", cameraPreset)
        put("cameraRevision", cameraRevision)
        put("simulation", simulation)
    }.toString()
}
