extends SceneTree
## Integrated presentation checks with the actual Riptide player and physics.
## Godot --headless --path . --script tests/validate_parkour_juice.gd --fixed-fps 60
## Only this process's in-memory preference is changed; no preference is saved.
const Settings = preload("res://scenes/parkour/presentation_settings.gd")
const STEP := 1.0 / 60.0

var course
var player
var juice
var particles
var flat: StaticBody3D
var failures: Array[String] = []
var metrics: Dictionary = {}
var checks := 0
var saved_strength := 1.0
var save_path := ""
var preferences_before := PackedByteArray()
var preferences_existed := false

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for _tick in range(count):
		await physics_frame

func render_frames(count: int) -> void:
	for _tick in range(count):
		await process_frame

func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)

func setting_bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(Settings.SAVE_PATH) if FileAccess.file_exists(Settings.SAVE_PATH) else PackedByteArray()

func shader_value(material: ShaderMaterial, parameter: String) -> float:
	return float(material.get_shader_parameter(parameter))

func emitters() -> Array[Node]:
	return particles.find_children("*", "CPUParticles3D", true, false)

func live_emitters() -> int:
	var live := 0
	for emitter in emitters():
		if emitter.visible or emitter.emitting:
			live += 1
	return live

func screen_neutral() -> bool:
	return not juice.distortion.visible and not player.hud.speedlines.visible \
		and is_zero_approx(shader_value(juice.distortion_material, "strength")) \
		and is_zero_approx(shader_value(juice.distortion_material, "pulse")) \
		and is_zero_approx(shader_value(player.hud.speedlines.material, "line_density"))

func camera_neutral() -> bool:
	return is_equal_approx(player.camera.fov, juice._base_fov) \
		and is_zero_approx(player.camera.rotation.z) and is_zero_approx(player.camera_tilt) \
		and player.camera.position.is_equal_approx(juice._base_position)

func release_inputs() -> void:
	for action in ["move_forwards", "move_backwards", "move_left", "move_right", "grapple", "jump_or_dash"]:
		Input.action_release(action)
	player.hud.mobile_controls.reset_touches()

func manual_updates(count: int) -> void:
	for _tick in range(count):
		juice.update_effects(STEP)

func make_flat() -> void:
	flat = StaticBody3D.new()
	flat.name = "JuicePhysicsProbe"
	flat.position = Vector3(1000, 20, 0)
	flat.collision_layer = 1
	flat.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(80, 1, 80)
	collision.shape = shape
	flat.add_child(collision)
	root.add_child(flat)

func prepare_real_physics(position: Vector3, velocity := Vector3.ZERO) -> void:
	release_inputs()
	player._end_hook(true)
	player.grapple._clear_pending()
	player.rotation = Vector3.ZERO
	player._hook_slide_timer = 0.0
	player._body_collision.shape = player._full_capsule
	player._body_collision.position = player._full_capsule_position
	player._capsule_reduced = false
	player.global_position = position
	player.velocity = velocity
	player.gameplay_active = true
	juice.reset_effects()
	player.set_process(true)
	player.set_physics_process(true)

func check_acquisition_invariance() -> void:
	# Keep real anchor collision and LOS checks, isolated from course targets.
	player.global_position = Vector3(1200, 30, 0)
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	var anchor = load("res://scenes/parkour/grapple_anchor.tscn").instantiate()
	anchor.name = "JuiceAcquisitionProbe"
	root.add_child(anchor)
	var cases := [
		{"name": "horizontal edge", "horizontal": 17.9, "vertical": 0.0, "accepted": true},
		{"name": "vertical screen edge", "horizontal": 0.0, "vertical": 37.4, "accepted": true},
		{"name": "combined screen edge", "horizontal": 17.9, "vertical": 37.4, "accepted": true},
		{"name": "outside base screen", "horizontal": 0.0, "vertical": 38.5, "accepted": false},
		{"name": "outside angular window", "horizontal": 18.1, "vertical": 0.0, "accepted": false},
	]
	var results: Array[Dictionary] = []
	for probe in cases:
		var direction := Vector3(tan(deg_to_rad(float(probe.horizontal))), tan(deg_to_rad(float(probe.vertical))), -1).normalized()
		anchor.global_position = player.to_global(player._camera_base_pos) + direction * 20.0
		await frames(2)
		for strength in [0.0, 1.0]:
			Settings.effects_strength = strength
			juice.update_effects(STEP)
			player.camera.position = juice._base_position
			player.camera.rotation = Vector3.ZERO
			player.camera.fov = juice._base_fov
			player.grapple.aim_assist_target = null
			var neutral = player.grapple._find_lock_target(player.camera.global_position)
			player.camera.rotation.z = deg_to_rad(7.0)
			player.camera.position.y -= 0.1
			player.camera.fov = juice._base_fov + 14.0
			var boosted = player.grapple._find_lock_target(player.camera.global_position)
			var expected: bool = bool(probe.accepted)
			var matched: bool = (neutral == anchor and boosted == anchor) if expected else (neutral == null and boosted == null)
			results.append({"case": probe.name, "effects": strength, "neutral_accepted": neutral == anchor, "boosted_accepted": boosted == anchor})
			check(matched, "%s preserves its lock outcome with FX %.0f and maximal camera cues" % [probe.name, strength])
	metrics["acquisition"] = results
	Settings.effects_strength = 1.0
	juice.update_effects(STEP)
	juice.reset_effects()
	anchor.queue_free()
	await frames(2)

func run() -> void:
	saved_strength = Settings.effects_strength
	preferences_existed = FileAccess.file_exists(Settings.SAVE_PATH)
	preferences_before = setting_bytes()
	save_path = "user://parkour_juice_validation_%d.cfg" % OS.get_process_id()
	course = load("res://levels/parkour/riptide.tscn").instantiate()
	# Configure the test path before the trial loads any PB data.
	course.clock.save_path = save_path
	root.add_child(course)
	current_scene = course
	await frames(5)
	player = course.player
	juice = player.parkour_juice
	particles = juice.particles
	root.get_node("SoundManager").music_player.stop()
	root.get_node("SoundManager").music_player.stream = null
	course.set_physics_process(false)
	player.set_process(false)
	player.set_physics_process(false)
	Settings.effects_strength = 1.0
	check(player.parkour_mode and player.surf_mode and is_instance_valid(juice), "Riptide initializes its integrated presentation helper")
	check(player.get_node_or_null("Grapple") == player.grapple and player.get_node_or_null("Weapon") == null and player.get_node_or_null("Health") == null,
		"Active parkour player initializes grapple without archived combat nodes")
	check(juice.get_node("WorldSpeedEffect").layer < player.hud.layer, "Screen warp draws before the HUD")

	# Ordinary walking and a controlled high-speed turn exercise the helper
	# without player physics obscuring whether presentation mutates the body.
	juice.reset_effects()
	player.velocity = Vector3(0, 0, -8)
	manual_updates(120)
	metrics["walking"] = {"fov": player.camera.fov, "density": shader_value(player.hud.speedlines.material, "line_density"), "distortion": shader_value(juice.distortion_material, "strength")}
	check(screen_neutral() and is_equal_approx(player.camera.fov, juice._base_fov), "Eight metre per second walking keeps speed cues off and base FOV")
	var invariant := true
	var peak_roll := 0.0
	var peak_fov: float = player.camera.fov
	for tick in range(180):
		player.rotation.y = float(tick) * 0.05
		player.velocity = player.global_basis * Vector3(28, 0, 0)
		var before_body: Transform3D = player.global_transform
		var before_velocity: Vector3 = player.velocity
		juice.update_effects(STEP)
		invariant = invariant and player.global_transform == before_body and player.velocity == before_velocity
		peak_roll = maxf(peak_roll, absf(player.camera.rotation.z))
		peak_fov = maxf(peak_fov, player.camera.fov)
	metrics["boosted_turn"] = {"roll_degrees": rad_to_deg(peak_roll), "fov": peak_fov, "density": shader_value(player.hud.speedlines.material, "line_density"), "distortion": shader_value(juice.distortion_material, "strength"), "body_unchanged": invariant}
	check(invariant, "Presentation updates preserve body velocity, position and rotation")
	check(peak_roll > deg_to_rad(1.0) and peak_roll <= deg_to_rad(7.0) + 0.00001, "Boosted lateral turns lean visibly within seven degrees")
	check(peak_fov > juice._base_fov + 5.0 and peak_fov <= juice._base_fov + 14.0 + 0.0001, "Boosted turns widen FOV within fourteen degrees")
	check(juice.distortion.visible and player.hud.speedlines.visible and particles.trail_active and particles.air_rush_active, "Boost speed enables screen cues, world trail and peripheral air rush")
	await check_acquisition_invariance()
	manual_updates(60)

	# Direct assignment avoids the menu setter, which deliberately saves prefs.
	particles.emit_burst("spring", player.global_position, Vector3.UP)
	Settings.effects_strength = 0.0
	manual_updates(10)
	var emitted_before: int = particles.bursts_emitted
	juice.spring_launch()
	manual_updates(5)
	check(camera_neutral() and screen_neutral(), "Zero effects preference leaves the camera and screen neutral at boost speed")
	check(not particles.trail_active and not particles.air_rush_active and live_emitters() == 0 and particles.bursts_emitted == emitted_before, "Zero effects preference clears particles and suppresses new bursts")
	Settings.effects_strength = 1.0
	manual_updates(30)
	juice.jump()
	juice.update_effects(STEP)
	var lifecycle_anchor = load("res://scenes/parkour/grapple_anchor.tscn").instantiate()
	lifecycle_anchor.name = "JuiceLifecycleProbe"
	root.add_child(lifecycle_anchor)
	lifecycle_anchor.global_position = player.to_global(player._camera_base_pos) - player.global_basis.z * 20.0
	await frames(2)
	check(player.grapple._find_lock_target(player.camera.global_position) == lifecycle_anchor, "Lifecycle probe has a real valid lock before pause")
	var pause_time: float = juice.motion_time
	var pause_camera: Transform3D = player.camera.transform
	var pause_fov: float = player.camera.fov
	var pause_remaining: Array = particles._burst_remaining.duplicate()
	var pause_live := live_emitters()
	var pause_emitted: int = particles.bursts_emitted
	var pause_streak_time := shader_value(player.hud.speedlines.material, "motion_time")
	var pause_warp_time := shader_value(juice.distortion_material, "motion_time")
	paused = true
	var pause_velocity: Vector3 = player.velocity
	player.grapple.request_hook()
	player.start_grapple(lifecycle_anchor)
	player.request_hook()
	check(not player.is_hooking and player.velocity == pause_velocity, "Pause blocks direct controller and player launch requests")
	juice.update_effects(0.5)
	particles.emit_burst("landing", player.global_position)
	await render_frames(30)
	var particle_nodes_paused: bool = not particles.can_process()
	for emitter in emitters():
		particle_nodes_paused = particle_nodes_paused and not emitter.can_process()
	check(juice.motion_time == pause_time and player.camera.transform == pause_camera and player.camera.fov == pause_fov, "Pause freezes the controlled animation clock and camera")
	check(shader_value(player.hud.speedlines.material, "motion_time") == pause_streak_time and shader_value(juice.distortion_material, "motion_time") == pause_warp_time, "Pause freezes both shader animation uniforms")
	check(particle_nodes_paused and particles._burst_remaining == pause_remaining and live_emitters() == pause_live and particles.bursts_emitted == pause_emitted, "Pause suspends actual particle nodes and burst lifetimes")
	paused = false
	await render_frames(12)
	check(particles._burst_remaining != pause_remaining, "Particle lifetimes resume after unpause")

	# A real capsule, floor, ordinary input press and landing prove event hooks.
	make_flat()
	prepare_real_physics(Vector3(1000, 21.05, 0))
	await frames(15)
	check(player.is_on_floor(), "Actual Riptide capsule settles on the isolated floor")
	var jump_before: int = juice.jump_count
	var landing_before: int = juice.landing_count
	var burst_before: int = particles.bursts_emitted
	Input.action_press("jump_or_dash")
	await frames(2)
	Input.action_release("jump_or_dash")
	check(juice.jump_count == jump_before + 1 and particles.bursts_emitted > burst_before and not player.is_on_floor() and particles.last_burst_kind == "jump", "Ordinary grounded jump produces the integrated takeoff burst")
	var downward_speed := 0.0
	var landing_ticks := 0
	while juice.landing_count == landing_before and landing_ticks < 150:
		downward_speed = minf(downward_speed, player.velocity.y)
		await physics_frame
		landing_ticks += 1
	metrics["jump_landing"] = {"jump_events": juice.jump_count - jump_before, "landing_events": juice.landing_count - landing_before, "downward_speed": downward_speed, "ticks": landing_ticks}
	check(juice.landing_count == landing_before + 1 and player.is_on_floor() and downward_speed < -2.5 and particles.last_burst_kind == "landing", "Actual downward floor contact generates one landing burst")

	# Enter the course's existing spring from above, without calling its handler.
	var spring = course.get_node("DropInSpring")
	var spring_before: int = spring.activations
	var launch_before: int = juice.launch_count
	prepare_real_physics(spring.global_position + Vector3(0, 3, 0), Vector3(0, -4, 0))
	var spring_ticks := 0
	while spring.activations == spring_before and spring_ticks < 90:
		await physics_frame
		spring_ticks += 1
	metrics["spring"] = {"activations": spring.activations - spring_before, "launch_events": juice.launch_count - launch_before, "velocity": str(player.velocity), "ticks": spring_ticks}
	check(spring.activations == spring_before + 1 and juice.launch_count == launch_before + 1 and player.velocity.y > 1.0 and particles.last_burst_kind == "spring", "Real spring Area entry produces a launch and its burst")

	player.set_process(false)
	player.set_physics_process(false)
	player.velocity = Vector3(28, 0, 0)
	manual_updates(60)
	particles.emit_burst("grapple", player.global_position)
	course.clock.start()
	course.clock.advance(1.0)
	course._checkpoint_entered(player, 1)
	course.respawn_checkpoint()
	check(camera_neutral() and screen_neutral(), "Checkpoint retry immediately resets camera FOV, roll and screen cues")
	check(player.velocity.is_zero_approx() and not particles.trail_active and not particles.air_rush_active and live_emitters() == 0 and particles._burst_remaining.all(func(value): return is_zero_approx(value)), "Checkpoint retry clears trails and every pooled burst")

	# Reusing many event kinds must not allocate emitters or exceed the budget.
	player.velocity = Vector3(28, 0, 0)
	manual_updates(30)
	var pool_count := emitters().size()
	var burst_kinds := ["jump", "landing", "spring", "grapple", "release", "arrival", "checkpoint", "finish"]
	var largest_budget := 0
	var pool_bounded := true
	for event in range(50):
		particles.emit_burst(burst_kinds[event % burst_kinds.size()], player.global_position, Vector3.UP, 1.0)
		var budget := 0
		for emitter in emitters():
			budget += emitter.amount
		largest_budget = maxi(largest_budget, budget)
		pool_bounded = pool_bounded and emitters().size() == pool_count and budget <= 112
		for emitter in particles._burst_emitters:
			pool_bounded = pool_bounded and emitter.amount <= 20
	metrics["pool"] = {"emitters": pool_count, "largest_particle_budget": largest_budget, "events": 50}
	check(pool_bounded, "Fifty mixed events reuse a fixed emitter pool within 112 particles")

	# Finish via the trial's normal integration; the isolated practice clock
	# prevents a PB write while retaining the real finish presentation behavior.
	course.clock.clean_run = false
	for index in range(2, course.clock.checkpoint_count + 1):
		course.clock.advance(1.0)
		course._checkpoint_entered(player, index)
	course.clock.advance(1.0)
	manual_updates(30)
	course._finish_entered(player)
	juice.update_effects(STEP)
	check(course.clock.state == 2 and not player.gameplay_active and screen_neutral() and not particles.trail_active and not particles.air_rush_active, "Finish stops screen distortion, streaks and trails")
	var finish_live := live_emitters()
	var finish_remaining: Array = particles._burst_remaining.duplicate()
	check(particles.last_burst_kind == "finish" and finish_live == 1 and finish_remaining.any(func(value): return value > 0.0), "Finish burst survives the transition to inactive gameplay")
	lifecycle_anchor.global_position = player.to_global(player._camera_base_pos) - player.global_basis.z * 20.0
	await frames(2)
	var finish_velocity: Vector3 = player.velocity
	player.grapple.request_hook()
	player.start_grapple(lifecycle_anchor)
	player.request_hook()
	check(not player.is_hooking and player.velocity == finish_velocity, "Inactive finish state blocks direct controller and player launch requests")
	await render_frames(6)
	check(live_emitters() == 1 and particles._burst_remaining != finish_remaining, "Inactive finish burst fades naturally instead of being cleared immediately")
	await render_frames(60)
	check(live_emitters() == 0 and particles._burst_remaining.all(func(value): return is_zero_approx(value)), "Finish burst ends after its natural lifetime")
	check(not FileAccess.file_exists(save_path), "Isolated practice validation never writes a PB")
	check(FileAccess.file_exists(Settings.SAVE_PATH) == preferences_existed and setting_bytes() == preferences_before, "Validation never writes the real presentation preferences")

	Settings.effects_strength = saved_strength
	release_inputs()
	paused = false
	for child in root.get_node("SoundManager").get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	course.queue_free()
	flat.queue_free()
	lifecycle_anchor.queue_free()
	await frames(2)
	DirAccess.remove_absolute(save_path)
	# Fixed-fps simulation can outrun the audio mixer. Give its stop queue a
	# bounded real-time interval to release played pickup/finish sounds.
	OS.delay_msec(200)
	print("PARKOUR_JUICE_RESULT ", JSON.stringify({"checks": checks, "metrics": metrics, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
