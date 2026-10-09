shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform float aspect_ratio : hint_range(0.25, 4.0) = 1.777778;
uniform float motion_time = -1.0;

void fragment() {
	vec2 sample_uv = SCREEN_UV;
	float t = motion_time < 0.0 ? TIME : motion_time;
	float impulse = clamp(pulse, 0.0, 1.0) * (0.9 + 0.1 * cos(t * 8.0));
	// Even fully driven controls stay within a small peripheral warp. The
	// center retains its original coordinates; colour uses one screen sample.
	float bend = clamp(strength, 0.0, 1.0) * 0.020 + impulse * 0.007;
	if (bend > 0.0) {
		float aspect = max(aspect_ratio, 0.001);
		vec2 position = (SCREEN_UV - vec2(0.5)) * vec2(aspect, 1.0);
		float radius = length(position);
		float maximum_radius = length(vec2(aspect * 0.5, 0.5));
		float edge = smoothstep(0.30, 0.85, radius);
		float radial_weight = dot(position, position) / (maximum_radius * maximum_radius);
		// Sample slightly inward, avoiding exposed borders at every strength.
		sample_uv += (vec2(0.5) - SCREEN_UV) * bend * edge * radial_weight;
		vec2 margin = SCREEN_PIXEL_SIZE * 0.5;
		sample_uv = clamp(sample_uv, margin, vec2(1.0) - margin);
	}
	// strength=0 and pulse=0 leave SCREEN_UV and sampled RGBA unchanged.
	COLOR = texture(screen_texture, sample_uv);
}
