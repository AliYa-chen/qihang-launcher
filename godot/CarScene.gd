extends Node3D
## Recovered vehicle geometry with an interaction rig and procedural fallback.

const SharedLighting = preload("res://SharedVehicleLighting.gd")
const CAMERA_IDLE_RETURN_SECONDS := 12.0
const CAMERA_TRANSITION_SECONDS := 0.5
# Tesla tablet PARKED: pivot (85,-140,0), local X=-90, offset (-.06,3.5,0),
# design FOV60 and frame scale .42. Map the forward axis to this vehicle.
const HOME_YAW := -0.6981317008
const HOME_PITCH := 0.0872664626
const HOME_DISTANCE := 8.33455773
const HOME_FOV := 27.2607941662
const ORBIT_TARGET := Vector3(0.110218955, 0.7598932865, -0.0908924258)

var studio_lighting
var studio_materials: Dictionary = {}
var bridge: Object
var car_root: Node3D
var left_door: Node3D
var right_door: Node3D
var left_window: Node3D
var right_window: Node3D
var trunk_lid: Node3D
var camera: Camera3D
var paint: StandardMaterial3D
var glass: StandardMaterial3D
var dark_trim: StandardMaterial3D
var metal: StandardMaterial3D
var wheel_metal: StandardMaterial3D
var tire: StandardMaterial3D
var lamp_on: StandardMaterial3D
var lamp_off: StandardMaterial3D
var rear_lamp: StandardMaterial3D
var head_lamps: Array[MeshInstance3D] = []
var tail_lamps: Array[MeshInstance3D] = []
var rear_windows: Array[Node3D] = []
var trunk_rotation_sign: float = -1.0
var state: Dictionary = {
	"leftDoor": 0.0, "rightDoor": 0.0, "windows": 0.0, "trunk": 0.0,
	"lights": false, "color": "#DCE5E9", "cameraPreset": "home", "simulation": true
}
var current_left: float = 0.0
var current_right: float = 0.0
var current_windows: float = 0.0
var current_trunk: float = 0.0
var yaw: float = HOME_YAW
var pitch: float = HOME_PITCH
var distance: float = HOME_DISTANCE
var drag_active: bool = false
var press_position: Vector2
var drag_distance: float = 0.0
var last_preset: String = "home"
var last_camera_revision: int = 0
var camera_idle_time: float = 0.0
var camera_has_user_view: bool = false
var camera_transition: bool = false
var camera_transition_time: float = 0.0
var camera_start_yaw: float = HOME_YAW
var camera_start_pitch: float = HOME_PITCH
var camera_start_distance: float = HOME_DISTANCE
var camera_goal_yaw: float = HOME_YAW
var camera_goal_pitch: float = HOME_PITCH
var camera_goal_distance: float = HOME_DISTANCE
var touch_positions: Dictionary = {}
var last_pinch_distance: float = 0.0
var model_source: String = "procedural_demo"


func _ready() -> void:
	Engine.max_fps = 30
	studio_lighting = SharedLighting.new()
	_build_materials()
	_build_studio()
	car_root = Node3D.new()
	car_root.name = "Car"
	add_child(car_root)
	_build_vehicle()
	if model_source == "recovered_c236_kzb":
		studio_lighting.set_coordinate_rotation(Basis(Vector3.UP, PI))
	_apply_studio_materials(car_root)
	if Engine.has_singleton("VehicleBridge"):
		bridge = Engine.get_singleton("VehicleBridge")
		# Android plugin methods are dynamically dispatched; has_method() does
		# not reliably describe this Java singleton's registered methods.
		bridge.connect("state_changed", Callable(self, "apply_state"))
		apply_state(str(bridge.call("getStateJson")))
		print("QIHANG_BRIDGE: native VehicleBridge connected")
	_update_camera()
	call_deferred("_notify_ready")


func _notify_ready() -> void:
	# Keep the native blurred loading surface until the first real vehicle frame.
	await RenderingServer.frame_post_draw
	if bridge != null:
		bridge.call("reportSceneReady")
	print("QIHANG_SCENE_READY: " + model_source)


func _build_materials() -> void:
	paint = _material(Color("#DCE5E9"), 0.18, 0.4)
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.85
	paint.clearcoat_roughness = 0.16
	# Neutral glass/metal/wheel response taken directly from the Tesla APK.
	glass = _material(Color("#010101"), 0.0, 0.2)
	glass.albedo_color.a = 0.7843137
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dark_trim = _material(Color("#111213"), 0.0, 0.4)
	metal = _material(Color("#171717"), 1.0, 0.15)
	wheel_metal = _material(Color("#0E0E0E"), 0.78, 0.4)
	tire = _material(Color("#0B0B0B"), 1.0, 0.92)
	lamp_on = _material(Color("#F3F3F3"), 0.2, 0.2)
	lamp_on.emission_enabled = true
	lamp_on.emission = Color("#EEEEEE")
	lamp_on.emission_energy_multiplier = 1.7
	lamp_off = _material(Color("#616161"), 0.42, 0.3)
	rear_lamp = _material(Color("#C64432"), 0.1, 0.22)
	rear_lamp.emission_enabled = true
	rear_lamp.emission = Color("#C42D20")
	rear_lamp.emission_energy_multiplier = 1.1


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


func _build_studio() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#161718")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.BLACK
	environment.ambient_light_energy = 0.0
	environment.ambient_light_sky_contribution = 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# The shared material shader owns the source renderer's gamma-space IBL.
	# Keep exposure 1 and avoid adding a second tone mapper or light rig.
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = load("res://shaders/studio_floor.gdshader")
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(1000, 1000)
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.material_override = floor_mat
	floor_instance.position.y = -0.035
	add_child(floor_instance)
	camera = Camera3D.new()
	camera.name = "OrbitCamera"
	camera.fov = HOME_FOV
	camera.v_offset = 0.0
	camera.near = 0.119047619
	camera.far = 357.142857
	camera.current = true
	add_child(camera)


func _studio_paint_color(color: Color) -> Color:
	# Tesla Desk's existing source paint profiles are deliberately darker than
	# UI swatches because its IBL evaluates the original display-space response.
	match color.to_html(false).to_upper():
		"DCE5E9", "DCE7EB": return Color("#232220") # Soft warm pearl
		"507A9C": return Color("#12161F") # GlacierBlue
		"7B8793", "7E8B98": return Color("#121417") # StealthGrey
	return Color(color.r * 0.325, color.g * 0.325, color.b * 0.325, color.a)


func _studio_material(source: BaseMaterial3D) -> ShaderMaterial:
	if not studio_materials.has(source):
		var overrides := {}
		if source == paint:
			overrides["albedo"] = _studio_paint_color(paint.albedo_color)
			overrides["pearl"] = true
			overrides["diffuse_fill"] = 0.5
			overrides["diffuse_fill_value"] = 0.5
			overrides["look_exposure"] = 1.8
			overrides["look_gamma"] = 0.85
			overrides["highlight_rolloff"] = 1.0
		else:
			var color := source.albedo_color
			# The recovered GLB wrote provisional display swatches as glTF linear
			# factors. Undo the importer's encoding for this asset only.
			if source.resource_name.begins_with("mat_"):
				color = color.srgb_to_linear()
			# The provisional KZB material reconstruction tinted neutral trim blue.
			# Keep its brightness and alpha, with a neutral base under the studio.
			if color.b > color.r and color.s < 0.55:
				var value := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
				color = Color(value, value, value, color.a)
			overrides["albedo"] = color
		studio_materials[source] = studio_lighting.create_material(source, overrides)
	return studio_materials[source]


func _apply_studio_materials(parent: Node) -> void:
	if parent is MeshInstance3D and parent.mesh != null:
		if parent.material_override is BaseMaterial3D:
			parent.material_override = _studio_material(parent.material_override)
		else:
			for surface in range(parent.mesh.get_surface_count()):
				var source: Material = parent.get_active_material(surface)
				if source is BaseMaterial3D:
					parent.set_surface_override_material(surface, _studio_material(source))
	for child in parent.get_children():
		_apply_studio_materials(child)


func _build_vehicle() -> void:
	if _build_recovered_vehicle():
		return
	# Body panels are separated from the moving doors so opening reveals the cabin.
	_build_top_panel(-2.30, -0.79, 24, "Hood")
	_build_top_panel(1.05, 2.24, 20, "RearDeckBase")
	for side in [-1.0, 1.0]:
		_build_side(side, -2.27, -0.79, 36)
		_build_side(side, 0.36, 2.23, 44)
		_build_sill(side)
	_build_front_and_rear()
	_build_cabin()
	left_door = _build_door(-1.0, "LeftDoor", "toggle_left_door")
	right_door = _build_door(1.0, "RightDoor", "toggle_right_door")
	left_window = left_door.get_node("Window")
	right_window = right_door.get_node("Window")
	_build_trunk()
	for side in [-1.0, 1.0]:
		_build_wheel(side, -1.45)
		_build_wheel(side, 1.42)
	_build_seats()
	# The procedural asset stays usable while the source KZB-to-glTF pipeline evolves.
	if ResourceLoader.exists("res://assets/car.glb"):
		print("QIHANG_ASSET_AVAILABLE: res://assets/car.glb; procedural interaction rig active")


func _build_recovered_vehicle() -> bool:
	# Runtime glTF loading also works when the raw project is embedded in Android assets.
	if not FileAccess.file_exists("res://assets/car.glb"):
		return false
	var document := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var error := document.append_from_file("res://assets/car.glb",gltf_state)
	if error != OK:
		push_warning("Recovered vehicle could not load: " + str(error))
		return false
	var recovered: Node3D = document.generate_scene(gltf_state)
	if recovered == null:
		return false
	recovered.name = "RecoveredC236"
	car_root.add_child(recovered)
	left_door = Node3D.new()
	left_door.name = "LeftDoor"
	left_door.position = Vector3(0.86,0.86,0.83)
	recovered.add_child(left_door)
	right_door = Node3D.new()
	right_door.name = "RightDoor"
	right_door.position = Vector3(-0.86,0.86,0.83)
	recovered.add_child(right_door)
	left_window = Node3D.new()
	left_window.name = "Window"
	left_door.add_child(left_window)
	right_window = Node3D.new()
	right_window.name = "Window"
	right_door.add_child(right_window)
	trunk_lid = Node3D.new()
	trunk_lid.name = "Trunk"
	trunk_lid.position = Vector3(0,1.36,-1.35)
	recovered.add_child(trunk_lid)
	trunk_rotation_sign = 1.0
	var rear_left := Node3D.new()
	var rear_right := Node3D.new()
	recovered.add_child(rear_left)
	recovered.add_child(rear_right)
	rear_windows.assign([rear_left,rear_right])
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(recovered,meshes)
	for instance in meshes:
		var part_name := str(instance.name)
		if part_name == "LicensePlate" or part_name == "Lamp_TrunkDoor_LicensePlate":
			instance.visible = false
			continue
		if part_name.contains("CarPaint"):
			instance.material_override = paint
		elif part_name.contains("MirrorGlass"):
			instance.material_override = metal
		elif part_name.begins_with("Glass_"):
			instance.material_override = glass
		elif part_name.contains("Rims_"):
			instance.material_override = wheel_metal
		elif part_name.contains("Tire_Rubber"):
			instance.material_override = tire
		elif part_name.contains("Metal_") or part_name.ends_with("_Logo") or part_name.ends_with("_Line"):
			instance.material_override = metal
		if part_name.begins_with("Glass_Door_LF"):
			instance.reparent(left_window,true)
		elif part_name.begins_with("Glass_Door_RF"):
			instance.reparent(right_window,true)
		elif part_name.begins_with("Glass_Door_LR"):
			instance.reparent(rear_left,true)
		elif part_name.begins_with("Glass_Door_RR"):
			instance.reparent(rear_right,true)
		elif part_name.begins_with("Door_LF_") or part_name.begins_with("Lamp_Door_LF"):
			instance.reparent(left_door,true)
		elif part_name.begins_with("Door_RF_") or part_name.begins_with("Lamp_Door_RF"):
			instance.reparent(right_door,true)
		elif part_name.contains("TrunkDoor") or part_name == "Lamp_HighStop":
			instance.reparent(trunk_lid,true)
		if part_name.begins_with("Lamp_Daytime") or part_name == "Lamp_Beam":
			head_lamps.append(instance)
		elif part_name.begins_with("Lamp_Rear_") or part_name.begins_with("Lamp_TrunkDoor"):
			tail_lamps.append(instance)
	_add_hit(left_door,Vector3(0.08,-0.10,-0.55),Vector3(0.17,0.52,1.0),"toggle_left_door")
	_add_hit(right_door,Vector3(-0.08,-0.10,-0.55),Vector3(0.17,0.52,1.0),"toggle_right_door")
	_add_hit(left_window,Vector3(-0.03,0.36,-0.48),Vector3(0.18,0.23,0.65),"toggle_windows")
	_add_hit(right_window,Vector3(0.03,0.36,-0.48),Vector3(0.18,0.23,0.65),"toggle_windows")
	_add_hit(trunk_lid,Vector3(0,-0.17,-0.51),Vector3(1.45,0.18,0.85),"toggle_trunk")
	_add_hit(recovered,Vector3(0,0.81,2.13),Vector3(1.5,0.26,0.25),"toggle_lights")
	recovered.rotation.y = PI
	model_source = "recovered_c236_kzb"
	apply_state(JSON.stringify(state))
	return true


func _collect_meshes(parent: Node, collected: Array[MeshInstance3D]) -> void:
	for child in parent.get_children():
		if child is MeshInstance3D:
			collected.append(child)
		_collect_meshes(child,collected)


func _body_width(z: float) -> float:
	return 0.97 - 0.19 * pow(clampf(absf(z) / 2.35, 0.0, 1.0), 3.4)


func _body_top(z: float) -> float:
	return 1.09 - 0.18 * pow(clampf(absf(z) / 2.45, 0.0, 1.0), 3.0)


func _build_top_panel(start_z: float, end_z: float, segments: int, panel_name: String) -> void:
	var vertices: Array[Vector3] = []
	var lateral: int = 12
	for iz in range(segments):
		var z0 := lerpf(start_z, end_z, float(iz) / segments)
		var z1 := lerpf(start_z, end_z, float(iz + 1) / segments)
		for ix in range(lateral):
			var x0 := lerpf(-1.0, 1.0, float(ix) / lateral)
			var x1 := lerpf(-1.0, 1.0, float(ix + 1) / lateral)
			_quad(vertices, Vector3(x0 * _body_width(z0), _body_top(z0) - x0*x0*0.065, z0), Vector3(x1 * _body_width(z0), _body_top(z0) - x1*x1*0.065, z0), Vector3(x1 * _body_width(z1), _body_top(z1) - x1*x1*0.065, z1), Vector3(x0 * _body_width(z1), _body_top(z1) - x0*x0*0.065, z1))
	_mesh(car_root, vertices, paint, panel_name)


func _arch_bottom(z: float) -> float:
	var bottom: float = 0.42
	for wheel_z in [-1.45, 1.42]:
		var delta_z: float = absf(z - wheel_z)
		if delta_z < 0.48:
			bottom = maxf(bottom, 0.47 + sqrt(maxf(0.0, 0.48 * 0.48 - delta_z * delta_z)))
	return bottom


func _build_side(side: float, start_z: float, end_z: float, segments: int) -> void:
	var vertices: Array[Vector3] = []
	for i in range(segments):
		var z0 := lerpf(start_z, end_z, float(i) / segments)
		var z1 := lerpf(start_z, end_z, float(i + 1) / segments)
		var top0: float = _body_top(z0) - 0.065
		var top1: float = _body_top(z1) - 0.065
		var bot0: float = minf(_arch_bottom(z0), top0 - 0.025)
		var bot1: float = minf(_arch_bottom(z1), top1 - 0.025)
		_quad(vertices, Vector3(side*_body_width(z0), top0, z0), Vector3(side*_body_width(z1), top1, z1), Vector3(side*(_body_width(z1)-0.035), bot1, z1), Vector3(side*(_body_width(z0)-0.035), bot0, z0))
	_mesh(car_root, vertices, paint, "BodySide")


func _build_sill(side: float) -> void:
	_box(car_root, Vector3(0.075, 0.075, 2.05), Vector3(side * 0.925, 0.395, -0.03), dark_trim, "SideSill")
	_box(car_root, Vector3(0.018, 0.018, 2.02), Vector3(side * 0.967, 0.433, -0.03), metal, "SillHighlight")


func _build_front_and_rear() -> void:
	var front: Array[Vector3] = []
	_quad(front, Vector3(-0.79,0.93,-2.30), Vector3(0.79,0.93,-2.30), Vector3(0.76,0.53,-2.27), Vector3(-0.76,0.53,-2.27))
	_mesh(car_root, front, paint, "FrontBumper")
	_box(car_root,Vector3(1.13,0.15,0.055),Vector3(0,0.64,-2.312),dark_trim,"LowerIntake")
	_box(car_root,Vector3(1.48,0.035,0.07),Vector3(0,0.48,-2.28),dark_trim,"FrontSplitter")
	_box(car_root,Vector3(0.38,0.11,0.026),Vector3(0,0.78,-2.334),_material(Color("#26373E"),0.15,0.55),"FrontPlate")
	for side in [-1.0, 1.0]:
		var lamp := _box(car_root,Vector3(0.46,0.035,0.055),Vector3(side*0.56,0.946,-2.306),lamp_off,"Headlight")
		lamp.rotation.y = side * -0.065
		head_lamps.append(lamp)
		_box(car_root,Vector3(0.045,0.19,0.045),Vector3(side*0.74,0.79,-2.318),dark_trim,"AirCurtain")
		_add_hit(car_root,Vector3(side*0.58,0.95,-2.32),Vector3(0.45,0.14,0.22),"toggle_lights")
	var rear: Array[Vector3] = []
	_quad(rear,Vector3(-0.80,0.96,2.25),Vector3(0.80,0.96,2.25),Vector3(0.78,0.49,2.21),Vector3(-0.78,0.49,2.21))
	_mesh(car_root,rear,paint,"RearBumper")
	_box(car_root,Vector3(1.45,0.14,0.09),Vector3(0,0.49,2.24),dark_trim,"RearDiffuser")
	var tail := _box(car_root,Vector3(1.48,0.038,0.045),Vector3(0,0.98,2.265),rear_lamp,"TailLight")
	tail_lamps.append(tail)
	_box(car_root,Vector3(0.36,0.13,0.03),Vector3(0,0.76,2.285),dark_trim,"RearPlate")


func _build_cabin() -> void:
	var windscreen: Array[Vector3] = []
	_quad(windscreen,Vector3(-0.85,1.075,-0.84),Vector3(0.85,1.075,-0.84),Vector3(0.69,1.59,-0.23),Vector3(-0.69,1.59,-0.23))
	_mesh(car_root,windscreen,glass,"Windscreen")
	var roof: Array[Vector3] = []
	for i in range(12):
		var a := lerpf(-0.22,0.65,float(i)/12)
		var b := lerpf(-0.22,0.65,float(i+1)/12)
		var ya := 1.61+sin(float(i)/12*PI)*0.035
		var yb := 1.61+sin(float(i+1)/12*PI)*0.035
		_quad(roof,Vector3(-0.70,ya,a),Vector3(0.70,ya,a),Vector3(0.70,yb,b),Vector3(-0.70,yb,b))
	_mesh(car_root,roof,glass,"PanoramicRoof")
	var rear_glass: Array[Vector3] = []
	_quad(rear_glass,Vector3(-0.70,1.60,0.65),Vector3(0.70,1.60,0.65),Vector3(0.85,1.08,1.28),Vector3(-0.85,1.08,1.28))
	_mesh(car_root,rear_glass,glass,"RearGlass")
	for side in [-1.0,1.0]:
		_rod(car_root,Vector3(side*0.86,1.06,-0.85),Vector3(side*0.70,1.62,-0.23),0.027,paint,"APillar")
		_rod(car_root,Vector3(side*0.70,1.62,-0.23),Vector3(side*0.70,1.62,0.65),0.026,paint,"RoofRail")
		_rod(car_root,Vector3(side*0.70,1.62,0.65),Vector3(side*0.85,1.07,1.28),0.044,paint,"CPillar")
		_rod(car_root,Vector3(side*0.935,1.06,0.34),Vector3(side*0.70,1.60,0.34),0.025,dark_trim,"BPillar")
		var rear_window: Array[Vector3] = []
		_quad(rear_window,Vector3(side*0.924,1.085,0.38),Vector3(side*0.83,1.085,1.22),Vector3(side*0.71,1.57,0.66),Vector3(side*0.71,1.58,0.38))
		_mesh(car_root,rear_window,glass,"RearSideGlass")
		_box(car_root,Vector3(0.034,0.02,0.19),Vector3(side*0.962,0.992,0.96),dark_trim,"RearDoorHandle")
	_box(car_root,Vector3(1.7,0.07,2.15),Vector3(0,0.54,0.12),dark_trim,"CabinFloor")


func _build_door(side: float, door_name: String, action: String) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = door_name
	pivot.position = Vector3(side*0.93,0.80,-0.78)
	car_root.add_child(pivot)
	var door_vertices: Array[Vector3] = []
	# Slightly convex mid-section catches the studio highlights.
	for i in range(12):
		var z0 := lerpf(-0.77,0.31,float(i)/12)
		var z1 := lerpf(-0.77,0.31,float(i+1)/12)
		var p0 := Vector3(side*_body_width(z0),1.025,z0)-pivot.position
		var p1 := Vector3(side*_body_width(z1),1.025,z1)-pivot.position
		var p2 := Vector3(side*(_body_width(z1)-0.018),0.46,z1)-pivot.position
		var p3 := Vector3(side*(_body_width(z0)-0.018),0.46,z0)-pivot.position
		_quad(door_vertices,p0,p1,p2,p3)
	_mesh(pivot,door_vertices,paint,"DoorPanel")
	_box(pivot,Vector3(0.055,0.42,0.95),Vector3(side*-0.024,-0.08,0.55),dark_trim,"InteriorDoorTrim")
	_box(pivot,Vector3(0.032,0.018,0.19),Vector3(side*0.04,0.195,0.83),dark_trim,"DoorHandle")
	_box(pivot,Vector3(0.24,0.11,0.17),Vector3(side*0.12,0.30,0.10),paint,"MirrorHousing")
	_box(pivot,Vector3(0.018,0.07,0.13),Vector3(side*0.242,0.30,0.12),glass,"MirrorGlass")
	var window := Node3D.new()
	window.name = "Window"
	pivot.add_child(window)
	var vertices: Array[Vector3] = []
	_quad(vertices,Vector3(side*0.938,1.055,-0.735)-pivot.position,Vector3(side*0.938,1.055,0.292)-pivot.position,Vector3(side*0.705,1.577,0.292)-pivot.position,Vector3(side*0.713,1.577,-0.193)-pivot.position)
	_mesh(window,vertices,glass,"MovingGlass")
	_rod(pivot,Vector3(side*0.938,1.04,-0.76)-pivot.position,Vector3(side*0.938,1.04,0.31)-pivot.position,0.013,metal,"BeltLine")
	_add_hit(pivot,Vector3(0,-0.035,0.52),Vector3(0.15,0.52,0.98),action)
	_add_hit(window,Vector3(side*-0.12,0.51,0.81),Vector3(0.14,0.29,0.48),"toggle_windows")
	return pivot


func _build_trunk() -> void:
	trunk_lid = Node3D.new()
	trunk_lid.name = "Trunk"
	trunk_lid.position = Vector3(0,1.085,1.24)
	car_root.add_child(trunk_lid)
	var vertices: Array[Vector3] = []
	_quad(vertices,Vector3(-0.83,0,0),Vector3(0.83,0,0),Vector3(0.79,-0.10,0.97),Vector3(-0.79,-0.10,0.97))
	_mesh(trunk_lid,vertices,paint,"TrunkLid")
	_box(trunk_lid,Vector3(1.56,0.028,0.045),Vector3(0,-0.086,0.95),dark_trim,"LipSpoiler")
	_box(trunk_lid,Vector3(1.48,0.03,0.70),Vector3(0,-0.035,0.40),dark_trim,"TrunkUnderside")
	_add_hit(trunk_lid,Vector3(0,0,0.55),Vector3(1.45,0.13,0.77),"toggle_trunk")


func _build_wheel(side: float, wheel_z: float) -> void:
	var root := Node3D.new()
	root.name = "Wheel"
	root.position = Vector3(side*0.94,0.465,wheel_z)
	car_root.add_child(root)
	_cylinder(root,0.435,0.245,Vector3.ZERO,tire,"Tire")
	_cylinder(root,0.315,0.253,Vector3.ZERO,dark_trim,"RimInner")
	_cylinder(root,0.263,0.258,Vector3.ZERO,metal,"BrakeDisc")
	_cylinder(root,0.062,0.284,Vector3.ZERO,metal,"WheelHub")
	for i in range(10):
		var angle := float(i)/10*TAU
		var spoke := _box(root,Vector3(0.025,0.25,0.029),Vector3(side*0.137,cos(angle)*0.17,sin(angle)*0.17),metal,"RimSpoke")
		spoke.rotation.x = angle
	var ring := TorusMesh.new()
	ring.inner_radius = 0.296
	ring.outer_radius = 0.318
	ring.rings = 48
	ring.ring_segments = 10
	var rim := MeshInstance3D.new()
	rim.mesh = ring
	rim.rotation.z = PI/2
	rim.position.x = side*0.132
	rim.material_override = metal
	root.add_child(rim)
	var caliper := _material(Color("#B78857"),0.5,0.35)
	_box(root,Vector3(0.035,0.15,0.075),Vector3(side*0.14,0.02,-0.205),caliper,"Caliper")


func _build_seats() -> void:
	var seat_mat := _material(Color("#46504F"),0.05,0.82)
	for x in [-0.43,0.43]:
		_box(car_root,Vector3(0.42,0.10,0.45),Vector3(x,0.70,-0.12),seat_mat,"SeatCushion")
		var back := _box(car_root,Vector3(0.42,0.55,0.11),Vector3(x,1.0,0.11),seat_mat,"SeatBack")
		back.rotation.x = -0.12
		_box(car_root,Vector3(0.25,0.17,0.11),Vector3(x,1.35,0.14),seat_mat,"HeadRest")
	_box(car_root,Vector3(1.22,0.30,0.14),Vector3(0,0.92,-0.68),dark_trim,"Dashboard")
	_box(car_root,Vector3(0.26,0.17,0.05),Vector3(0,1.12,-0.53),glass,"CenterDisplay")


func _cylinder(parent: Node3D, radius: float, height: float, position_value: Vector3, material: Material, mesh_name: String) -> MeshInstance3D:
	var primitive := CylinderMesh.new()
	primitive.top_radius = radius
	primitive.bottom_radius = radius
	primitive.height = height
	primitive.radial_segments = 48
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = primitive
	instance.material_override = material
	instance.rotation.z = PI/2
	instance.position = position_value
	parent.add_child(instance)
	return instance


func _box(parent: Node3D, size: Vector3, position_value: Vector3, material: Material, mesh_name: String) -> MeshInstance3D:
	var primitive := BoxMesh.new()
	primitive.size = size
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = primitive
	instance.material_override = material
	instance.position = position_value
	parent.add_child(instance)
	return instance


func _rod(parent: Node3D, start: Vector3, end: Vector3, radius: float, material: Material, mesh_name: String) -> void:
	var primitive := CylinderMesh.new()
	primitive.top_radius = radius
	primitive.bottom_radius = radius
	primitive.height = start.distance_to(end)
	primitive.radial_segments = 10
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = primitive
	instance.material_override = material
	instance.position = (start+end)*0.5
	var direction := (end-start).normalized()
	var helper := Vector3.FORWARD
	if absf(direction.dot(helper)) > 0.98:
		helper = Vector3.RIGHT
	var x_axis := direction.cross(helper).normalized()
	instance.basis = Basis(x_axis,direction,x_axis.cross(direction).normalized())
	parent.add_child(instance)


func _quad(vertices: Array[Vector3], a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	vertices.append_array([a,b,c,a,c,d])


func _mesh(parent: Node3D, vertices: Array[Vector3], material: Material, mesh_name: String) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	for vertex in vertices:
		surface.add_vertex(vertex)
	surface.generate_normals()
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = surface.commit()
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _add_hit(parent: Node3D, position_value: Vector3, size: Vector3, action: String) -> void:
	var body := StaticBody3D.new()
	body.name = "Hit_"+action
	body.position = position_value
	body.set_meta("action",action)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


func apply_state(json: String) -> void:
	var parsed: Variant = JSON.parse_string(json)
	if not parsed is Dictionary:
		return
	for key in state.keys():
		if parsed.has(key):
			state[key] = parsed[key]
	paint.albedo_color = Color(str(state.get("color","#DCE5E9")))
	studio_lighting.update_color(_studio_material(paint), _studio_paint_color(paint.albedo_color))
	for lamp in head_lamps:
		lamp.material_override = _studio_material(lamp_on if bool(state.get("lights",false)) else lamp_off)
	for lamp in tail_lamps:
		lamp.material_override = _studio_material(rear_lamp if bool(state.get("lights",false)) else dark_trim)
	var preset := str(state.get("cameraPreset","home"))
	var camera_revision := int(parsed.get("cameraRevision",last_camera_revision))
	if preset != last_preset or camera_revision != last_camera_revision:
		last_preset = preset
		last_camera_revision = camera_revision
		_set_camera_target(preset)
		camera_has_user_view = preset != "home"
		camera_idle_time = 0.0


func _set_camera_target(preset: String) -> void:
	camera_start_yaw = yaw
	camera_start_pitch = pitch
	camera_start_distance = distance
	camera_transition_time = 0.0
	match preset:
		"front": camera_goal_yaw = 0.0; camera_goal_pitch = 0.18; camera_goal_distance = 7.0
		"side": camera_goal_yaw = -1.55; camera_goal_pitch = 0.18; camera_goal_distance = HOME_DISTANCE
		"rear": camera_goal_yaw = -2.7; camera_goal_pitch = 0.30; camera_goal_distance = HOME_DISTANCE
		_: camera_goal_yaw = HOME_YAW; camera_goal_pitch = HOME_PITCH; camera_goal_distance = HOME_DISTANCE
	camera_transition = true


func _note_camera_activity() -> void:
	camera_idle_time = 0.0
	camera_has_user_view = true
	camera_transition = false


func _return_camera_home() -> void:
	camera_has_user_view = false
	camera_idle_time = 0.0
	_set_camera_target("home")
	state["cameraPreset"] = "home"
	last_preset = "home"
	if bridge != null:
		bridge.call("requestAction", "camera_home")


func _process(delta: float) -> void:
	var blend := 1.0-exp(-delta*8.0)
	current_left = lerpf(current_left,clampf(float(state.get("leftDoor",0)),0,1),blend)
	current_right = lerpf(current_right,clampf(float(state.get("rightDoor",0)),0,1),blend)
	current_windows = lerpf(current_windows,clampf(float(state.get("windows",0)),0,1),blend)
	current_trunk = lerpf(current_trunk,clampf(float(state.get("trunk",0)),0,1),blend)
	left_door.rotation.y = -current_left*1.12
	right_door.rotation.y = current_right*1.12
	left_window.position.y = -current_windows*0.43
	right_window.position.y = -current_windows*0.43
	trunk_lid.rotation.x = trunk_rotation_sign*current_trunk*0.93
	for window in rear_windows:
		window.position.y = -current_windows*0.43
	if camera_has_user_view and not drag_active and touch_positions.is_empty():
		camera_idle_time += delta
		if camera_idle_time >= CAMERA_IDLE_RETURN_SECONDS:
			_return_camera_home()
	if camera_transition:
		camera_transition_time += delta
		var progress := clampf(camera_transition_time / CAMERA_TRANSITION_SECONDS, 0.0, 1.0)
		# Match the source camera's half-second QUART / OUT transition.
		var camera_blend := 1.0 - pow(1.0 - progress, 4.0)
		yaw = lerp_angle(camera_start_yaw, camera_goal_yaw, camera_blend)
		pitch = lerpf(camera_start_pitch, camera_goal_pitch, camera_blend)
		distance = lerpf(camera_start_distance, camera_goal_distance, camera_blend)
		if progress >= 1.0:
			yaw = camera_goal_yaw
			pitch = camera_goal_pitch
			distance = camera_goal_distance
			camera_transition = false
		_update_camera()


func _update_camera() -> void:
	if camera == null:
		return
	var target := ORBIT_TARGET
	camera.position = target + Vector3(sin(yaw)*cos(pitch),sin(pitch),-cos(yaw)*cos(pitch))*distance
	camera.look_at(target,Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_positions[event.index] = event.position
			if touch_positions.size() == 1:
				_begin_drag(event.position)
			else:
				drag_distance = 1000.0
				last_pinch_distance = _touch_distance()
		else:
			if touch_positions.size() == 1:
				_end_drag(event.position)
			touch_positions.erase(event.index)
			last_pinch_distance = 0.0
	elif event is InputEventScreenDrag:
		touch_positions[event.index] = event.position
		if touch_positions.size() > 1:
			var separation := _touch_distance()
			if last_pinch_distance > 0.0 and separation > 1.0:
				_note_camera_activity()
				distance = clampf(distance*last_pinch_distance/separation,5.4,11.0)
				_update_camera()
			last_pinch_distance = separation
		else:
			_orbit(event.relative)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_drag(event.position)
			else:
				_end_drag(event.position)
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			_note_camera_activity()
			distance = clampf(distance + (-0.35 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.35),5.4,11.0)
			_update_camera()
	elif event is InputEventMouseMotion and drag_active:
		_orbit(event.relative)
	elif event is InputEventMagnifyGesture:
		_note_camera_activity()
		distance = clampf(distance/event.factor,5.4,11.0)
		_update_camera()


func _touch_distance() -> float:
	var points: Array = touch_positions.values()
	if points.size() < 2:
		return 0.0
	var first: Vector2 = points[0]
	var second: Vector2 = points[1]
	return first.distance_to(second)


func _begin_drag(position_value: Vector2) -> void:
	_note_camera_activity()
	drag_active = true
	press_position = position_value
	drag_distance = 0


func _end_drag(position_value: Vector2) -> void:
	if drag_active and drag_distance < 12.0 and press_position.distance_to(position_value) < 16.0:
		_pick(position_value)
	drag_active = false


func _orbit(relative: Vector2) -> void:
	if not drag_active:
		return
	_note_camera_activity()
	drag_distance += relative.length()
	# Direct manipulation: a feature on the near side follows the horizontal drag.
	# Normalize by the scene size so touch feels consistent across display densities.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	yaw += relative.x / maxf(viewport_size.x, 1.0) * TAU * 0.85
	pitch = clampf(pitch + relative.y / maxf(viewport_size.y, 1.0) * 1.1, 0.08, 0.85)
	_update_camera()


func _pick(screen_position: Vector2) -> void:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin,origin+direction*30)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider != null and collider.has_meta("action"):
		_request_action(str(collider.get_meta("action")))


func _request_action(action: String) -> void:
	if bridge != null:
		bridge.call("requestAction",action)
		return
	match action:
		"toggle_left_door": state["leftDoor"] = 0.0 if float(state["leftDoor"]) > 0.5 else 1.0
		"toggle_right_door": state["rightDoor"] = 0.0 if float(state["rightDoor"]) > 0.5 else 1.0
		"toggle_windows": state["windows"] = 0.0 if float(state["windows"]) > 0.5 else 1.0
		"toggle_trunk": state["trunk"] = 0.0 if float(state["trunk"]) > 0.5 else 1.0
		"toggle_lights": state["lights"] = not bool(state["lights"])
	apply_state(JSON.stringify(state))
