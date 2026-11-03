extends RefCounted
## Shared studio IBL for the recovered vehicle. No direct light is required.
## create_material() expects the same sRGB colors exposed by BaseMaterial3D.

const SHADER_PATH := "res://shaders/shared_vehicle_ibl.gdshader"
const RADIANCE_PATH := "res://assets/studio-radiance.bin"
const ENVIRONMENT_ENERGY := 4.0
const AMBIENT_ENERGY := 4.0
const SKY_ROTATION := Vector3(0.0, -11.0, 83.0)

var radiance: Cubemap
var opaque_shader: Shader
var transparent_shader: Shader
var materials: Array[ShaderMaterial] = []
var environment_energy: float = ENVIRONMENT_ENERGY
var ambient_energy: float = AMBIENT_ENERGY
var sky_rotation_degrees: Vector3 = SKY_ROTATION
var coordinate_rotation: Basis = Basis.IDENTITY
var world_to_sky: Basis


func _init() -> void:
	radiance = _load_radiance()
	opaque_shader = load(SHADER_PATH)
	transparent_shader = Shader.new()
	transparent_shader.code = opaque_shader.code.replace(
		"// QIHANG_ALPHA_OUTPUT", "ALPHA = clamp(alpha_value * texel.a, 0.0, 1.0);").replace("cull_back", "cull_disabled")
	_update_sky_basis()


func create_material(source: BaseMaterial3D, overrides: Dictionary = {}) -> ShaderMaterial:
	var converted := ShaderMaterial.new()
	var source_color: Color = overrides.get("albedo", source.albedo_color)
	var source_alpha: float = float(overrides.get("alpha", source_color.a))
	var transparent: bool = source_alpha < 0.999 or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	converted.shader = transparent_shader if transparent else opaque_shader
	converted.resource_name = "SharedStudio_" + source.resource_name
	converted.render_priority = 5 if transparent else source.render_priority
	converted.set_shader_parameter("radiance_map", radiance)
	converted.set_shader_parameter("environment_energy", environment_energy)
	converted.set_shader_parameter("ambient_energy", ambient_energy)
	converted.set_shader_parameter("ambient_sky_contribution", 1.0)
	converted.set_shader_parameter("ambient_color", Vector3.ZERO)
	converted.set_shader_parameter("world_to_sky", world_to_sky)
	converted.set_shader_parameter("base_color", source_color)
	converted.set_shader_parameter("alpha_value", source_alpha)
	converted.set_shader_parameter("roughness_value", float(overrides.get("roughness", source.roughness)))
	converted.set_shader_parameter("metallic_value", float(overrides.get("metallic", source.metallic)))
	converted.set_shader_parameter("specular_value", source.metallic_specular)
	converted.set_shader_parameter("emission_color", Vector3(source.emission.r, source.emission.g, source.emission.b) if source.emission_enabled else Vector3.ZERO)
	converted.set_shader_parameter("emission_energy", source.emission_energy_multiplier)
	converted.set_shader_parameter("has_base_texture", source.albedo_texture != null)
	if source.albedo_texture != null:
		converted.set_shader_parameter("base_texture", source.albedo_texture)
	converted.set_shader_parameter("uv_scale", Vector2(source.uv1_scale.x, source.uv1_scale.y))
	converted.set_shader_parameter("uv_offset", Vector2(source.uv1_offset.x, source.uv1_offset.y))
	set_paint_look(converted, bool(overrides.get("pearl", false)), overrides)
	materials.append(converted)
	return converted


func update_color(material: ShaderMaterial, color: Color) -> void:
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("alpha_value", color.a)


func set_paint_look(material: ShaderMaterial, enabled: bool, overrides: Dictionary = {}) -> void:
	material.set_shader_parameter("pearl_look", enabled)
	material.set_shader_parameter("diffuse_fill", float(overrides.get("diffuse_fill", 0.5)))
	material.set_shader_parameter("diffuse_fill_value", float(overrides.get("diffuse_fill_value", 0.5)))
	material.set_shader_parameter("look_exposure", float(overrides.get("look_exposure", 1.8)))
	material.set_shader_parameter("highlight_rolloff", float(overrides.get("highlight_rolloff", 1.0)))
	material.set_shader_parameter("look_gamma", float(overrides.get("look_gamma", 0.85)))


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
