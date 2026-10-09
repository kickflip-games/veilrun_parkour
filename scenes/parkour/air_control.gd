extends RefCounted
## Horizontal control: redirect earned momentum without adding sideways speed.

var acceleration := 32.0
var turn_degrees_per_second := 240.0
var braking := 56.0

func step(horizontal: Vector3, input: Vector3, walk_speed: float, speed_budget: float, delta: float) -> Vector3:
	var wish := Vector3(input.x, 0.0, input.z).limit_length(1.0)
	var strength := wish.length()
	if strength < 0.001 or delta <= 0.0:
		return horizontal
	var direction := wish / strength
	var speed := horizontal.length()
	var target_speed := minf(walk_speed * strength, speed_budget)
	if speed < 0.001:
		return direction * minf(target_speed, acceleration * strength * delta)
	var heading := horizontal / speed
	# Opposing input is a brake, followed by reversal once momentum is spent.
	if heading.dot(direction) < -0.35:
		var time_to_stop := speed / maxf(braking * strength, 0.001)
		if time_to_stop >= delta:
			return heading * minf(speed_budget, maxf(0.0, speed - braking * strength * delta))
		return direction * minf(target_speed, acceleration * strength * (delta - time_to_stop))
	var angle := heading.signed_angle_to(direction, Vector3.UP)
	var max_turn := deg_to_rad(turn_degrees_per_second) * strength * delta
	heading = heading.rotated(Vector3.UP, clampf(angle, -max_turn, max_turn))
	if speed < target_speed:
		speed = minf(target_speed, speed + acceleration * strength * delta)
	return heading * minf(speed, speed_budget)
