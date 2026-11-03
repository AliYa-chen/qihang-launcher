extends Node3D
## Source: Tesla Desk teslaAppGroundReflection.js / teslaAppBackgroundGlow.js.
## Node layers: car=1, floor/reflection/source shadow=2, background glow=4.
## The mirror captures only layer 1, never its own floor or glow.

const DAY_BACKGROUND := Color("#F7F7F7")
const NIGHT_BACKGROUND := Color("#161718")
const FLOOR_SIZE := 30.0
const FADE_START := 5.0
const FADE_END := 15.0
const REFLECTION_SCALE := 0.5
const REFLECTION_STRENGTH := 0.1
const FLOOR_EFFECT := 0.6
const REFLECTION_LIFT := 0.03
const TEXTURE_REPEAT := 5.0
const NORMAL_FACTOR := 0.3
const DISTORTION_PIXELS := 50.0
const GLOW_HALF_WIDTH := 8.2
const GLOW_HALF_HEIGHT := 4.3
const GLOW_DISTANCE := 16.3
const GLOW_CENTER_HEIGHT := 1.0
const GLOW_REFERENCE_DISTANCE := 15.8
const GLOW_OPACITY := 0.26
const GLOW_FADE_SECONDS := 0.3
const GLOW_ELEVATION_SPEED := 6.0
const PAINT_HIGHLIGHTS := {
	"PearlWhite": Color("#DADADA"),
	"GlacierBlue": Color("#42599C"),
	"StealthGrey": Color("#929BA7"),
}

var mirror_viewport: SubViewport
var mirror_camera: Camera3D
var floor: MeshInstance3D
var source_shadow: MeshInstance3D
var glow: MeshInstance3D
var floor_material: ShaderMaterial
var glow_material: ShaderMaterial
var source_camera: Camera3D
var body_root: Node3D
var night_mode: bool = false
var initialized: bool = false
var mirror_frame_pending: bool = false
var mirror_frame_ready: bool = false
var glow_fade: float = 0.0
var glow_elevation_fade: float = 1.0
var paint_key: String = "PearlWhite"
var world_environment: Environment


func initialize(car_root: Node3D, camera: Camera3D) -> void:
	if initialized:
		return
	body_root = car_root
	source_camera = camera
	_assign_car_layer(body_root)
	source_camera.cull_mask = 7
	var world := get_viewport().find_world_3d()
	world_environment = world.environment
	mirror_viewport = SubViewport.new()
	mirror_viewport.name = "SharedGroundMirror"
	mirror_viewport.size = Vector2i.ONE
	mirror_viewport.world_3d = world
	mirror_viewport.own_world_3d = false
	mirror_viewport.transparent_bg = true
	mirror_viewport.use_hdr_2d = false
	mirror_viewport.msaa_3d = Viewport.MSAA_DISABLED
	mirror_viewport.msaa_2d = Viewport.MSAA_DISABLED
	mirror_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	mirror_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	mirror_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(mirror_viewport)
	mirror_camera = Camera3D.new()
	mirror_camera.name = "MirrorCamera"
	mirror_camera.cull_mask = 1
	mirror_camera.current = true
	var capture_environment := Environment.new()
	capture_environment.background_mode = Environment.BG_COLOR
	capture_environment.background_color = Color(0, 0, 0, 0)
	capture_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	capture_environment.ambient_light_energy = 0.0
	capture_environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	capture_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	capture_environment.tonemap_exposure = 1.0
	mirror_camera.environment = capture_environment
	mirror_viewport.add_child(mirror_camera)
	_create_floor()
	_create_source_shadow()
	_create_glow()
	initialized = true
	set_theme(night_mode)
	set_paint_key(paint_key)
	update(0.0)
	RenderingServer.frame_post_draw.connect(_after_frame)


func set_theme(night_mode_value: bool) -> void:
	night_mode = night_mode_value
	var background := NIGHT_BACKGROUND if night_mode else DAY_BACKGROUND
	if world_environment != null:
		world_environment.background_mode = Environment.BG_COLOR
		world_environment.background_color = background
	if floor_material != null:
		floor_material.set_shader_parameter("floor_color", Vector3(background.r, background.g, background.b))
		floor_material.set_shader_parameter("strength", REFLECTION_STRENGTH)


func set_paint_key(value: String) -> void:
	if not PAINT_HIGHLIGHTS.has(value):
		push_warning("SharedStudio received unsupported source paint key: " + value)
		return
	paint_key = value
	if glow_material != null:
		var color: Color = PAINT_HIGHLIGHTS[paint_key]
		glow_material.set_shader_parameter("glow_color", Vector3(color.r, color.g, color.b))


func update(delta: float) -> void:
	if not initialized or source_camera == null or body_root == null:
		return
	_update_floor_transform()
	_update_mirror()
	_update_glow(maxf(delta, 0.0))


func _create_floor() -> void:
	floor_material = ShaderMaterial.new()
	floor_material.shader = load("res://shaders/shared_ground_reflection.gdshader")
	floor_material.render_priority = -1
	floor_material.set_shader_parameter("reflection_map", mirror_viewport.get_texture())
	floor_material.set_shader_parameter("strength", REFLECTION_STRENGTH)
	floor_material.set_shader_parameter("floor_effect_on_reflection", FLOOR_EFFECT)
	floor_material.set_shader_parameter("reflection_lift", REFLECTION_LIFT)
	floor_material.set_shader_parameter("texture_repeat", TEXTURE_REPEAT)
	floor_material.set_shader_parameter("distortion_pixels", DISTORTION_PIXELS)
	floor_material.set_shader_parameter("fade_start", FADE_START)
	floor_material.set_shader_parameter("fade_end", FADE_END)
	floor_material.set_shader_parameter("overall_fade", 1.0)
	floor_material.set_shader_parameter("ready", 0.0)
	var normal := _load_image_texture("res://assets/studio-floor-normal.jpg")
	if normal != null:
		floor_material.set_shader_parameter("normal_map", normal)
		floor_material.set_shader_parameter("normal_factor", NORMAL_FACTOR)
	else:
		var neutral := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		neutral.fill(Color(128.0/255.0, 128.0/255.0, 1.0, 1.0))
		floor_material.set_shader_parameter("normal_map", ImageTexture.create_from_image(neutral))
		floor_material.set_shader_parameter("normal_factor", 0.0)
	var plane := PlaneMesh.new()
	plane.size = Vector2(FLOOR_SIZE, FLOOR_SIZE)
	floor = MeshInstance3D.new()
	floor.name = "TeslaAppGroundReflection"
	floor.mesh = plane
	floor.material_override = floor_material
	floor.layers = 2
	floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor)


func _create_glow() -> void:
	glow_material = ShaderMaterial.new()
	glow_material.shader = load("res://shaders/shared_background_glow.gdshader")
	glow_material.render_priority = 0
	glow_material.set_shader_parameter("overall_fade", 0.0)
	var plane := QuadMesh.new()
	plane.size = Vector2(2.0, 2.0)
	glow = MeshInstance3D.new()
	glow.name = "TeslaAppBackgroundGlow"
	glow.mesh = plane
	glow.material_override = glow_material
	glow.layers = 4
	glow.visible = false
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)


func _create_source_shadow() -> void:
	var text := FileAccess.get_file_as_string("res://assets/c236/Ground_Shadow.mesh.json")
	var decoded: Variant = JSON.parse_string(text)
	if not decoded is Dictionary:
		push_warning("Original C236 ground shadow mesh unavailable")
		return
	var data: Dictionary = decoded
	var positions: Array = data.get("positions", [])
	var normals: Array = data.get("normals", [])
	var uvs: Array = data.get("source_uv", [])
	var source_indices: Array = data.get("indices", [])
	if positions.size() != normals.size() or positions.size() != uvs.size() or positions.is_empty():
		push_warning("Original C236 ground shadow mesh arrays invalid")
		return
	var vertices := PackedVector3Array()
	var vertex_normals := PackedVector3Array()
	var texture_uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for item in positions:
		vertices.append(Vector3(float(item[0]), float(item[1]), float(item[2])))
	for item in normals:
		vertex_normals.append(Vector3(float(item[0]), float(item[1]), float(item[2])))
	for item in uvs:
		texture_uv.append(Vector2(float(item[0]), float(item[1])))
	for item in source_indices:
		indices.append(int(item))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = vertex_normals
	arrays[Mesh.ARRAY_TEX_UV] = texture_uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var original_texture := _load_image_texture("res://assets/c236/Ground_Shadow.png")
	if original_texture == null:
		return
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/c236_ground_shadow.gdshader")
	material.render_priority = 0
	material.set_shader_parameter("shadow_texture", original_texture)
	source_shadow = MeshInstance3D.new()
	source_shadow.name = "C236_OriginalGroundShadow"
	source_shadow.mesh = mesh
	source_shadow.material_override = material
	source_shadow.layers = 2
	source_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(source_shadow)


func _assign_car_layer(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = 1
	for child in node.get_children():
		_assign_car_layer(child)


func _update_floor_transform() -> void:
	var source_transform := body_root.global_transform
	var source_scale := source_transform.basis.get_scale()
	var orientation := source_transform.basis.orthonormalized()
	var floor_basis := Basis(orientation.x * absf(source_scale.x), orientation.y, orientation.z * absf(source_scale.z))
	floor.global_transform = Transform3D(floor_basis, source_transform.origin)
	floor_material.set_shader_parameter("fade_center", source_transform.origin)
	floor_material.set_shader_parameter("fade_scale", maxf(absf(source_scale.x), 0.0001))
	if source_shadow != null:
		# Source KZB +Z front is rotated with the recovered vehicle, not the floor.
		source_shadow.global_transform = source_transform * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)


func _update_mirror() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var wanted := Vector2i(maxi(1, floori(viewport_size.x * REFLECTION_SCALE)), maxi(1, floori(viewport_size.y * REFLECTION_SCALE)))
	if mirror_viewport.size != wanted:
		mirror_viewport.size = wanted
		mirror_frame_ready = false
		floor_material.set_shader_parameter("ready", 0.0)
	floor_material.set_shader_parameter("viewport_size", viewport_size)
	var plane_position := floor.global_position
	var normal := floor.global_basis.y.normalized()
	var active_transform := source_camera.global_transform
	var camera_height := normal.dot(active_transform.origin - plane_position)
	if camera_height <= 0.0001:
		floor_material.set_shader_parameter("ready", 0.0)
		return
	var mirror_position := active_transform.origin - normal * (2.0 * camera_height)
	var x_axis := active_transform.basis.x.normalized()
	var z_axis := active_transform.basis.z.normalized()
	z_axis = (z_axis - normal * (2.0 * z_axis.dot(normal))).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	z_axis = x_axis.cross(y_axis).normalized()
	mirror_camera.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), mirror_position)
	mirror_camera.projection = source_camera.projection
	mirror_camera.keep_aspect = source_camera.keep_aspect
	mirror_camera.fov = source_camera.fov
	mirror_camera.size = source_camera.size
	mirror_camera.near = source_camera.near
	mirror_camera.far = source_camera.far
	mirror_camera.h_offset = source_camera.h_offset
	mirror_camera.v_offset = -source_camera.v_offset
	mirror_camera.frustum_offset = Vector2(source_camera.frustum_offset.x, -source_camera.frustum_offset.y)
	floor_material.set_shader_parameter("mirror_view", mirror_camera.global_transform.affine_inverse())
	floor_material.set_shader_parameter("mirror_projection", mirror_camera.get_camera_projection())
	floor_material.set_shader_parameter("ready", 1.0 if mirror_frame_ready else 0.0)
	mirror_frame_pending = true


func _after_frame() -> void:
	if mirror_frame_pending:
		mirror_frame_ready = true
		mirror_frame_pending = false


func _update_glow(delta: float) -> void:
	var target_fade := 1.0 if night_mode else 0.0
	glow_fade = clampf(glow_fade + signf(target_fade - glow_fade) * minf(absf(target_fade - glow_fade), delta / GLOW_FADE_SECONDS), 0.0, 1.0)
	var source_transform := body_root.global_transform
	var source_scale := maxf(absf(source_transform.basis.get_scale().x), 0.0001)
	var world_center := source_transform * Vector3(0.0, GLOW_CENTER_HEIGHT, 0.0)
	var camera_position := source_camera.global_position
	var to_center := world_center - camera_position
	var distance_to_center := maxf(to_center.length(), 0.01)
	to_center /= distance_to_center
	var facing := -to_center
	var up := Vector3.UP - facing * facing.y
	if up.length_squared() < 0.0001:
		glow.visible = false
		return
	up = up.normalized()
	var right := up.cross(facing).normalized()
	var beyond := GLOW_DISTANCE * source_scale
	var reference := GLOW_REFERENCE_DISTANCE * source_scale
	var size_scale := (distance_to_center + beyond) / distance_to_center * reference / (reference + beyond)
	var position_value := camera_position + to_center * (distance_to_center + beyond)
	var display_scale := Vector3(GLOW_HALF_WIDTH * source_scale * size_scale, GLOW_HALF_HEIGHT * source_scale * size_scale, 1.0)
	glow.global_transform = Transform3D(Basis(right * display_scale.x, up * display_scale.y, facing), position_value)
	var camera_z := source_camera.global_basis.z
	var looking_down := camera_z.y / maxf(camera_z.length(), 0.0001)
	var desired := 1.0 - smoothstep(0.6, 0.85, looking_down)
	glow_elevation_fade = lerpf(glow_elevation_fade, desired, minf(delta * GLOW_ELEVATION_SPEED, 1.0))
	var opacity := glow_fade * glow_elevation_fade * GLOW_OPACITY
	glow_material.set_shader_parameter("overall_fade", opacity)
	glow.visible = night_mode and opacity > 0.0001


func _load_image_texture(path: String) -> ImageTexture:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	var result := image.load_jpg_from_buffer(bytes) if path.get_extension().to_lower() in ["jpg", "jpeg"] else image.load_png_from_buffer(bytes)
	if result != OK:
		push_warning("SharedStudio image decode failed: " + path)
		return null
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_after_frame):
		RenderingServer.frame_post_draw.disconnect(_after_frame)
