shader_type spatial;
// Facility architecture surface (walls / floors / ceilings), mobile friendly.
//  * PBR texture set: albedo + normal + ORM (AO, roughness, metallic)
//  * macro variation from a low-frequency world-space noise (breaks visible tiling)
//  * wall grime that thickens near the floor, optional painted safety stripe
// 4 texture samples, no branches.

render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 0.5;
uniform float normal_strength = 1.0;
uniform float roughness_mul = 1.0;
uniform float macro_amount = 0.35;
uniform float floor_grime = 0.45;
uniform vec4 grime_color : source_color = vec4(0.08, 0.07, 0.06, 1.0);
uniform vec4 stripe_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float stripe_height = 1.1;
uniform float stripe_width = 0.09;
// 0 = Low (no normal map / detail noise), 1 = Medium, 2 = High. Set by Settings.
global uniform float ns_quality;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 alb = texture(albedo_tex, uv).rgb * tint.rgb;
	vec3 orm = texture(orm_tex, uv).rgb;
	vec2 mp = world_pos.xz * 0.045 + world_pos.y * 0.03;
	float macro = texture(macro_noise, mp).r;
	float macro2 = 0.5;
	if (ns_quality > 0.5) {
		macro2 = texture(macro_noise, mp * 3.7 + vec2(0.37, 0.11)).r;
	}
	float var = (macro - 0.5) * macro_amount;
	alb *= 1.0 + var;
	// grime gathers at the base of walls (floors sit at multiples of 6 m)
	float wall = 1.0 - step(0.6, abs(world_normal.y));
	float h = mod(world_pos.y + 12.0, 6.0);
	float g = wall * clamp(1.0 - h * 1.4, 0.0, 1.0) * floor_grime * (0.6 + macro2 * 0.8);
	g += clamp((macro2 - 0.62) * 2.0, 0.0, 1.0) * macro_amount;
	alb = mix(alb, grime_color.rgb, clamp(g, 0.0, 0.85));
	float stripe = (1.0 - step(stripe_width, abs(h - stripe_height))) * wall * stripe_color.a;
	alb = mix(alb, stripe_color.rgb * (0.85 + macro * 0.3), stripe);
	ALBEDO = alb;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = clamp(orm.g * roughness_mul + g * 0.25, 0.05, 1.0);
	METALLIC = orm.b * (1.0 - g);
	if (ns_quality > 0.5) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
}
