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
	assert(Engine.max_fps == 0)
	var painted: ShaderMaterial = scene.studio_materials[scene.paint]
	assert(painted.get_shader_parameter("has_ao_texture") == true)
	assert(painted.get_shader_parameter("ao_flip_v") == true)
	assert(is_equal_approx(painted.get_shader_parameter("ao_strength"), 1.0))
	assert(is_equal_approx(painted.get_shader_parameter("ao_light_affect"), 1.0))
	assert(is_equal_approx(painted.get_shader_parameter("metallic_value"), 0.25))
	assert(is_equal_approx(painted.get_shader_parameter("roughness_value"), 0.2))
	assert(painted.get_shader_parameter("base_color").is_equal_approx(Color("#181818")))
	assert(scene.studio.mirror_viewport.world_3d == root.find_world_3d())
	assert(scene.studio.mirror_camera.cull_mask == 1)
	assert(scene.studio.mirror_viewport.msaa_3d == Viewport.MSAA_DISABLED)
	assert(scene.studio.source_shadow.mesh.get_surface_count() == 1)
	assert(scene.camera.cull_mask == 7)
	var source_size: Vector2 = root.get_visible_rect().size
	assert(scene.studio.mirror_viewport.size == Vector2i(maxi(1, floori(source_size.x * 0.5)), maxi(1, floori(source_size.y * 0.5))))
	scene.apply_state(JSON.stringify({"leftDoor":1.0,"rightDoor":1.0,"windows":1.0,"trunk":1.0,"lights":true,"color":"#507A9C","cameraPreset":"side","cameraRevision":1}))
	assert(is_equal_approx(painted.get_shader_parameter("metallic_value"), 0.7))
	assert(is_equal_approx(painted.get_shader_parameter("roughness_value"), 0.1))
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
	# Theme changes keep the source lighting energy, appearance and camera state.
	scene.apply_state(JSON.stringify({"nightMode":true}))
	scene._process(0.3)
	assert(scene.world_environment.background_color.is_equal_approx(Color("#161718")))
	assert(scene.studio.glow.visible)
	assert(is_equal_approx(scene.studio.glow_material.get_shader_parameter("overall_fade"), 0.26))
	assert(scene.studio_lighting.environment_energy == 4.0)
	assert(scene.state["leftDoor"] == 1.0 and scene.state["color"] == "#507A9C")
	assert(absf(scene.yaw - scene.HOME_YAW) < 0.001)
	scene.apply_state(JSON.stringify({"nightMode":false}))
	assert(scene.world_environment.background_color.is_equal_approx(Color("#F7F7F7")))
	assert(not scene.studio.night_mode)
	# A fresh gesture cancels an in-flight return immediately.
	scene._set_camera_target("front")
	scene._begin_drag(Vector2(800, 500))
	scene._orbit(Vector2(120, 0))
	assert(not scene.camera_transition)
	assert(scene.camera_has_user_view)
	print("QIHANG_STUDIO_CHECK: source paint/AO, mirror layers and day/night; display-paced rendering; idle camera return preserves state")
	quit(0)
