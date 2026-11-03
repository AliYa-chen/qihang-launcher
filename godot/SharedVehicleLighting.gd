extends RefCounted
## Tesla Desk's ordinary-vehicle display-space IBL response and source controls.
## Colors follow BaseMaterial3D's sRGB-facing color properties.

const SHADER_PATH := "res://shaders/shared_vehicle_ibl.gdshader"
const RADIANCE_PATH := "res://assets/studio-radiance.bin"
const ENVIRONMENT_ENERGY := 4.0
const AMBIENT_ENERGY := 4.0
const SKY_ROTATION := Vector3(0.0, -11.0, 83.0)

var radiance: Cubemap
var shader_variants: Dictionary = {}
var shader_source: String
var materials: Array[ShaderMaterial] = []
var environment_energy: float = ENVIRONMENT_ENERGY
var ambient_energy: float = AMBIENT_ENERGY
var sky_rotation_degrees: Vector3 = SKY_ROTATION
var coordinate_rotation: Basis = Basis.IDENTITY
var world_to_sky: Basis


func _init() -> void:
	radiance = _load_radiance()
	shader_source = load(SHADER_PATH).code
	_update_sky_basis()


func create_material(source: BaseMaterial3D, overrides: Dictionary = {}) -> ShaderMaterial:
	var converted := ShaderMaterial.new()
	converted.resource_name = "SharedStudio_" + source.resource_name
	update_material(converted, source, overrides)
	materials.append(converted)
	return converted


func update_material(converted: ShaderMaterial, source: BaseMaterial3D, overrides: Dictionary = {}) -> void:
	var source_color: Color = overrides.get("albedo", source.albedo_color)
	var source_alpha: float = float(overrides.get("alpha", source_color.a))
	var transparent: bool = source_alpha < 0.999 or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	converted.shader = _get_shader(transparent, int(overrides.get("cull_mode", source.cull_mode)), int(overrides.get("depth_draw_mode", source.depth_draw_mode)), int(overrides.get("blend_mode", source.blend_mode)))
	converted.render_priority = int(overrides.get("render_priority", source.render_priority))
	converted.set_shader_parameter("radiance_map", radiance)
	converted.set_shader_parameter("environment_energy", environment_energy)
	converted.set_shader_parameter("ambient_energy", ambient_energy)
	converted.set_shader_parameter("ambient_sky_contribution", float(overrides.get("ambient_sky_contribution", 1.0)))
	converted.set_shader_parameter("ambient_color", overrides.get("ambient_color", Vector3.ZERO))
	converted.set_shader_parameter("world_to_sky", world_to_sky)
	converted.set_shader_parameter("base_color", source_color)
	converted.set_shader_parameter("alpha_value", source_alpha)
	converted.set_shader_parameter("roughness_value", float(overrides.get("roughness", source.roughness)))
	converted.set_shader_parameter("metallic_value", float(overrides.get("metallic", source.metallic)))
	converted.set_shader_parameter("specular_value", float(overrides.get("specular", source.metallic_specular)))
	converted.set_shader_parameter("uv_scale", overrides.get("uv_scale", Vector2(source.uv1_scale.x, source.uv1_scale.y)))
	converted.set_shader_parameter("uv_offset", overrides.get("uv_offset", Vector2(source.uv1_offset.x, source.uv1_offset.y)))
	_set_texture(converted, "base", overrides.get("base_texture", source.albedo_texture))
	_set_texture(converted, "roughness", overrides.get("roughness_texture", source.roughness_texture))
	_set_texture(converted, "metallic", overrides.get("metallic_texture", source.metallic_texture))
	converted.set_shader_parameter("roughness_channel", _channel_mask(int(overrides.get("roughness_channel", source.roughness_texture_channel))))
	converted.set_shader_parameter("metallic_channel", _channel_mask(int(overrides.get("metallic_channel", source.metallic_texture_channel))))
	var ao_map: Texture2D = overrides.get("ao_texture", source.ao_texture if source.ao_enabled else null)
	_set_texture(converted, "ao", ao_map)
	converted.set_shader_parameter("ao_channel", _channel_mask(int(overrides.get("ao_channel", source.ao_texture_channel))))
	converted.set_shader_parameter("ao_uv2", bool(overrides.get("ao_uv2", source.ao_on_uv2)))
	converted.set_shader_parameter("ao_flip_v", bool(overrides.get("ao_flip_v", false)))
	converted.set_shader_parameter("ao_strength", float(overrides.get("ao_strength", 1.0)))
	converted.set_shader_parameter("ao_light_affect", float(overrides.get("ao_light_affect", source.ao_light_affect)))
	var normal_map: Texture2D = overrides.get("normal_texture", source.normal_texture if source.normal_enabled else null)
	_set_texture(converted, "normal", normal_map)
	converted.set_shader_parameter("normal_scale", float(overrides.get("normal_scale", source.normal_scale)))
	var emission_enabled := bool(overrides.get("emission_enabled", source.emission_enabled))
	converted.set_shader_parameter("has_emission", emission_enabled)
	var emission: Color = overrides.get("emission", source.emission)
	converted.set_shader_parameter("emission_color", Vector3(emission.r, emission.g, emission.b))
	converted.set_shader_parameter("emission_energy", float(overrides.get("emission_energy", source.emission_energy_multiplier)))
	_set_texture(converted, "emission", overrides.get("emission_texture", source.emission_texture))


func update_color(material: ShaderMaterial, color: Color) -> void:
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("alpha_value", color.a)


func _set_texture(material: ShaderMaterial, prefix: String, texture: Texture2D) -> void:
	material.set_shader_parameter("has_" + prefix + "_texture", texture != null)
	if texture != null:
		material.set_shader_parameter(prefix + "_texture", texture)


func _channel_mask(channel: int) -> Vector4:
	match channel:
		1: return Vector4(0, 1, 0, 0)
		2: return Vector4(0, 0, 1, 0)
		3: return Vector4(0, 0, 0, 1)
		4: return Vector4(0.3333333, 0.3333333, 0.3333333, 0)
		_: return Vector4(1, 0, 0, 0)


func _get_shader(transparent: bool, cull_mode: int, depth_mode: int, blend_mode: int) -> Shader:
	var key := str(transparent) + ":" + str(cull_mode) + ":" + str(depth_mode) + ":" + str(blend_mode)
	if shader_variants.has(key):
		return shader_variants[key]
	var code := shader_source
	if transparent:
		code = code.replace("// QIHANG_ALPHA_OUTPUT", "ALPHA = clamp(alpha_value * texel.a, 0.0, 1.0);")
	if cull_mode == BaseMaterial3D.CULL_FRONT:
		code = code.replace("cull_back", "cull_front")
	elif cull_mode == BaseMaterial3D.CULL_DISABLED:
		code = code.replace("cull_back", "cull_disabled")
	if depth_mode == BaseMaterial3D.DEPTH_DRAW_ALWAYS:
		code = code.replace("depth_draw_opaque", "depth_draw_always")
	elif depth_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED:
		code = code.replace("depth_draw_opaque", "depth_draw_never")
	match blend_mode:
		BaseMaterial3D.BLEND_MODE_ADD: code = code.replace("blend_mix", "blend_add")
		BaseMaterial3D.BLEND_MODE_SUB: code = code.replace("blend_mix", "blend_sub")
		BaseMaterial3D.BLEND_MODE_MUL: code = code.replace("blend_mix", "blend_mul")
	var shader := Shader.new()
	shader.code = code
	shader_variants[key] = shader
	return shader


func set_environment(env_energy: float = ENVIRONMENT_ENERGY, amb_energy: float = AMBIENT_ENERGY, rotation_degrees: Vector3 = SKY_ROTATION) -> void:
	environment_energy = maxf(0.0, env_energy)
	ambient_energy = maxf(0.0, amb_energy)
	sky_rotation_degrees = rotation_degrees
	_update_sky_basis()
	for material in materials:
		material.set_shader_parameter("environment_energy", environment_energy)
		material.set_shader_parameter("ambient_energy", ambient_energy)
		material.set_shader_parameter("world_to_sky", world_to_sky)


func set_coordinate_rotation(rotation: Basis) -> void:
	coordinate_rotation = rotation.orthonormalized()
	_update_sky_basis()
	for material in materials:
		material.set_shader_parameter("world_to_sky", world_to_sky)


func _update_sky_basis() -> void:
	world_to_sky = (coordinate_rotation * Basis.from_euler(sky_rotation_degrees * PI / 180.0, EULER_ORDER_YXZ)).inverse()


func _load_radiance() -> Cubemap:
	var file := FileAccess.open(RADIANCE_PATH, FileAccess.READ)
	if file == null:
		push_error("Shared studio radiance file is missing")
		return null
	var magic := file.get_buffer(8).get_string_from_ascii()
	var size := file.get_32()
	var levels := file.get_32()
	var faces := file.get_32()
	var face_bytes := file.get_32()
	if magic != "QIBL0001" or size != 256 or levels != 9 or faces != 6 or face_bytes != 349524:
		push_error("Shared studio radiance header is invalid")
		return null
	var images: Array[Image] = []
	for face in range(faces):
		var bytes := file.get_buffer(face_bytes)
		if bytes.size() != face_bytes:
			push_error("Shared studio radiance payload is truncated")
			return null
		images.append(Image.create_from_data(size, size, true, Image.FORMAT_RGBA8, bytes))
	var cube := Cubemap.new()
	var error := cube.create_from_images(images)
	if error != OK:
		push_error("Could not upload shared studio cubemap: " + str(error))
		return null
	return cube
