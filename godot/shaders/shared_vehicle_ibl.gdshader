shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_opaque, shadows_disabled;

// Environment response ported from Tesla Desk's shared renderer, itself adapted
// from Godot 3.2.2 GLES2 scene.glsl. Keep the display-space BRDF and encoded GGX
// cubemap; Godot 4's ordinary ambient light uses a different energy convention.
uniform samplerCube radiance_map : filter_linear_mipmap;
uniform float environment_energy = 4.0;
uniform float ambient_energy = 4.0;
uniform float ambient_sky_contribution = 1.0;
uniform vec3 ambient_color = vec3(0.0);
uniform mat3 world_to_sky = mat3(1.0);

// These colors intentionally have no source_color hint: values are encoded sRGB.
uniform vec4 base_color = vec4(0.09411765, 0.09411765, 0.09411765, 1.0);
uniform float roughness_value = 0.2;
uniform float metallic_value = 0.25;
uniform float specular_value = 0.5;
uniform float alpha_value = 1.0;
uniform vec3 emission_color = vec3(0.0);
uniform float emission_energy = 1.0;
uniform bool has_base_texture = false;
uniform sampler2D base_texture : filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
// Optional C236 display adaptation. Other materials retain the source BRDF.
uniform bool pearl_look = false;
uniform float diffuse_fill = 0.5;
uniform float diffuse_fill_value = 0.5;
uniform float look_exposure = 1.8;
uniform float highlight_rolloff = 1.0;
uniform float look_gamma = 0.85;

varying vec3 world_normal;
varying vec3 world_position;

vec3 display_to_linear(vec3 color) {
	return mix(pow((color + vec3(0.055)) / 1.055, vec3(2.4)), color / 12.92,
		lessThan(color, vec3(0.04045)));
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 normal_world = normalize(world_normal);
	vec3 view_world = normalize(CAMERA_POSITION_WORLD - world_position);
	float ndotv = clamp(dot(normal_world, view_world), 0.0, 1.0);
	vec4 texel = vec4(1.0);
	if (has_base_texture) {
		texel = texture(base_texture, UV * uv_scale + uv_offset);
	}
	vec3 albedo = max(base_color.rgb * texel.rgb, vec3(0.0));
	float roughness = max(roughness_value, 0.0);
	float metallic = max(metallic_value, 0.0);
	vec3 f0 = mix(vec3(0.16 * specular_value * specular_value), albedo, metallic);
	vec3 fresnel = f0 + (max(vec3(1.0 - roughness), f0) - f0) * pow(1.0 - ndotv, 5.0);
	vec3 diffuse_direction = normalize(world_to_sky * normal_world);
	vec3 specular_direction = normalize(world_to_sky * reflect(-view_world, normal_world));
	// Native Godot GLES2's reflection lookup flips Z after inverse sky rotation.
	specular_direction.z *= -1.0;
	vec3 sky_diffuse = textureLod(radiance_map, diffuse_direction, 4.0).rgb;
	vec3 sky_specular = textureLod(radiance_map, specular_direction, roughness * 6.0).rgb;
	if (pearl_look) {
		sky_diffuse = mix(sky_diffuse, vec3(diffuse_fill_value), clamp(diffuse_fill, 0.0, 1.0));
	}
	sky_diffuse *= environment_energy * (vec3(1.0) - fresnel);
	vec3 ambient = mix(ambient_color, sky_diffuse, ambient_sky_contribution);
	ambient *= ambient_energy * albedo * (1.0 - metallic);
	vec4 r = roughness * vec4(-1.0, -0.0275, -0.572, 0.022) + vec4(1.0, 0.0425, 1.04, -0.04);
	float a004 = min(r.x * r.x, exp2(-9.28 * ndotv)) * r.x + r.y;
	vec2 brdf = vec2(-1.04, 1.04) * a004 + r.zw;
	vec3 specular = sky_specular * environment_energy * (brdf.x * fresnel + brdf.y);
	vec3 display_result = max(ambient + specular + emission_color * emission_energy, vec3(0.0));
	if (pearl_look) {
		vec3 exposed = display_result * look_exposure;
		vec3 rolled = vec3(1.0) - exp(-exposed);
		display_result = pow(max(mix(exposed, rolled, clamp(highlight_rolloff, 0.0, 1.0)), vec3(0.0)), vec3(look_gamma));
	}
	// GLES3 Compatibility converts ALBEDO from display to linear after fragment()
	// and converts the final framebuffer back. Forward renderers expect linear.
	ALBEDO = OUTPUT_IS_SRGB ? display_result : display_to_linear(display_result);
	// QIHANG_ALPHA_OUTPUT
}
