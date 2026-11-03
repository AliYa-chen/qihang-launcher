extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	assert(scene.model_source == "recovered_c236_kzb")
	assert(scene.studio_lighting.radiance != null)
	assert(scene.get_node("Car/RecoveredC236/LicensePlate").visible == false)
	assert(scene.get_node("Car/RecoveredC236/Lamp_TrunkDoor_LicensePlate").visible == false)
	assert(scene.studio_lighting.environment_energy == 4.0)
	assert(scene.studio_lighting.ambient_energy == 4.0)
	scene.apply_state(JSON.stringify({"leftDoor":1.0,"rightDoor":1.0,"windows":1.0,"trunk":1.0,"lights":true,"color":"#507A9C","cameraPreset":"side","cameraRevision":1}))
	for frame in range(65):
		scene._process(1.0 / 30.0)
	assert(scene.left_door.rotation.y < -0.8)
	assert(scene.right_door.rotation.y > 0.8)
	assert(scene.left_window.position.y < -0.3)
	assert(scene.trunk_lid.rotation.x > 0.7)
	assert(absf(scene.yaw + 1.55) < 0.01)
	# Idle return changes the camera alone and converges smoothly.
	scene.camera_idle_time = 11.99
	var previous_yaw: float = scene.yaw
	scene._process(0.02)
	assert(scene.camera_transition)
	assert(scene.yaw > previous_yaw and scene.yaw < scene.HOME_YAW)
	for frame in range(65):
		scene._process(1.0 / 30.0)
	assert(absf(scene.yaw - scene.HOME_YAW) < 0.001)
	assert(absf(scene.pitch - scene.HOME_PITCH) < 0.001)
	assert(absf(scene.distance - scene.HOME_DISTANCE) < 0.003)
	assert(scene.state["leftDoor"] == 1.0 and scene.state["trunk"] == 1.0)
	assert(scene.state["color"] == "#507A9C")
	# A fresh gesture cancels an in-flight return immediately.
	scene._set_camera_target("front")
	scene._begin_drag(Vector2(800, 500))
	scene._orbit(Vector2(120, 0))
	assert(not scene.camera_transition)
	assert(scene.camera_has_user_view)
	print("QIHANG_STUDIO_CHECK: IBL loaded; doors/windows/trunk/lights; smooth idle camera return preserves vehicle state; new gesture cancels return")
	quit(0)
