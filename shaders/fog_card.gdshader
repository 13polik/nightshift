shader_type spatial;
// Low-lying drifting fog card. Unshaded, additive-free alpha blend, two scrolling noise
// samples and radial edge fade - no depth texture reads, so it is cheap on mobile GPUs.

render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 fog_color : source_color = vec4(0.55, 0.6, 0.65, 1.0);
uniform float density = 0.22;

void fragment() {
	vec2 uv = UV;
	float edge = clamp(1.0 - length(uv - 0.5) * 2.0, 0.0, 1.0);
	float n1 = texture(noise_tex, uv * 0.6 + vec2(TIME * 0.012, TIME * 0.007)).r;
	float n2 = texture(noise_tex, uv * 1.3 - vec2(TIME * 0.018, -TIME * 0.01)).r;
	float a = smoothstep(0.35, 0.85, n1 * 0.6 + n2 * 0.5) * edge * edge * density;
	ALBEDO = fog_color.rgb;
	ALPHA = a;
}
