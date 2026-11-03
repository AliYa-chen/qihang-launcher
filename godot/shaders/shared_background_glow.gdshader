shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

// Direct source palette and authored falloff; no lighting or tone adjustment.
uniform vec3 glow_color = vec3(0.85490196);
uniform float overall_fade = 0.0;

vec3 display_to_linear(vec3 color) {
	return mix(pow((color + vec3(0.055)) / 1.055, vec3(2.4)), color / 12.92,
		lessThan(color, vec3(0.04045)));
}

void fragment() {
	float radius = length(abs(UV - vec2(0.5)) * 2.0);
	float distance_fade = 1.0 - smoothstep(0.5, 1.0, radius);
	ALBEDO = OUTPUT_IS_SRGB ? glow_color : display_to_linear(glow_color);
	ALPHA = overall_fade * distance_fade;
}
