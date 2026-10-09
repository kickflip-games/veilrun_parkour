extends SceneTree
## Actual CharacterBody traces, separate from course route/medal validation.
## Run with --fixed-fps 30/60/120 --script tests/validate_anchor_pull.gd -- --pull-fps=30/60/120.

const PLAYER := "res://scenes/player/player.tscn"
const ANCHOR := "res://scenes/parkour/grapple_anchor.tscn"
const SOLVER = preload("res://scenes/parkour/anchor_pull.gd")
var player
var anchor
var second_anchor
var wall: StaticBody3D
var fps := 60
var failures: Array[String] = []
var checks := 0
var metrics := {}
var trace: Array[Dictionary] = []

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--pull-fps="):
			fps = int(argument.get_slice("=", 1))
	Engine.physics_ticks_per_second = fps
	call_deferred("run")

func ticks(count: int) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame

func check(condition: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if condition else "FAIL ", message)
	if not condition:
		failures.append(message)

func vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func release_inputs() -> void:
	for action in ["move_forwards", "move_backwards", "move_left", "move_right", "grapple", "jump_or_dash"]:
		Input.action_release(action)
	player.hud.mobile_controls.reset_touches()

func place(position: Vector3, velocity: Vector3, destination: Vector3) -> void:
	# Setup placement is explicit. All reported movement after this uses the
	# production force solver and move_and_slide, with no position correction.
	release_inputs()
	player.set_physics_process(false)
	player._end_hook(true)
	player._recent_anchor = null
	player._anchor_cooldown = 0.0
	player._hook_slide_timer = 0.0
	player._body_collision.shape = player._full_capsule
	player._body_collision.position = player._full_capsule_position
	player._capsule_reduced = false
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.global_position = position
	player.velocity = velocity
	player.gameplay_active = true
	anchor.global_position = destination
	second_anchor.global_position = Vector3(1800, 100, 0)
	await ticks(2)
	player.set_physics_process(true)

func record(label: String, seconds: float) -> void:
	var count := roundi(seconds * fps)
	for index in range(count):
		var before: Vector3 = player.velocity
		var was_pulling: bool = player.is_hooking
		await ticks(1)
		if label == "blocked" and was_pulling and not player.is_hooking:
			metrics["stalled_release"] = {"velocity_change":player.velocity.distance_to(before), "speed":player.velocity.length()}
		if index % maxi(1, fps / 10) == 0 or index == count - 1:
			trace.append({"probe": label, "time": float(index + 1) / fps,
				"position": vector(player.global_position), "velocity": vector(player.velocity),
				"pulling": player.is_hooking})

func release_probe(seconds: float) -> Dictionary:
	await place(Vector3(1000, 30, 0), Vector3(12, 3, -4), Vector3(1000, 40, -28))
	player.start_grapple(anchor)
	await record("release_%.2f" % seconds, seconds)
	var before: Vector3 = player.velocity
	var position: Vector3 = player.global_position
	player.request_hook()
	check(not player.is_hooking and player.velocity.distance_to(before) < 0.001,
		"Manual release preserves current velocity at %.2f seconds" % seconds)
	player.start_grapple(anchor)
	check(not player.is_hooking and player.velocity.distance_to(before) < 0.001,
		"Recent-anchor cooldown prevents immediate reuse after release")
	await record("coast_%.2f" % seconds, 0.4)
	return {"release_position": vector(position), "release_velocity": vector(before),
		"release_speed": before.length(), "coast_position": vector(player.global_position),
		"coast_velocity": vector(player.velocity)}

func run() -> void:
	var sound = root.get_node("SoundManager")
	sound.music_player.stop()
	sound.music_player.stream = null
	for path in ["res://levels/parkour/parkour_trial.tscn", "res://levels/parkour/riptide.tscn", "res://levels/parkour/switchyard.tscn"]:
		var course = load(path).instantiate()
		check(not course.get_node("Player").use_momentum_pull, path.get_file() + " retains legacy pull by default")
		# HUD creates its touch control before _ready adds it as a child.
		course.get_node("Player/Hud").mobile_controls.free()
		course.free()
	player = load(PLAYER).instantiate()
	player.use_momentum_pull = true
	player.vertical_look_enabled = true
	root.add_child(player)
	current_scene = player
	anchor = load(ANCHOR).instantiate()
	second_anchor = load(ANCHOR).instantiate()
	root.add_child(anchor)
	root.add_child(second_anchor)
	await ticks(3)
	player.hud.parkour_ready()
	player.grapple.hook_range = 32.0
	check(Engine.physics_ticks_per_second == fps, "Actual physics rate is %d Hz" % fps)
	await place(Vector3(1000, 30, 0), Vector3(12, 3, -4), Vector3(1000, 36, -18))
	player.use_momentum_pull = false
	player.hook_exit_speed = 22.0
	player.start_grapple(anchor)
	await ticks(1)
	check(absf(player.velocity.length() - 38.0) < 0.01 and absf(player.velocity.x) < 0.01,
		"Legacy mode retains the original thirty-eight metre linear reel")
	for _index in range(fps * 2):
		await ticks(1)
		if not player.is_hooking:
			break
	check(not player.is_hooking and absf(player.velocity.length() - 22.0) < 0.01,
		"Legacy mode retains the existing authored twenty-two metre exit speed")
	player.use_momentum_pull = true

	var solver = SOLVER.new()
	var solved: Vector3 = solver.step(Vector3(12, 0, 0), Vector3(0, 0, -20), Vector3.ZERO, 9.8, 1.0 / fps)
	check(absf(solved.x - 12.0) < 0.0001 and solved.y < 0.0 and solved.z < 0.0,
		"Force retains transverse momentum and applies gravity")
	await place(Vector3(1000, 30, 0), Vector3(12, 3, -4), Vector3(1000, 40, -28))
	var initial: Vector3 = player.velocity
	player.start_grapple(anchor)
	check(player.is_hooking and player.velocity.distance_to(initial) < 0.001,
		"Activating pull does not replace current velocity")
	await ticks(1)
	check(player.velocity.x > 11.5 and player.velocity.length() < 15.0,
		"First body step adds immediate acceleration without fixed-speed reel")
	await record("arc", 0.4 - 1.0 / fps)
	metrics["arc"] = {"position": vector(player.global_position), "velocity": vector(player.velocity),
		"speed": player.velocity.length(), "elapsed": player._pull_solver.elapsed}
	check(player.global_position.x > 1003.0 and player.global_position.y > 31.0,
		"Actual body follows a lateral rising arc")
	check(player.velocity.length() <= 32.01, "Pull speed remains bounded")
	metrics["early"] = await release_probe(0.2)
	metrics["late"] = await release_probe(0.6)
	var early_velocity := Vector3(metrics["early"]["release_velocity"][0], metrics["early"]["release_velocity"][1], metrics["early"]["release_velocity"][2])
	var late_velocity := Vector3(metrics["late"]["release_velocity"][0], metrics["late"]["release_velocity"][1], metrics["late"]["release_velocity"][2])
	check(early_velocity.angle_to(late_velocity) > deg_to_rad(8.0) and late_velocity.length() > early_velocity.length() + 5.0,
		"Release timing changes the actual flight angle and speed")
	check(metrics["late"]["coast_position"][1] > metrics["late"]["release_position"][1],
		"Late release continues upward while gravity bends the free arc")

	await place(Vector3(1000, 30, 0), Vector3(0, 0, -8), Vector3(1000, 36, -18))
	player.start_grapple(anchor)
	var arrival_speed := 0.0
	var arrival_velocity_change := INF
	var arrival_position := Vector3.ZERO
	for _index in range(fps * 2):
		var before: Vector3 = player.velocity
		await ticks(1)
		if not player.is_hooking:
			arrival_speed = player.velocity.length()
			arrival_velocity_change = player.velocity.distance_to(before)
			arrival_position = player.global_position
			break
	metrics["arrival"] = {"speed": arrival_speed, "velocity_change": arrival_velocity_change,
		"position": vector(arrival_position)}
	check(arrival_speed > 25.0 and arrival_velocity_change < 0.01,
		"Near arrival ends force without imposing the old straight exit velocity")

	await place(Vector3(1000, 30, 0), Vector3(8, 2, -8), Vector3(1000, 40, -24))
	player.start_grapple(anchor)
	await record("chain_first", 0.3)
	player.request_hook()
	var first_position: Vector3 = player.global_position
	var carried: Vector3 = player.velocity
	second_anchor.global_position = Vector3(1020, 49, -31)
	player.start_grapple(second_anchor)
	check(player.is_hooking and player.velocity.distance_to(carried) < 0.001,
		"A second anchor inherits the first pull's outgoing momentum")
	await record("chain_second", 0.5)
	metrics["chain"] = {"position": vector(player.global_position), "velocity": vector(player.velocity),
		"height_gain": player.global_position.y - first_position.y}
	check(player.global_position.y > first_position.y + 3.0 and player.velocity.x > carried.x + 6.0 and player.velocity.z < -10.0,
		"Chained force gains height and redirects around a corner while carrying forward speed")

	await place(Vector3(1000, 30, 0), Vector3(0, 0, -8), Vector3(1000, 34, -25))
	player.start_grapple(anchor)
	Input.action_press("move_right")
	await record("steering", 0.3)
	metrics["steering"] = {"velocity": vector(player.velocity), "speed": player.velocity.length()}
	check(player.velocity.x > 5.0 and player.velocity.z < -10.0 and player.velocity.length() <= 32.01,
		"Pull steering makes a useful lateral correction while carrying capped forward momentum")

	await place(Vector3(1000, 30, 0), Vector3.ZERO, Vector3(1000, 30, -1000))
	player.start_grapple(anchor)
	await record("duration", player.pull_max_duration + 0.15)
	check(not player.is_hooking and player.velocity.length() > 20.0 and player._pull_solver.elapsed == 0.0,
		"Duration safety cap ends force and clears solver state without stopping flight")

	wall = StaticBody3D.new()
	wall.position = Vector3(1000, 35, -10)
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(20, 20, 1)
	collision.shape = shape
	wall.add_child(collision)
	root.add_child(wall)
	await place(Vector3(1000, 30, 0), Vector3.ZERO, Vector3(1000, 33, -23))
	check(player.grapple._find_lock_target(player.camera.global_position) == null, "Real obstruction blocks anchor line of sight")
	player.grapple.request_hook()
	check(not player.is_hooking, "LOS rejects a normal pull activation through the wall")
	player.start_grapple(anchor)
	await record("blocked", 1.3)
	metrics["wall"] = {"position": vector(player.global_position), "velocity": vector(player.velocity), "pulling": player.is_hooking}
	check(player.global_position.z > -9.4 and not player.is_hooking,
		"Swept capsule collision and blocked timeout prevent pulling through a wall")
	check(metrics.has("stalled_release") and metrics["stalled_release"]["velocity_change"] < 0.001
		and metrics["stalled_release"]["speed"] > 0.5,
		"Stalled force release retains the actual collision-projected velocity")
	wall.queue_free()
	await ticks(2)

	# A thin wall initially lies outside LOS, then the curved approach touches
	# its side. A long, fast tangential slide must not trigger the stalled test.
	var side_wall := StaticBody3D.new()
	side_wall.position = Vector3(1003, 35, -7)
	var side_collision := CollisionShape3D.new()
	var side_shape := BoxShape3D.new()
	side_shape.size = Vector3(0.4, 20, 10)
	side_collision.shape = side_shape
	side_wall.add_child(side_collision)
	root.add_child(side_wall)
	await place(Vector3(1000, 30, 0), Vector3(10, 0, -12), Vector3(1005, 36, -30))
	check(player.grapple._find_lock_target(player.camera.global_position) == anchor,
		"Curved wall-slide approach starts with a valid real LOS lock")
	player.request_hook()
	var wall_contact_time := 0.0
	var wall_peak_speed := 0.0
	var wall_lost_momentum := false
	var wall_start := Vector3.ZERO
	for index in range(fps):
		var before: Vector3 = player.velocity
		await ticks(1)
		if player.is_on_wall():
			if wall_contact_time == 0.0:
				wall_start = player.global_position
			wall_contact_time += 1.0 / fps
			wall_peak_speed = maxf(wall_peak_speed, player.velocity.length())
			if player.velocity.length() < 1.0 or (not player.is_hooking and before.length() > 20.0 and player.velocity.length() < 10.0):
				wall_lost_momentum = true
		if index % maxi(1, fps / 10) == 0:
			trace.append({"probe":"wall_slide", "time":float(index + 1) / fps,
				"position":vector(player.global_position), "velocity":vector(player.velocity), "pulling":player.is_hooking})
	metrics["wall_slide"] = {"contact_time":wall_contact_time, "peak_speed":wall_peak_speed,
		"position":vector(player.global_position), "velocity":vector(player.velocity)}
	check(wall_contact_time > player.hook_blocked_timeout and wall_peak_speed > 25.0,
		"Real wall slide lasts beyond the old blocked timeout at high tangent speed")
	check(not wall_lost_momentum and player.global_position.z < wall_start.z - 5.0 and player.velocity.length() > 20.0,
		"Useful wall contact retains projected momentum and continues beyond the obstacle")
	side_wall.queue_free()
	await ticks(2)

	await place(Vector3(1000, 30, 0), Vector3.ZERO, Vector3(1000, 57, -12))
	player.camera.rotation.x = deg_to_rad(65.0)
	check(player.grapple._find_lock_target(player.camera.global_position) == anchor,
		"Pitch-aware aim acquires a steep overhead anchor")
	var neutral: Basis = player.get_aim_basis()
	player.camera.rotation.z = 0.12
	player.camera.fov = 95.0
	player.camera.position.y -= 0.1
	check(player.get_aim_basis().is_equal_approx(neutral), "Aim ignores presentation roll, FOV and dip")
	player.vertical_look_enabled = false
	check(player.get_aim_basis().is_equal_approx(player.global_basis), "Legacy aim remains yaw-only")
	player.vertical_look_enabled = true
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(0, -2000)
	player._input(mouse)
	check(absf(player.camera.rotation.x - deg_to_rad(80.0)) < 0.0001, "Vertical mouse look clamps at eighty degrees")

	await place(Vector3(1000, 30, 0), Vector3(5, 2, -8), Vector3(1000, 40, -25))
	player.start_grapple(anchor)
	await ticks(maxi(1, fps / 5))
	var paused_position: Vector3 = player.global_position
	var paused_velocity: Vector3 = player.velocity
	var paused_elapsed: float = player._pull_solver.elapsed
	paused = true
	player.request_hook()
	player.grapple.request_hook()
	await ticks(4)
	check(player.is_hooking and player.global_position.distance_to(paused_position) < 0.001
		and player.velocity.distance_to(paused_velocity) < 0.001 and player._pull_solver.elapsed == paused_elapsed,
		"Pause freezes the body and force elapsed state without accepting release")
	paused = false
	player._end_hook(true)
	check(player.velocity.is_zero_approx() and player._pull_solver.elapsed == 0.0 and player._pull_solver.last_force.is_zero_approx(),
		"Explicit zero/reset clears pull velocity, force and elapsed state")
	await ticks(2)
	check(not player._capsule_reduced, "Flight capsule restores when the full capsule is clear")
	await place(Vector3(1000, 30, 0), Vector3.ZERO, Vector3(1000, 33, -23))
	var ceiling := StaticBody3D.new()
	var ceiling_collision := CollisionShape3D.new()
	var ceiling_shape := BoxShape3D.new()
	ceiling_shape.size = Vector3(8, 0.3, 8)
	ceiling_collision.shape = ceiling_shape
	ceiling.add_child(ceiling_collision)
	var full_top: float = player.global_position.y + player._full_capsule_position.y + player._full_capsule.height * 0.5
	ceiling.position = Vector3(1000, full_top - 0.05, 0)
	root.add_child(ceiling)
	player.start_grapple(anchor)
	player._end_hook(true)
	await ticks(2)
	check(player._capsule_reduced, "Full capsule waits for clearance after pull ends under a low ceiling")
	ceiling.queue_free()
	await ticks(2)
	check(not player._capsule_reduced, "Full capsule restores after the obstruction clears")
	player.gameplay_active = false
	player.start_grapple(anchor)
	player.grapple.request_hook()
	check(not player.is_hooking, "Inactive gameplay rejects direct and controller pull requests")

	release_inputs()
	player._end_hook(true)
	root.get_node("GameManager").player = null
	# Accelerated fixed-fps tests finish before real-time audio naturally does.
	for voice in player.find_children("*", "AudioStreamPlayer", true, false) + sound.find_children("*", "AudioStreamPlayer", true, false):
		voice.stop()
		voice.stream = null
	player.queue_free()
	anchor.queue_free()
	second_anchor.queue_free()
	await ticks(6)
	# The Dummy audio mixer uses wall time even when fixed-fps physics is
	# accelerated. Let its stopped playback references drain before quitting.
	OS.delay_msec(120)
	print("ANCHOR_PULL_RESULT ", JSON.stringify({"physics_fps": fps, "checks": checks, "failures": failures, "metrics": metrics, "trace": trace}))
	quit(0 if failures.is_empty() else 1)
