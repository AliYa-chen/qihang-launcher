shader_type spatial;
render_mode unshaded, cull_back, blend_mix, depth_draw_opaque, shadows_disabled;

// Ordinary-vehicle IBL branch from Tesla Desk's shared material renderer.
// Radiance mip levels store encoded RGB; GGX integration is performed offline.
// This shader contains no additional fill light, tone curve or paint softening.
uniform samplerCube radiance_map : filter_linear_mipmap;
uniform float environment_energy = 4.0;
uniform float ambient_energy = 4.0;
uniform float ambient_sky_contribution = 1.0;
uniform vec3 ambient_color = vec3(0.0);
uniform mat3 world_to_sky = mat3(1.0);

// No source_color hint: these uniforms and texture samples are display values.
uniform vec4 base_color = vec4(0.09411765, 0.09411765, 0.09411765, 1.0);
uniform float roughness_value = 0.2;
uniform float metallic_value = 0.25;
uniform float specular_value = 0.5;
uniform float alpha_value = 1.0;
uniform bool has_base_texture = false;
uniform sampler2D base_texture : filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);

uniform bool has_roughness_texture = false;
uniform sampler2D roughness_texture : filter_linear_mipmap, repeat_enable;
uniform vec4 roughness_channel = vec4(0.0, 1.0, 0.0, 0.0);
uniform bool has_metallic_texture = false;
uniform sampler2D metallic_texture : filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_channel = vec4(0.0, 0.0, 1.0, 0.0);

uniform bool has_ao_texture = false;
uniform sampler2D ao_texture : filter_linear_mipmap, repeat_enable;
uniform vec4 ao_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform bool ao_uv2 = false;
uniform bool ao_flip_v = false;
uniform float ao_strength = 1.0;
uniform float ao_light_affect = 0.0;

uniform bool has_normal_texture = false;
uniform sampler2D normal_texture : filter_linear_mipmap, repeat_enable;
uniform float normal_scale = 1.0;

uniform bool has_emission = false;
uniform vec3 emission_color = vec3(0.0);
uniform float emission_energy = 1.0;
uniform bool has_emission_texture = false;
uniform sampler2D emission_texture : filter_linear_mipmap, repeat_enable;

varying vec3 world_normal;
varying vec3 world_position;

vec3 display_to_linear(vec3 color) {
	return mix(pow((max(color, vec3(0.0)) + vec3(0.055)) / 1.055, vec3(2.4)), color / 12.92,
		lessThan(color, vec3(0.04045)));
}

vec3 linear_to_display(vec3 color) {
	return mix(1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - vec3(0.055), color * 12.92,
		lessThan(color, vec3(0.0031308)));
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec2 material_uv = UV * uv_scale + uv_offset;
	vec3 normal_world = normalize(world_normal);
	if (!FRONT_FACING) {
		normal_world = -normal_world;
	}
	if (has_normal_texture) {
		// Derivative TBN also supports recovered meshes that have UVs but no
		// authored tangent buffer, matching Three's tangent-less normal path.
		vec3 q0 = dFdx(world_position);
		vec3 q1 = dFdy(world_position);
		vec2 st0 = dFdx(material_uv);
		vec2 st1 = dFdy(material_uv);
		vec3 q1perp = cross(q1, normal_world);
		vec3 q0perp = cross(normal_world, q0);
		vec3 tangent = q1perp * st0.x + q0perp * st1.x;
		vec3 bitangent = q1perp * st0.y + q0perp * st1.y;
		float determinant_scale = max(dot(tangent, tangent), dot(bitangent, bitangent));
		if (determinant_scale > 0.0000001) {
			float inverse_scale = inversesqrt(determinant_scale);
			vec3 sampled_normal = texture(normal_texture, material_uv).rgb * 2.0 - 1.0;
			sampled_normal.xy *= normal_scale;
			normal_world = normalize(mat3(tangent * inverse_scale, bitangent * inverse_scale, normal_world) * sampled_normal);
		}
	}
	vec3 view_world = normalize(CAMERA_POSITION_WORLD - world_position);
	float ndotv = clamp(dot(normal_world, view_world), 0.0, 1.0);
	vec4 texel = vec4(1.0);
	if (has_base_texture) {
		texel = texture(base_texture, material_uv);
	}
	vec3 albedo = max(base_color.rgb * texel.rgb, vec3(0.0));
	float roughness = max(roughness_value, 0.0);
	float metallic = max(metallic_value, 0.0);
	if (has_roughness_texture) {
		roughness *= dot(texture(roughness_texture, material_uv), roughness_channel);
	}
	if (has_metallic_texture) {
		metallic *= dot(texture(metallic_texture, material_uv), metallic_channel);
	}
	vec3 f0 = mix(vec3(0.16 * specular_value * specular_value), albedo, metallic);
	vec3 fresnel = f0 + (max(vec3(1.0 - roughness), f0) - f0) * pow(1.0 - ndotv, 5.0);
	vec3 diffuse_direction = normalize(world_to_sky * normal_world);
	vec3 specular_direction = normalize(world_to_sky * reflect(-view_world, normal_world));
	// The original GLES2 specular lookup alone flips Z after sky rotation.
	specular_direction.z *= -1.0;
	vec3 sky_diffuse = textureLod(radiance_map, diffuse_direction, 4.0).rgb;
	vec3 sky_specular = textureLod(radiance_map, specular_direction, roughness * 6.0).rgb;
	sky_diffuse *= environment_energy * (vec3(1.0) - fresnel);
	vec3 ambient = mix(ambient_color, sky_diffuse, ambient_sky_contribution);
	ambient *= ambient_energy * albedo * (1.0 - metallic);
	vec4 r = roughness * vec4(-1.0, -0.0275, -0.572, 0.022) + vec4(1.0, 0.0425, 1.04, -0.04);
	float a004 = min(r.x * r.x, exp2(-9.28 * ndotv)) * r.x + r.y;
	vec2 brdf = vec2(-1.04, 1.04) * a004 + r.zw;
	vec3 specular = sky_specular * environment_energy * (brdf.x * fresnel + brdf.y);
	if (has_ao_texture) {
		vec2 ao_coords = (ao_uv2 ? UV2 : UV) * uv_scale + uv_offset;
		if (ao_flip_v) {
			ao_coords.y = 1.0 - ao_coords.y;
		}
		float sampled_ao = dot(texture(ao_texture, ao_coords), ao_channel);
		float ambient_occlusion = (sampled_ao - 1.0) * ao_strength + 1.0;
		ambient *= ambient_occlusion;
		specular *= mix(1.0, ambient_occlusion, ao_light_affect);
	}
	vec3 display_result = max(ambient + specular, vec3(0.0));
	if (has_emission) {
		// Source renderer adds emissive radiance after the environment EOTF.
		vec3 emissive_linear = display_to_linear(emission_color) * emission_energy;
		if (has_emission_texture) {
			emissive_linear *= display_to_linear(texture(emission_texture, material_uv).rgb);
		}
		display_result = linear_to_display(display_to_linear(display_result) + emissive_linear);
	}
	// Compatibility performs an EOTF after fragment() and OETF at framebuffer
	// output. Forward backends instead expect a linear ALBEDO result here.
	ALBEDO = OUTPUT_IS_SRGB ? display_result : display_to_linear(display_result);
	// QIHANG_ALPHA_OUTPUT
}
