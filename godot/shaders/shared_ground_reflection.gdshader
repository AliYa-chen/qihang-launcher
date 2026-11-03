shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

// Direct port of teslaAppGroundReflection.js. Colors are authored display RGB.
uniform sampler2D reflection_map : filter_linear, repeat_disable;
uniform sampler2D normal_map : filter_linear_mipmap, repeat_enable;
uniform mat4 mirror_view;
uniform mat4 mirror_projection;
uniform vec3 floor_color = vec3(0.96862745);
uniform vec3 fade_center = vec3(0.0);
uniform vec2 viewport_size = vec2(1.0);
uniform float fade_scale = 1.0;
uniform float strength = 0.1;
uniform float ready = 0.0;
uniform float overall_fade = 1.0;
uniform float normal_factor = 0.0;
uniform float texture_repeat = 5.0;
uniform float distortion_pixels = 50.0;
uniform float floor_effect_on_reflection = 0.6;
uniform float reflection_lift = 0.03;
uniform float fade_start = 5.0;
uniform float fade_end = 15.0;
varying vec4 reflection_clip;
varying vec2 floor_uv;
varying vec3 floor_world_position;

vec3 display_to_linear(vec3 color) {
	return mix(pow((color + vec3(0.055)) / 1.055, vec3(2.4)), color / 12.92,
		lessThan(color, vec3(0.04045)));
}

void vertex() {
	vec4 world_position = MODEL_MATRIX * vec4(VERTEX, 1.0);
	floor_world_position = world_position.xyz;
	// PlaneMesh UV differs from Three.PlaneGeometry rotated -PI/2.
	// Reconstruct that exact source floorUv after its explicit V flip.
	floor_uv = vec2(VERTEX.x / 30.0 + 0.5, 0.5 - VERTEX.z / 30.0);
	reflection_clip = mirror_projection * mirror_view * world_position;
}

void fragment() {
	if (ready < 0.5 || overall_fade < 0.01) discard;
	float radial_fade = 1.0 - smoothstep(fade_start, fade_end,
		length(floor_world_position - fade_center) / max(fade_scale, 0.0001));
	if (radial_fade < 0.0001) discard;
	vec2 projected_uv = reflection_clip.xy / reflection_clip.w * 0.5 + 0.5;
	// Godot viewport textures use top-left UV while projection NDC is Y-up.
	projected_uv.y = 1.0 - projected_uv.y;
	vec4 reflected = texture(reflection_map, projected_uv);
	float original_alpha = reflected.a;
	vec2 normal_value = texture(normal_map, floor_uv * texture_repeat).xy * 2.0 - 1.0;
	vec2 uv_offset = distortion_pixels * normal_value * normal_factor / max(viewport_size, vec2(1.0));
	reflected.rgb = texture(reflection_map, projected_uv + uv_offset).rgb;
	reflected.a = original_alpha;
	if (reflection_clip.w <= 0.0 || any(lessThan(projected_uv, vec2(0.0)))
		|| any(greaterThan(projected_uv, vec2(1.0)))) reflected = vec4(0.0);
	vec3 reflected_display = clamp(reflected.rgb, vec3(0.0), vec3(1.0));
	vec3 floor_display = floor_color * mix(1.0, floor_effect_on_reflection, reflected.a);
	vec3 reflection_display = reflected_display * strength + vec3(reflection_lift * reflected.a);
	vec3 composed = max(floor_display + reflection_display, vec3(0.0));
	ALBEDO = OUTPUT_IS_SRGB ? composed : display_to_linear(composed);
	ALPHA = overall_fade * radial_fade;
}
