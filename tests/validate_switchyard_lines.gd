extends SceneTree
## Input-driven real-player checks for the optional bank and bridge lines.
## Godot --headless --path . --script tests/validate_switchyard_lines.gd --fixed-fps 60
## Place/seed once at each isolated approach; all traversal uses normal inputs.

var course
var player
var failures: Array[String] = []
var metrics: Dictionary = {}
var checks := 0
var save_path := "user://switchyard_lines_validation.cfg"

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for _tick in range(count):
		await physics_frame

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
	print("CHECK ", "PASS " if condition else "FAIL ", message)

func release_inputs() -> void:
	for action in ["move_forwards", "move_backwards", "move_left", "move_right", "grapple", "jump_or_dash"]:
		Input.action_release(action)
	player.hud.mobile_controls.reset_touches()

func place(floor_point: Vector3, approach_velocity := Vector3.ZERO) -> void:
	release_inputs()
	player._end_hook(true)
	player.grapple._clear_pending()
	player.grapple.aim_assist_target = null
	player._body_collision.shape = player._full_capsule
	player._body_collision.position = player._full_capsule_position
	player._capsule_reduced = false
	player._hook_slide_timer = 0.0
	player._anchor_cooldown = 0.0
	player._recent_anchor = null
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.global_position = floor_point + Vector3.UP * 0.55
	player.velocity = Vector3.ZERO
	player.input_dir = Vector3.ZERO
	player.gameplay_active = true
	player.hud.game_started = true
	await frames(8)
	# This is the only velocity seed; input and the actual controller take over.
	player.velocity = approach_velocity

func drive_to(floor_point: Vector3, label: String) -> bool:
	var reached := false
	var collisions: Dictionary = {}
	var ticks := 0
	for tick in range(1200):
		ticks = tick
		var offset: Vector3 = floor_point - player.global_position
		offset.y = 0.0
		if offset.length() < 0.55:
			reached = true
			break
		# Ordinary movement countersteers the preserved momentum when needed.
		var desired := offset.normalized() * minf(8.0, offset.length() * 2.5)
		var horizontal := Vector3(player.velocity.x, 0.0, player.velocity.z)
		var steering := desired - horizontal
		if steering.length() > 0.2:
			player.rotation.y = atan2(-steering.x, -steering.z)
			Input.action_press("move_forwards")
		else:
			Input.action_release("move_forwards")
		await physics_frame
		for index in range(player.get_slide_collision_count()):
			var collision = player.get_slide_collision(index)
			var collider = collision.get_collider()
			if is_instance_valid(collider):
				collisions[collider.name] = true
	Input.action_release("move_forwards")
	var height_matches: bool = absf(player.global_position.y - (floor_point.y + 0.5)) < 0.35
	metrics[label] = {"position":str(player.global_position), "velocity":str(player.velocity),
		"ticks":ticks, "on_floor":player.is_on_floor(), "contacts":collisions.keys()}
	print("LINE_LEG ", label, " ", JSON.stringify(metrics[label]))
	check(reached and height_matches, label + " reaches the intended floor using movement input")
	return reached and height_matches

func jump_to_bridge(label: String, launch: Vector3, approach_velocity: Vector3, bridge_name: String) -> void:
	await place(launch, approach_velocity)
	check(player.is_on_floor(), label + " approach starts on the bridge")
	player.rotation.y = atan2(-approach_velocity.x, -approach_velocity.z)
	Input.action_press("move_forwards")
	Input.action_press("jump_or_dash")
	var start: Vector3 = player.global_position
	var peak_height: float = start.y
	var airborne := false
	var airborne_ticks := 0
	var landed := false
	var landing_contacts: Array[String] = []
	for tick in range(180):
		await physics_frame
		if tick == 1:
			Input.action_release("jump_or_dash")
		peak_height = maxf(peak_height, player.global_position.y)
		if not player.is_on_floor():
			airborne = true
			airborne_ticks += 1
		elif airborne:
			landed = true
			for index in range(player.get_slide_collision_count()):
				var collider = player.get_slide_collision(index).get_collider()
				if is_instance_valid(collider) and String(collider.name) not in landing_contacts:
					landing_contacts.append(String(collider.name))
			break
	release_inputs()
	var bridge = course.get_node(bridge_name)
	var local: Vector3 = bridge.to_local(player.global_position)
	var within_top: bool = absf(local.x) < bridge.size.x * 0.5 and absf(local.z) < bridge.size.z * 0.5
	var intended_height: bool = absf(player.global_position.y - 4.0) < 0.2
	metrics[label] = {"launch":str(start), "seed_speed":approach_velocity.length(),
		"landing":str(player.global_position), "landing_contacts":landing_contacts,
		"airborne_ticks":airborne_ticks, "height_gain":peak_height-start.y,
		"final_speed":player.velocity.length(), "on_floor":player.is_on_floor()}
	print("NARROW_HOP ", label, " ", JSON.stringify(metrics[label]))
	check(airborne and airborne_ticks > 30 and peak_height-start.y > 1.0,
		label + " normal jump crosses the gap through the air")
	check(landed and bridge_name in landing_contacts and within_top and intended_height,
		label + " lands on " + bridge_name + " without the catch deck")
	check(not player.is_hooking and not player._capsule_reduced,
		label + " finishes with the ordinary full player capsule")

func run() -> void:
	DirAccess.remove_absolute(save_path)
	course = load("res://levels/parkour/switchyard.tscn").instantiate()
	root.add_child(course)
	current_scene = course
	await frames(8)
	player = course.player
	course.clock.save_path = save_path
	course.clock.load_best()
	# Isolated features do not advance or trigger automatic course retries.
	course.set_physics_process(false)
	var sound = root.get_node("SoundManager")
	sound.music_player.stop()
	sound.music_player.stream = null
	check(player.surf_mode and player.parkour_mode and player.gameplay_active,
		"Checks use the initialized Switchyard surf player")

	await place(Vector3(7.5,0,-162), Vector3(0,0,-12))
	var highline := [
		Vector3(7.5,1.5,-172), Vector3(7.5,3.5,-180), Vector3(7.5,6,-191),
		Vector3(10.5,6.545955,-201), Vector3(10.5,6.545955,-215),
		Vector3(7.5,6,-223), Vector3(7.5,4,-232), Vector3(7.5,2,-240), Vector3(7.5,0,-249),
	]
	for index in range(highline.size()):
		if not await drive_to(highline[index], "highline_leg_%d" % index):
			break
	check(player.global_position.z < -248 and player.global_position.y < 0.8,
		"Highline enters, rides the real bank, and returns to the merge floor")

	# At normal jump duration the player lands farther into each 15 m deck
	# than its front edge; lateral seed changes only at the next isolated setup.
	await jump_to_bridge("hop_01", Vector3(-6,3.5,-285), Vector3(6.3,0,-16), "NarrowBridge02")
	await jump_to_bridge("hop_02", Vector3(1,3.5,-307), Vector3(-6.3,0,-15), "NarrowBridge03")
	check(course.clock.state == 0 and not FileAccess.file_exists(save_path),
		"Isolated lines never start a timed run or write a personal best")

	release_inputs()
	DirAccess.remove_absolute(save_path)
	player.gameplay_active = false
	load("res://tests/audio_test_cleanup.gd").stop_voices(self)
	sound.music_player.stop()
	sound.music_player.stream = null
	root.get_node("GameManager").player = null
	course.queue_free()
	current_scene = null
	player = null
	course = null
	await frames(4)
	load("res://tests/audio_test_cleanup.gd").drain_mixer()
	print("SWITCHYARD_LINES_RESULT ", JSON.stringify({"checks":checks,"metrics":metrics,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
