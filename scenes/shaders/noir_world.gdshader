shader_type spatial;
render_mode diffuse_lambert, specular_disabled, ambient_light_disabled;

uniform float hi_threshold    : hint_range(0.0, 1.0) = 0.65;  // above = white highlight
uniform float light_threshold : hint_range(0.0, 1.0) = 0.20;  // below = shadow zone
uniform float softness        : hint_range(0.0, 0.15) = 0.05; // blend width — kills WebGL edge flicker
uniform float shadow_lift     : hint_range(0.0, 0.4) = 0.12;  // min brightness — no pure black
uniform float dot_size        : hint_range(0.1, 5.0) = 1.2;   // screentone density
uniform float paper_grain     : hint_range(0.0, 0.1) = 0.03;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	ALBEDO = vec3(1.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndotl = clamp(dot(NORMAL, LIGHT) * ATTENUATION, 0.0, 1.0);

	// 45° rotated sine-wave screentone — manga/comic dot grid
	vec2 pos = FRAGCOORD.xy * dot_size * 0.2;
	float r1 = (pos.x - pos.y) * 0.707;
	float r2 = (pos.x + pos.y) * 0.707;
	float dots = step(0.5, sin(r1) * sin(r2));  // binary 0/1

	// Signed paper grain — lightens and darkens for hand-drawn feel
	float grain = (hash(floor(FRAGCOORD.xy)) * 2.0 - 1.0) * paper_grain;

	// Smooth zone boundaries — prevents crunchy flickering edges in WebGL
	float is_hi  = smoothstep(hi_threshold - softness, hi_threshold + softness, ndotl);
	float is_lit = smoothstep(light_threshold - softness, light_threshold + softness, ndotl);

	// 3-zone palette
	// Shadow: screentone dots on dark background (shadow_lift stops pure black)
	vec3 shadow_color = vec3(shadow_lift + dots * 0.10);
	// Mid-gray: solid with paper grain
	vec3 mid_color    = vec3(clamp(0.45 + grain, 0.0, 1.0));
	// Highlight: pure white with grain
	vec3 hi_color     = vec3(clamp(1.0 + grain, 0.0, 1.0));

	// Layer shadow → mid → white
	vec3 color = mix(shadow_color, mid_color, is_lit);
	color = mix(color, hi_color, is_hi);

	DIFFUSE_LIGHT = clamp(color, 0.0, 1.0);
}
