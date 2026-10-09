extends RefCounted
## Acceleration solver only: the CharacterBody owns collision, targets and release.

const AirControl = preload("res://scenes/parkour/air_control.gd")

var acceleration := 72.0
var speed_limit := 32.0
var tangent_retention := 1.0
var upward_scale := 1.1
var air_acceleration := 24.0
var air_turn_speed := 120.0
var air_braking := 56.0
var elapsed := 0.0
var last_force := Vector3.ZERO
var _air_control = AirControl.new()

func reset() -> void:
	elapsed = 0.0
	last_force = Vector3.ZERO

func step(velocity: Vector3, offset: Vector3, steering: Vector3, gravity: float, delta: float) -> Vector3:
	elapsed += delta
	if offset.is_zero_approx():
		return velocity
	var radial := offset.normalized()
	var along := radial * velocity.dot(radial)
	var tangent := velocity - along
	# Retention is per second, so changing the physics rate cannot change damping.
	tangent *= pow(clampf(tangent_retention, 0.9, 1.0), delta)
	var pull_direction := radial
	if pull_direction.y > 0.0:
		pull_direction.y *= upward_scale
	last_force = pull_direction * acceleration + Vector3.DOWN * gravity
	# Force adds to the existing radial and tangential momentum. The total cap
	# bounds speed without imposing a direction toward the anchor.
	var result := (along + tangent + last_force * delta).limit_length(speed_limit)
	if not steering.is_zero_approx():
		_air_control.acceleration = air_acceleration
		_air_control.turn_degrees_per_second = air_turn_speed
		_air_control.braking = air_braking
		var horizontal := Vector3(result.x, 0.0, result.z)
		var budget := sqrt(maxf(0.0, speed_limit * speed_limit - result.y * result.y))
		var controlled: Vector3 = _air_control.step(horizontal, steering, 8.0, budget, delta)
		if delta > 0.0:
			last_force += (controlled - horizontal) / delta
		result.x = controlled.x
		result.z = controlled.z
	return result
