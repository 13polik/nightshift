shader_type canvas_item;
// Downed-state desaturation. Reads the screen, so the HUD only shows this rect while the
// local player is downed.

uniform float amount : hint_range(0.0, 1.0) = 0.8;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(c, vec3(g) * 0.8, amount), 1.0);
}
