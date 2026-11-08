shader_type canvas_item;
// Damage / low-health vignette. No screen read => cheap on mobile.

uniform float intensity : hint_range(0.0, 1.5) = 0.0;
uniform vec4 tint : source_color = vec4(0.55, 0.02, 0.02, 1.0);

void fragment() {
	float d = distance(UV, vec2(0.5));
	float v = smoothstep(0.35, 0.85, d) * intensity;
	COLOR = vec4(tint.rgb, clamp(v, 0.0, 0.9));
}
