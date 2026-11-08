shader_type canvas_item;
// Animated menu backdrop: cold vignette, slow drifting haze, faint scanlines and an
// occasional fluorescent flicker. Cheap: a few sin/hash ops per pixel, no textures.

uniform vec4 base_color : source_color = vec4(0.02, 0.025, 0.03, 1.0);
uniform vec4 haze_color : source_color = vec4(0.09, 0.11, 0.12, 1.0);
uniform vec4 accent_color : source_color = vec4(0.5, 0.08, 0.05, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * 0.05;
	float n = noise(uv * 3.0 + vec2(t, t * 0.6)) * 0.6 + noise(uv * 7.0 - vec2(t * 1.3, 0.0)) * 0.4;
	vec3 col = mix(base_color.rgb, haze_color.rgb, n * 0.8);
	// emergency light glow from the lower right
	float glow = smoothstep(0.9, 0.0, distance(uv, vec2(0.85, 0.95))) * (0.6 + 0.4 * sin(TIME * 1.7));
	col += accent_color.rgb * glow * 0.35;
	// scanlines + vignette
	col *= 0.92 + 0.08 * sin(uv.y * 900.0);
	col *= smoothstep(1.1, 0.25, distance(uv, vec2(0.5)));
	float flicker = step(0.985, hash(vec2(floor(TIME * 12.0), 3.0))) * 0.06;
	col += flicker;
	COLOR = vec4(col, 1.0);
}
