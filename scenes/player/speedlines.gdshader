shader_type canvas_item;
render_mode unshaded;

// Keep the existing material API; noise and mask controls are legacy fields.
uniform sampler2D noise : repeat_enable;
uniform vec4 line_color : source_color = vec4(1.0);
uniform float line_count : hint_range(0.0, 2.0, 0.05) = 0.5;
uniform float line_density : hint_range(0.0, 1.0) = 0.0;
uniform float line_faloff : hint_range(0.0, 1.0) = 0.25;
uniform float mask_size : hint_range(0.0, 1.0) = 0.1;
uniform float mask_edge : hint_range(0.0, 1.0) = 0.5;
uniform float animation_speed : hint_range(1.0, 20.0) = 10.0;
uniform float aspect_ratio : hint_range(0.25, 4.0) = 1.777778;
uniform float motion_time = -1.0;
uniform float line_width : hint_range(0.5, 3.0) = 1.0;

float lane_hash(float lane, float salt) {
	return fract(sin(lane * 12.9898 + salt * 78.233) * 43758.5453);
}

void fragment() {
	float density = clamp(line_density, 0.0, 1.0);
	vec2 position = (UV - vec2(0.5)) * vec2(max(aspect_ratio, 0.001), 1.0);
	float radius = length(position);
	// Radius is measured in viewport-height units, keeping the aiming circle
	// round on widescreen and portrait viewports. The central 0.30 stays clear.
	float periphery = smoothstep(0.30, 0.46, radius);
	float count = floor(mix(24.0, 96.0, clamp(line_count * 0.5, 0.0, 1.0)));
	float angle = fract(atan(position.y, position.x + 0.000001) / 6.283185307 + 0.5);
	float lane_position = angle * count;
	float lane = floor(lane_position);
	float seed = lane_hash(lane, 1.0);
	float axis = mix(0.23, 0.77, lane_hash(lane, 2.0));
	float distance_to_ray = abs(fract(lane_position) - axis) * 6.283185307 * radius / count;
	float pixel = SCREEN_PIXEL_SIZE.y;
	float width = pixel * line_width * mix(0.55, 1.15, seed);
	float ray = 1.0 - smoothstep(width, width + pixel, distance_to_ray);

	// Each lane has a stable direction. A smooth segment travels outward;
	// there is no frame-stepped angular rotation or texture-noise flicker.
	float t = motion_time < 0.0 ? TIME : motion_time;
	float cycle = fract(t * animation_speed * 0.07 * mix(0.8, 1.25, seed) + lane_hash(lane, 3.0));
	float outer_radius = length(vec2(aspect_ratio * 0.5, 0.5)) + 0.22;
	float head = mix(0.30, outer_radius, cycle);
	float tail = head - mix(0.09, 0.22, lane_hash(lane, 4.0));
	float segment = smoothstep(tail, tail + 0.04, radius)
		* (1.0 - smoothstep(head - 0.012, head, radius));
	float presence = 1.0 - smoothstep(density * 0.75 + 0.02, density * 0.75 + 0.13, lane_hash(lane, 5.0));
	float alpha = ray * segment * presence * periphery * density * 0.55 * line_color.a;
	COLOR = vec4(line_color.rgb, clamp(alpha, 0.0, 0.55));
}
