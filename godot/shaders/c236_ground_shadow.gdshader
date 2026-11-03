shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

// Original KZB RGBA texture on its original six-vertex mesh and source UVs.
// No alpha gain, invented footprint, tint, blur, or reshaping is applied.
uniform sampler2D shadow_texture : source_color, filter_linear_mipmap, repeat_disable;
void fragment() {
	vec4 texel = texture(shadow_texture, UV);
	ALBEDO = texel.rgb;
	ALPHA = texel.a;
}
