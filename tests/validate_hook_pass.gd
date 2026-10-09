extends SceneTree
## Held, real-input pulls through isolated production CharacterBody physics.
## --fixed-fps 30/60/120 --script tests/validate_hook_pass.gd -- --hook-fps=30/60/120
## A test-only --player-script=/tmp/pre_fix_player.gd reproduces the old behavior.
## No course clock is instantiated. Saved bests/preferences remain byte identical.

const AudioCleanup = preload("res://tests/audio_test_cleanup.gd")
const START := Vector3(1000, 100, 0)
class ProbeAnchor extends "res://scenes/parkour/grapple_anchor.gd":
	var arrivals := 0
	func on_grapple_arrival() -> void:
		arrivals += 1
		super.on_grapple_arrival()
class Errors extends Logger:
	var captured: Array[String] = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, error_type: int, _traces: Array) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			captured.append("%s (%s:%d %s)" % [rationale if not rationale.is_empty() else code, file, line, function])

var error_log := Errors.new()
var failures: Array[String] = []
var checks := 0
var fps := 60
var player_script := ""
var player
var anchor
var metrics := {}
var saved_files := {}

func _initialize() -> void:
	OS.add_logger(error_log)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--hook-fps="):
			fps = int(argument.get_slice("=", 1))
		if argument.begins_with("--player-script="):
			player_script = argument.trim_prefix("--player-script=")
	Engine.physics_ticks_per_second = fps
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)

func ticks(count: int) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame

func vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.device = 0
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	event.position = root.get_final_transform() * Vector2(640, 360)
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func setup(velocity: Vector3, offset: Vector3, momentum := true) -> void:
	paused = false
	player.hud.is_paused = false
	player.hud.pause_screen.hide()
	player.set_physics_process(false)
	player.reset_movement_input()
	mouse(false)
	player._end_hook(true)
	player._recent_anchor = null
	player._anchor_cooldown = 0.0
	player._hook_slide_timer = 0.0
	player._body_collision.shape = player._full_capsule
	player._body_collision.position = player._full_capsule_position
	player._capsule_reduced = false
	player.global_position = START
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.velocity = velocity
	player.input_dir = Vector3.ZERO
	player.use_momentum_pull = momentum
	player.gameplay_active = true
	player.hud.mobile_controls.enabled = false
	player.hud.mobile_controls.set_active(false)
	for action in ["move_forwards", "move_backwards", "move_left", "move_right", "grapple", "jump_or_dash"]:
		Input.action_release(action)
	anchor.global_position = START + offset
	anchor.arrivals = 0
	player.grapple.aim_assist_target = null
	# Real target acquisition remains required even for a highly lateral sweep.
	var aim: Vector3 = anchor.global_position - player.to_global(player._camera_base_pos)
	player.rotation.y = -atan2(aim.x, -aim.z)
	player.camera.rotation.x = clampf(atan2(aim.y, Vector2(aim.x, aim.z).length()), -player.MAX_LOOK_PITCH, player.MAX_LOOK_PITCH)
	await ticks(2)
	check(player.grapple.get_lock_target() == anchor, "Setup acquires the real isolated anchor collider")
	player.set_physics_process(true)
	mouse(true)
	check(player.is_hooking and Input.is_action_pressed("grapple"), "A held mouse press acquires the anchor")

func flyby(label: String, velocity: Vector3, offset: Vector3) -> void:
	await setup(velocity, offset)
	var closest := INF
	var outward_time := -1.0
	var reversed_time := -1.0
	var release_time := -1.0
	var release_speed := 0.0
	var release_change := INF
	var trace: Array[Dictionary] = []
	for index in range(ceili(3.0 * fps)):
		var before: Vector3 = player.velocity
		await ticks(1)
		var distance: float = player.global_position.distance_to(anchor.global_position)
		closest = minf(closest, distance)
		var time := float(index + 1) / fps
		if (anchor.global_position - player.global_position).dot(player.velocity) < 0.0 and outward_time < 0.0:
			outward_time = time
		if player.is_hooking and player.velocity.z > 0.1 and reversed_time < 0.0:
			reversed_time = time
		if index % maxi(1, fps / 10) == 0 or not player.is_hooking:
			trace.append({"time": time, "position": vector(player.global_position), "velocity": vector(player.velocity), "distance": distance, "pulling": player.is_hooking})
		if not player.is_hooking:
			release_time = time
			release_speed = player.velocity.length()
			release_change = before.distance_to(player.velocity)
			break
	metrics[label] = {"closest": closest, "outward_time": outward_time, "reversed_time": reversed_time,
		"release_time": release_time, "release_speed": release_speed, "release_change": release_change, "arrivals": anchor.arrivals, "trace": trace}
	check(closest > player.pull_arrival_distance, label + " misses the arrival sphere while passing beside the anchor")
	check(release_time > 0.0 and release_time < 1.0 and reversed_time < 0.0,
		label + " releases at the first closest pass before force can reverse forward travel")
	check(anchor.arrivals == 0 and release_speed > 20.0 and release_change < 0.001,
		label + " pass keeps the actual momentum and emits no arrival pulse")
	check(not player.is_hooking and player._hook_target == null and player._pull_solver.elapsed == 0.0,
		label + " clears the held target and solver state")
	await ticks(maxi(1, fps / 5))
	check(player.velocity.z < 0.0, label + " continues its forward free arc after automatic release")

func swept_arrival() -> void:
	var delta := 1.0 / fps
	var offset := Vector3(player.pull_arrival_distance + 18.0 * delta * delta, 0, -16.0 * delta)
	await setup(Vector3(0, 0, -32), offset)
	var start: Vector3 = player.global_position
	await ticks(1)
	var endpoint: Vector3 = player.global_position
	var closest := Geometry3D.get_closest_point_to_segment(anchor.global_position, start, endpoint)
	var velocity: Vector3 = player.velocity
	check(start.distance_to(anchor.global_position) > player.pull_arrival_distance and endpoint.distance_to(anchor.global_position) > player.pull_arrival_distance,
		"Swept arrival has both sampled body endpoints outside the arrival sphere")
	check(closest.distance_to(anchor.global_position) < player.pull_arrival_distance, "Actual traveled segment crosses the arrival sphere between samples")
	await ticks(1)
	check(not player.is_hooking and anchor.arrivals == 1, "Swept arrival ends the held pull once and calls the arrival hook")
	check(player.velocity.distance_to(velocity) < 0.001, "Swept arrival preserves the actual pre-release velocity")
	metrics["sweep"] = {"start_distance": start.distance_to(anchor.global_position), "end_distance": endpoint.distance_to(anchor.global_position), "segment_distance": closest.distance_to(anchor.global_position), "arrivals": anchor.arrivals}

func initial_away_and_overhead() -> void:
	await setup(Vector3(0, 0, 20), Vector3(0, 6, -18))
	await ticks(maxi(1, roundi(0.15 * fps)))
	check(player.is_hooking and player.global_position.z > START.z and player.velocity.z > 0.0,
		"An initially away-moving arc stays attached while force brakes its inherited momentum")
	await ticks(maxi(1, roundi(0.25 * fps)))
	check(player.is_hooking and player.velocity.z < 0.0,
		"The initial-away arc can turn toward the anchor before pass detection is armed")
	await setup(Vector3(5, 0, -4), Vector3(0, 27, -10))
	await ticks(maxi(1, roundi(0.35 * fps)))
	check(player.is_hooking and player.global_position.y > START.y + 2.0 and player.velocity.y > 10.0,
		"A steep overhead anchor still gives a rising pull before the actual closest pass")
	await setup(Vector3(0, 0, -24), Vector3(0, 8, 0))
	var release_time := -1.0
	var closest := 8.0
	var release_change := INF
	for index in range(ceili(0.3 * fps)):
		var before: Vector3 = player.velocity
		await ticks(1)
		closest = minf(closest, player.global_position.distance_to(anchor.global_position))
		if not player.is_hooking:
			release_time = float(index + 1) / fps
			release_change = player.velocity.distance_to(before)
			break
	metrics["fast_direct_overhead"] = {"release_time": release_time, "closest": closest,
		"height_gain": player.global_position.y - START.y, "velocity": vector(player.velocity), "pulling": player.is_hooking, "release_change": release_change}
	check(release_time > 0.0 and release_time <= 2.0 / fps + 0.00001 and closest > player.pull_arrival_distance,
		"A fast flyby directly below an overhead ring releases after its actual first closest pass")
	check(anchor.arrivals == 0 and release_change < 0.001 and is_equal_approx(player.velocity.z, -24.0),
		"The immediate overhead miss gives no arrival pulse and preserves its outgoing momentum")
	# A directly overhead fast miss is distinct from a vertical climb. To gain
	# height on a fast line, acquire earlier or brake before passing below it.
	await setup(Vector3.ZERO, Vector3(0, 18, 0))
	await ticks(maxi(1, roundi(0.15 * fps)))
	check(player.is_hooking and player.global_position.y > START.y + 0.5 and player.velocity.y > 5.0,
		"A pure vertical overhead pull from rest acquires and climbs normally")
	var vertical_change := INF
	for _index in range(2 * fps):
		var before: Vector3 = player.velocity
		await ticks(1)
		if not player.is_hooking:
			vertical_change = player.velocity.distance_to(before)
			break
	check(not player.is_hooking and anchor.arrivals == 1 and player.global_position.y > START.y + 16.0 and player.velocity.y > 25.0 and vertical_change < 0.001,
		"A pure vertical climb reaches its ring and keeps upward momentum on arrival")

func lifecycle_and_legacy() -> void:
	await setup(Vector3(12, 3, -4), Vector3(0, 10, -28))
	await ticks(maxi(1, roundi(0.2 * fps)))
	var position: Vector3 = player.global_position
	var velocity: Vector3 = player.velocity
	player.hud.toggle_pause()
	mouse(false)
	mouse(true)
	await ticks(4)
	check(not player.is_hooking and player.global_position.is_equal_approx(position) and player.velocity.is_equal_approx(velocity) and player._pull_solver.elapsed == 0.0,
		"Pause freezes the body and cancels the hold without accepting menu presses")
	player.hud.toggle_pause()
	mouse(false)
	check(not player.is_hooking, "Resuming cannot replay a canceled hold")
	await setup(Vector3(12, 3, -4), Vector3(0, 10, -28))
	await ticks(maxi(1, roundi(0.2 * fps)))
	velocity = player.velocity
	mouse(false)
	check(not player.is_hooking and player.velocity.distance_to(velocity) < 0.001 and player._pull_solver.elapsed == 0.0,
		"Manual button release preserves velocity and clears force state")
	mouse(true)
	check(not player.is_hooking, "Recent-anchor cooldown rejects immediate reacquisition after release")
	mouse(false)
	await ticks(2)
	check(not player._capsule_reduced, "Full capsule restores after release when the environment is clear")
	await setup(Vector3(12, 3, -4), Vector3(0, 6, -18), false)
	player.hook_exit_speed = 22.0
	await ticks(1)
	check(absf(player.velocity.length() - 38.0) < 0.01 and absf(player.velocity.x) < 0.001,
		"Comparison courses retain their existing thirty-eight metre linear reel")
	for _index in range(2 * fps):
		await ticks(1)
		if not player.is_hooking:
			break
	check(not player.is_hooking and anchor.arrivals == 1 and absf(player.velocity.length() - 22.0) < 0.01,
		"Comparison courses retain their authored arrival and twenty-two metre exit speed")

func run() -> void:
	for path in ["user://parkour_bests.cfg", "user://parkour_settings.cfg"]:
		saved_files[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	player = load("res://scenes/player/player.tscn").instantiate()
	if not player_script.is_empty():
		player.set_script(load(player_script))
	player.use_momentum_pull = true
	player.vertical_look_enabled = true
	root.add_child(player)
	current_scene = player
	player.set_process(false)
	player.set_physics_process(false)
	player.hud.parkour_ready()
	player.grapple.hook_range = 32.0
	root.get_node("SoundManager").music_player.stop()
	anchor = load("res://scenes/parkour/grapple_anchor.tscn").instantiate()
	anchor.set_script(ProbeAnchor)
	root.add_child(anchor)
	check(Engine.physics_ticks_per_second == fps, "Actual hook-pass physics rate is %d Hz" % fps)
	await flyby("gentle_lateral", Vector3(12, 0, -28), Vector3(0, 5, -10))
	await flyby("wide_lateral", Vector3(24, 0, -20), Vector3(0, 5, -10))
	await swept_arrival()
	await initial_away_and_overhead()
	await lifecycle_and_legacy()
	for path in saved_files:
		var after = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		check(after == saved_files[path], path.get_file() + " remains byte identical")
	check(error_log.captured.is_empty(), "Hook-pass validation produced no script errors")
	AudioCleanup.stop_voices(self)
	root.get_node("GameManager").player = null
	player.queue_free()
	anchor.queue_free()
	await ticks(3)
	AudioCleanup.drain_mixer()
	print("HOOK_PASS_RESULT ", JSON.stringify({"physics_fps": fps, "checks": checks, "failures": failures, "script_errors": error_log.captured, "metrics": metrics, "player_script": player_script}))
	OS.remove_logger(error_log)
	quit(0 if failures.is_empty() and error_log.captured.is_empty() else 1)
