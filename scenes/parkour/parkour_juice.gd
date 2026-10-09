extends Node
## Presentation only: never changes the body, inputs, timers or grapple heading.
const Settings = preload("res://scenes/parkour/presentation_settings.gd")
const Particles = preload("res://scenes/parkour/parkour_particles.gd")
const DISTORTION = preload("res://scenes/parkour/speed_distortion.gdshader")
const MAX_ROLL := deg_to_rad(7.0)
const FOV_BOOST := 14.0

var player: CharacterBody3D
var particles
var distortion: ColorRect
var distortion_material: ShaderMaterial
var speed_amount := 0.0
var motion_time := 0.0
var pulse := 0.0
var effect_strength := 1.0
var landing_count := 0
var jump_count := 0
var launch_count := 0
var wind_player: AudioStreamPlayer
var _fov_boost := FOV_BOOST
var _roll_limit := MAX_ROLL
var _camera: Camera3D
var _base_position := Vector3.ZERO
var _base_fov := 75.0
var _previous_yaw := 0.0
var _was_grounded := false
var _incoming_vertical := 0.0
var _contact_normal := Vector3.ZERO
var _kick := 0.0
var _kick_velocity := 0.0
var _landing_cooldown := 0.0

func configure(body: CharacterBody3D) -> void:
	player = body
	_camera = player.camera
	_base_position = _camera.position
	_base_fov = _camera.fov
	_fov_boost = float(player.get("camera_fov_boost"))
	_roll_limit = deg_to_rad(float(player.get("camera_roll_limit_degrees")))
	wind_player = SoundManager.create_wind_player(self)
	_previous_yaw = player.rotation.y
	Settings.load_settings()
	effect_strength = Settings.effects_strength
	particles = Particles.new()
	particles.name = "MovementParticles"
	add_child(particles)
	particles.configure(player)
	particles.set_strength(effect_strength)
	# The world is copied before the HUD. Text, reticle and touch controls stay crisp.
	var world_effect := CanvasLayer.new()
	world_effect.name = "WorldSpeedEffect"
	world_effect.layer = 0
	add_child(world_effect)
	distortion = ColorRect.new()
	distortion.name = "SpeedDistortion"
	distortion.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	distortion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	distortion_material = ShaderMaterial.new()
	distortion_material.shader = DISTORTION
	distortion.material = distortion_material
	world_effect.add_child(distortion)
	# Avoid sharing speed density between scene instances or retries.
	player.hud.speedlines.material = player.hud.speedlines.material.duplicate()
	reset_effects()

func update_effects(delta: float) -> void:
	if get_tree().paused:
		return
	var strength: float = Settings.effects_strength
	if not is_equal_approx(strength, effect_strength):
		effect_strength = strength
		particles.set_strength(strength)
		if strength == 0.0:
			reset_effects()
	var active: bool = player.gameplay_active and not player._is_debug_fly_active()
	var horizontal_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var feedback_speed := player.velocity.length() if bool(player.get("use_momentum_pull")) else horizontal_speed
	var target := smoothstep(9.0, 32.0, feedback_speed) if active else 0.0
	var blend := 1.0 - exp(-6.0 * delta)
	speed_amount = lerpf(speed_amount, target, blend)
	if active:
		motion_time += delta
	pulse = move_toward(pulse, 0.0, delta * 2.5)
	_landing_cooldown = maxf(0.0, _landing_cooldown - delta)
	var yaw_delta := wrapf(player.rotation.y - _previous_yaw, -PI, PI)
	_previous_yaw = player.rotation.y
	var turn_rate := clampf(yaw_delta / maxf(delta, 0.001), -3.0, 3.0)
	var local_velocity: Vector3 = player.global_basis.inverse() * player.velocity
	var local_normal: Vector3 = player.global_basis.inverse() * _contact_normal
	var bank_lean := local_normal.x * deg_to_rad(4.0) if _contact_normal.y > 0.2 and _contact_normal.y < 0.8 else 0.0
	var roll := -clampf(local_velocity.x / 24.0, -1.0, 1.0) * deg_to_rad(5.0)
	roll += -turn_rate * deg_to_rad(1.0) * speed_amount + bank_lean * speed_amount
	roll = clampf(roll, -_roll_limit, _roll_limit) * effect_strength if active else 0.0
	player.camera_tilt = lerpf(player.camera_tilt, roll, 1.0 - exp(-9.0 * delta))
	_camera.rotation.z = player.camera_tilt
	_camera.fov = lerpf(_camera.fov, _base_fov + _fov_boost * speed_amount * effect_strength, blend)
	# A damped dip on takeoff/landing gives weight without random camera jitter.
	# Substeps keep the presentation spring stable at low render frame rates.
	var remaining := minf(delta, 0.15)
	while remaining > 0.0:
		var step := minf(remaining, 1.0 / 120.0)
		_kick_velocity += (-100.0 * _kick - 17.0 * _kick_velocity) * step
		_kick += _kick_velocity * step
		remaining -= step
	_kick = clampf(_kick, -0.12, 0.06)
	_camera.position = _base_position + Vector3.UP * _kick * effect_strength
	var size := player.get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	distortion_material.set_shader_parameter("strength", speed_amount * 0.45 * effect_strength)
	distortion_material.set_shader_parameter("pulse", pulse * effect_strength if active else 0.0)
	distortion_material.set_shader_parameter("aspect_ratio", aspect)
	distortion_material.set_shader_parameter("motion_time", motion_time)
	distortion.visible = active and effect_strength > 0.0 and (speed_amount > 0.005 or pulse > 0.005)
	var streak_material: ShaderMaterial = player.hud.speedlines.material
	streak_material.set_shader_parameter("line_density", speed_amount * 0.45 * effect_strength)
	streak_material.set_shader_parameter("aspect_ratio", aspect)
	streak_material.set_shader_parameter("motion_time", motion_time)
	player.hud.speedlines.visible = active and speed_amount * effect_strength > 0.02
	particles.update_trail(delta, horizontal_speed, active, _contact_normal)
	if active and speed_amount > 0.01 and effect_strength > 0.0:
		wind_player.volume_db = lerpf(-42.0, -26.0, speed_amount) + linear_to_db(effect_strength)
		if not wind_player.playing:
			wind_player.play()
	else:
		wind_player.stop()

func begin_physics_step() -> void:
	_was_grounded = player.is_on_floor()
	_incoming_vertical = player.velocity.y

func finish_physics_step() -> void:
	_contact_normal = player.get_floor_normal() if player.is_on_floor() else Vector3.ZERO
	if _contact_normal.is_zero_approx():
		for index in range(player.get_slide_collision_count()):
			var normal: Vector3 = player.get_slide_collision(index).get_normal()
			if normal.y > 0.2 and normal.y < 0.8:
				_contact_normal = normal
				break
	if not _was_grounded and player.is_on_floor() and _incoming_vertical < -2.5 and player.gameplay_active and _landing_cooldown <= 0.0:
		landing_count += 1
		_landing_cooldown = 0.18
		var weight := clampf(-_incoming_vertical / 14.0, 0.25, 1.0)
		_kick_velocity -= lerpf(0.5, 1.7, weight)
		particles.emit_burst("landing", _feet(), _contact_normal, weight)

func jump() -> void:
	jump_count += 1
	_kick_velocity -= 0.65
	particles.emit_burst("jump", _feet(), player.get_floor_normal(), 0.6)

func spring_launch() -> void:
	launch_count += 1
	_kick_velocity -= 1.2
	pulse = maxf(pulse, 0.22)
	particles.emit_burst("spring", _feet(), Vector3.UP, 1.0)

func grapple_start() -> void:
	SoundManager.play_pull_cue(SoundManager.SFX_PULL_ON)
	pulse = maxf(pulse, 0.12)
	particles.emit_burst("grapple", player.global_position + Vector3.UP * 0.6, -player.global_basis.z, 0.65)

func grapple_release() -> void:
	SoundManager.play_pull_cue(SoundManager.SFX_PULL_RELEASE)
	particles.emit_burst("release", player.global_position + Vector3.UP * 0.6, Vector3.UP, 0.4)

func grapple_arrival(position: Vector3) -> void:
	pulse = maxf(pulse, 0.14)
	particles.emit_burst("arrival", position, Vector3.UP, 0.75)

func gate_passed(finish := false) -> void:
	particles.emit_burst("finish" if finish else "checkpoint", player.global_position + Vector3.UP, Vector3.UP, 1.0 if finish else 0.6)

func _feet() -> Vector3:
	return player.global_position + Vector3.DOWN * 0.45

func reset_effects() -> void:
	if is_instance_valid(wind_player):
		wind_player.stop()
	speed_amount = 0.0
	pulse = 0.0
	_kick = 0.0
	_kick_velocity = 0.0
	_contact_normal = Vector3.ZERO
	_landing_cooldown = 0.25
	_previous_yaw = player.rotation.y
	player.camera_tilt = 0.0
	_camera.position = _base_position
	_camera.rotation.z = 0.0
	_camera.fov = _base_fov
	player.hud.speedlines.material.set_shader_parameter("line_density", 0.0)
	player.hud.speedlines.hide()
	distortion_material.set_shader_parameter("strength", 0.0)
	distortion_material.set_shader_parameter("pulse", 0.0)
	distortion.hide()
	particles.reset_effects()
