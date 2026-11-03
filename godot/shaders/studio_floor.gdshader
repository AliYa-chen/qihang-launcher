shader_type spatial;
render_mode unshaded, cull_disabled;

// A continuous neutral studio floor. The soft contact footprint is deliberately
// independent of the orbit camera, unlike the former blue display pedestal.
uniform vec4 floor_color : source_color = vec4(0.0862745, 0.0901961, 0.0941176, 1.0);
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	float pool = exp(-dot(p / vec2(6.5, 8.5), p / vec2(6.5, 8.5)));
	vec2 q = abs(p) - vec2(0.56, 1.62);
	float footprint = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - 0.25;
	float shadow = (1.0 - smoothstep(-0.18, 0.48, footprint)) * 0.52;
	vec2 wheel = (abs(p) - vec2(0.86, 1.43)) / vec2(0.22, 0.33);
	shadow = max(shadow, exp(-dot(wheel, wheel) * 1.9) * 0.75);
	vec3 color = floor_color.rgb + vec3(0.038) * pool;
	ALBEDO = color * (1.0 - shadow);
}
