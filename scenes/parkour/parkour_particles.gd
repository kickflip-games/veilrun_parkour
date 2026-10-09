class_name ParkourParticles
extends Node3D
## Small world-space feedback pool for the Compatibility/Web parkour courses.
## Presentation only: the helper never changes player movement or collision.

const BURST_POOL_SIZE := 4
const MAX_BURST_PARTICLES := 20
const TRAIL_PARTICLES := 20
const AIR_RUSH_PARTICLES := 12
const TRAIL_START_SPEED := 12.0
const GRAPHITE := Color(0.2, 0.2, 0.2, 1)

var bursts_emitted := 0
var bursts_ignored := 0
var reset_count := 0
var last_burst_kind := ""
var last_burst_position := Vector3.ZERO
var trail_active := false
var air_rush_active := false

var _player: CharacterBody3D
var _camera: Camera3D
var _player_has_active_flag := false
var _strength := 1.0
var _active := true
var _burst_emitters: Array[CPUParticles3D] = []
var _burst_remaining: Array[float] = []
var _next_burst := 0
var _trail: CPUParticles3D
var _air_rush: CPUParticles3D
var _cube: BoxMesh
var _streak: BoxMesh
var _rush_streak: BoxMesh
var _fade: Gradient
var _shrink: Curve
var _trail_level := 0.0

func _ready() -> void:
	# Pause freezes both the lifetime bookkeeping and the CPU particle simulation.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build_emitters()

func configure(player: CharacterBody3D) -> void:
	_player = player
	_active = true
	_player_has_active_flag = false
	_camera = null
	if is_instance_valid(_player):
		_camera = _player.get_node_or_null("Camera3D") as Camera3D
		for property in _player.get_property_list():
			if property.name == "gameplay_active":
				_player_has_active_flag = true
				break

func set_strength(value: float) -> void:
	_strength = clampf(value, 0.0, 1.5)
	if is_zero_approx(_strength):
		reset_effects()

func emit_burst(kind: String, position: Vector3, normal: Vector3 = Vector3.UP, strength: float = 1.0) -> void:
	if not _can_emit() or strength <= 0.0:
		bursts_ignored += 1
		return
	_build_emitters()
	var emitter := _burst_emitters[_next_burst]
	var slot := _next_burst
	_next_burst = (_next_burst + 1) % BURST_POOL_SIZE
	_clear_emitter(emitter)
	var gain := clampf(_strength * strength, 0.15, 1.5)
	var outward := normal.normalized() if not normal.is_zero_approx() else Vector3.UP
	emitter.global_transform = Transform3D(Basis.IDENTITY, position + outward * 0.05)
	emitter.mesh = _cube
	emitter.amount = clampi(roundi(16.0 * gain), 12, MAX_BURST_PARTICLES)
	var tint := GRAPHITE if kind in ["jump", "land", "landing"] else Color.WHITE
	emitter.color = Color(tint.r, tint.g, tint.b, minf(gain, 1.0))
	emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	emitter.emission_ring_axis = outward
	emitter.emission_ring_radius = 0.32 * gain
	emitter.emission_ring_inner_radius = 0.16 * gain
	emitter.emission_ring_height = 0.04
	emitter.direction = outward
	emitter.spread = 65.0
	emitter.gravity = Vector3(0, -3.5, 0)
	emitter.flatness = 0.0
	emitter.lifetime = 0.3
	emitter.initial_velocity_min = 0.8 * gain
	emitter.initial_velocity_max = 2.0 * gain
	emitter.radial_accel_min = 0.5
	emitter.radial_accel_max = 2.0 * gain
	emitter.scale_amount_min = 0.55 * gain
	emitter.scale_amount_max = 1.1 * gain
	emitter.particle_flag_align_y = false
	match kind:
		"land", "landing":
			# The horizon-level camera is above the feet. Place dust at its lower
			# view edges, with impact strength controlling opacity and fleck size.
			emitter.emission_ring_radius = 2.6
			emitter.emission_ring_inner_radius = 1.8
			emitter.color.a = minf(0.45 + gain * 0.55, 1.0)
			emitter.scale_amount_min = 0.55 * sqrt(gain)
			emitter.scale_amount_max = 1.1 * sqrt(gain)
			emitter.lifetime = 0.4
			emitter.initial_velocity_min = 1.8 * gain
			emitter.initial_velocity_max = 3.6 * gain
			emitter.radial_accel_min = 6.0 * gain
			emitter.radial_accel_max = 10.0 * gain
		"spring", "spring_launch":
			emitter.mesh = _streak
			emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			emitter.emission_sphere_radius = 0.2
			emitter.spread = 22.0
			emitter.lifetime = 0.4
			emitter.initial_velocity_min = 3.0 * gain
			emitter.initial_velocity_max = 5.0 * gain
			emitter.radial_accel_max = 0.0
			emitter.particle_flag_align_y = true
		"grapple", "release", "arrival", "grapple_release", "grapple_arrival", "hook_release", "hook_arrival", "anchor_release", "anchor_arrival":
			emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			emitter.emission_sphere_radius = 0.22 * gain
			emitter.spread = 150.0
			emitter.gravity = Vector3(0, -1.0, 0)
			emitter.lifetime = 0.35
			emitter.initial_velocity_min = 1.2 * gain
			emitter.initial_velocity_max = 3.2 * gain
			emitter.radial_accel_max = 0.0
		"checkpoint", "finish":
			emitter.emission_ring_radius = (0.85 if kind == "checkpoint" else 1.15) * gain
			emitter.emission_ring_inner_radius = 0.5 * gain
			emitter.lifetime = 0.45 if kind == "checkpoint" else 0.55
			emitter.initial_velocity_max = 3.0 * gain
			emitter.radial_accel_max = 4.0 * gain
	_burst_remaining[slot] = emitter.lifetime + 0.1
	emitter.visible = true
	emitter.restart()
	emitter.emitting = true
	bursts_emitted += 1
	last_burst_kind = kind
	last_burst_position = position

func update_trail(delta: float, speed: float, active: bool, contact_normal: Vector3 = Vector3.ZERO) -> void:
	_active = active
	if not _can_emit():
		_stop_trails()
		return
	_build_emitters()
	if not is_instance_valid(_player) or speed < TRAIL_START_SPEED:
		_stop_trails()
		return
	var target := clampf((speed - TRAIL_START_SPEED) / 20.0, 0.0, 1.0)
	_trail_level = lerpf(_trail_level, target, 1.0 - exp(-12.0 * maxf(delta, 0.0)))
	var normal := contact_normal.normalized() if not contact_normal.is_zero_approx() else Vector3.UP
	var horizontal := Vector3(_player.velocity.x, 0, _player.velocity.z)
	var backward := -horizontal.normalized() if not horizontal.is_zero_approx() else _player.global_basis.z
	_trail.global_transform = Transform3D(Basis.IDENTITY, _player.global_position - Vector3.UP * 0.48 + normal * 0.06)
	_trail.direction = (backward + normal * 0.4).normalized()
	_trail.gravity = Vector3(0, -2.0, 0) if not contact_normal.is_zero_approx() else Vector3.ZERO
	_trail.initial_velocity_min = 0.8
	_trail.initial_velocity_max = lerpf(1.5, 3.0, _trail_level)
	_trail.scale_amount_min = lerpf(0.35, 0.65, _trail_level) * _strength
	_trail.scale_amount_max = lerpf(0.7, 1.2, _trail_level) * _strength
	var tint := GRAPHITE if not contact_normal.is_zero_approx() and normal.y > 0.8 else Color.WHITE
	_trail.color = Color(tint.r, tint.g, tint.b, minf(_strength, 1.0))
	_trail.visible = true
	_trail.emitting = true
	trail_active = true
	_update_air_rush()

func _update_air_rush() -> void:
	if not is_instance_valid(_camera):
		return
	var forward := -_camera.global_basis.z.normalized()
	_air_rush.global_transform = Transform3D(Basis.IDENTITY, _camera.global_position + forward * 4.0)
	_air_rush.emission_ring_axis = forward
	_air_rush.direction = -forward
	_air_rush.scale_amount_min = 0.55 * _strength
	_air_rush.scale_amount_max = 0.9 * _strength
	_air_rush.color = Color(1, 1, 1, minf(0.65 * _strength, 1.0))
	_air_rush.visible = true
	_air_rush.emitting = true
	air_rush_active = true

func _stop_trails() -> void:
	if trail_active and is_instance_valid(_trail):
		_clear_emitter(_trail)
	if air_rush_active and is_instance_valid(_air_rush):
		_clear_emitter(_air_rush)
	trail_active = false
	air_rush_active = false
	_trail_level = 0.0

func reset_effects() -> void:
	for emitter in _burst_emitters:
		_clear_emitter(emitter)
	for index in range(_burst_remaining.size()):
		_burst_remaining[index] = 0.0
	if is_instance_valid(_trail):
		_clear_emitter(_trail)
	if is_instance_valid(_air_rush):
		_clear_emitter(_air_rush)
	trail_active = false
	air_rush_active = false
	_trail_level = 0.0
	_next_burst = 0
	reset_count += 1

func _process(delta: float) -> void:
	# Finishing stops new emissions, while the already emitted finish burst fades.
	if _strength <= 0.0:
		return
	for index in range(_burst_remaining.size()):
		if _burst_remaining[index] <= 0.0:
			continue
		_burst_remaining[index] = maxf(0.0, _burst_remaining[index] - delta)
		if is_zero_approx(_burst_remaining[index]):
			_clear_emitter(_burst_emitters[index])

func _can_emit() -> bool:
	if not is_inside_tree() or _strength <= 0.0 or not _active or get_tree().paused:
		return false
	return not _player_has_active_flag or (is_instance_valid(_player) and bool(_player.get("gameplay_active")))

func _clear_emitter(emitter: CPUParticles3D) -> void:
	# Restart clears old world-space particles; hidden/disabled prevents a new cycle.
	emitter.visible = false
	emitter.emitting = false
	emitter.restart()
	emitter.emitting = false

func _build_emitters() -> void:
	if not _burst_emitters.is_empty():
		return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	_cube = BoxMesh.new()
	_cube.size = Vector3(0.065, 0.065, 0.065)
	_cube.material = material
	_streak = BoxMesh.new()
	_streak.size = Vector3(0.04, 0.18, 0.04)
	_streak.material = material
	_rush_streak = BoxMesh.new()
	_rush_streak.size = Vector3(0.015, 0.09, 0.015)
	_rush_streak.material = material
	_fade = Gradient.new()
	_fade.offsets = PackedFloat32Array([0.0, 0.65, 1.0])
	# White RGB in the fade ramp multiplies the emitter tint without bleaching it.
	_fade.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	_shrink = Curve.new()
	_shrink.add_point(Vector2(0, 1))
	_shrink.add_point(Vector2(0.65, 0.8))
	_shrink.add_point(Vector2(1, 0.05))
	for index in range(BURST_POOL_SIZE):
		var emitter := _new_emitter("Burst%d" % index, true, 16)
		_burst_emitters.append(emitter)
		_burst_remaining.append(0.0)
	_trail = _new_emitter("SpeedTrail", false, TRAIL_PARTICLES)
	_trail.lifetime = 0.22
	_trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_trail.emission_sphere_radius = 0.12
	_trail.spread = 30.0
	_air_rush = _new_emitter("AirRush", false, AIR_RUSH_PARTICLES)
	_air_rush.mesh = _rush_streak
	_air_rush.lifetime = 0.35
	_air_rush.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_air_rush.emission_ring_radius = 2.3
	_air_rush.emission_ring_inner_radius = 1.7
	_air_rush.emission_ring_height = 0.05
	_air_rush.initial_velocity_min = 8.0
	_air_rush.initial_velocity_max = 12.0
	_air_rush.spread = 6.0
	_air_rush.gravity = Vector3.ZERO
	_air_rush.particle_flag_align_y = true

func _new_emitter(node_name: String, one_shot: bool, count: int) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.name = node_name
	emitter.emitting = false
	emitter.visible = false
	emitter.one_shot = one_shot
	emitter.amount = count
	emitter.local_coords = false
	emitter.top_level = true
	emitter.mesh = _cube
	emitter.color_ramp = _fade
	emitter.scale_amount_curve = _shrink
	emitter.explosiveness = 0.95 if one_shot else 0.0
	emitter.lifetime_randomness = 0.2
	emitter.randomness = 0.3
	emitter.fixed_fps = 30
	emitter.fract_delta = true
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	add_child(emitter)
	return emitter
