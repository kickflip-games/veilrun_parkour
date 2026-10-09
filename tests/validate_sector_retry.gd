extends SceneTree
## Real physical R / Shift+R and pause UI. Default opts the rooftop reference
## into city retry behavior. Add -- --city to check every authored city boundary.
const COURSE := "res://levels/parkour/rooftop_trial.tscn"
const CITY := "res://levels/parkour/MainCityRun.tscn"
const CHECKPOINT := preload("res://scenes/parkour/city_checkpoint.gd")
var checks := 0
var failures: Array[String] = []
var save_path := ""
var course_path := COURSE

func _initialize() -> void:
	save_path = "user://sector_retry_validation_%d.cfg" % OS.get_process_id()
	if OS.get_cmdline_user_args().has("--city"):
		course_path = CITY
	node_added.connect(_isolate)
	call_deferred("run")

func _isolate(node: Node) -> void:
	if node.scene_file_path != course_path:
		return
	node.clock.save_path = save_path
	if course_path == CITY:
		return
	node.sector_retry_enabled = true
	var boundary := node.get_node("Checkpoint1") as Area3D
	boundary.set_script(CHECKPOINT)
	boundary.checkpoint_id = "eaves_exit"
	boundary.sector_name = "CHIMNEY ROW"
	boundary.order_index = 1
	boundary.initial_velocity = Vector3(0, 0, -18)
	var spawn := Marker3D.new()
	spawn.name = "PlayerSpawn"
	spawn.transform = node.get_node("Player").transform
	node.add_child(spawn)

func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)

func frames(count: int) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame

func key(pressed: bool, shift := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_R
	event.keycode = KEY_R
	event.device = 0
	event.pressed = pressed
	event.shift_pressed = shift
	return event

func retry_key(shift := false) -> void:
	Input.parse_input_event(key(true, shift))
	await process_frame
	Input.parse_input_event(key(false, shift))
	await process_frame

func run() -> void:
	check(ResourceLoader.exists(course_path), "Requested authored course exists")
	if not ResourceLoader.exists(course_path):
		quit(1)
		return
	var course = load(course_path).instantiate()
	root.add_child(course)
	current_scene = course
	await frames(12)
	check(course.player.is_on_floor(), "Authored starting capsule settles on its roof")
	check(key(true).is_action_pressed("trial_restart"), "Physical R matches sector action")
	check(key(true, true).is_action_pressed("trial_full_restart", true), "Physical Shift+R matches full action")
	var initial_id: int = course.get_instance_id()
	course.set_physics_process(false)
	course.player.set_physics_process(false)
	await retry_key()
	check(current_scene.get_instance_id() == initial_id, "R before CP1 retries in place")
	check(course.clock.state == 1 and not course.clock.clean_run, "Opening retry begins practice immediately")
	check(course.player.global_transform.is_equal_approx(course._spawn_transform), "Opening retry uses its authored spawn transform")
	check(course.clock.current_sector_elapsed == 0.0 and course.clock.elapsed == 0.0, "Opening retry resets sector time")
	course.clock.advance(7.0)
	course._checkpoint_entered(course.player, 1)
	course.clock.advance(4.0)
	var before_total: float = course.clock.elapsed
	var respawn: Marker3D = course._checkpoints[0].get_node("Respawn")
	var entry_velocity: Vector3 = course._checkpoints[0].practice_velocity()
	course.player.global_position += Vector3(8, 12, -25)
	course.player.camera.rotation.x = 0.6
	course.player.press_pull(&"touch")
	course.player.request_jump()
	course.player.hud.toggle_pause()
	check(paused and course.player.hud.pause_screen.visible, "Retry begins from the actual pause overlay")
	await retry_key()
	check(current_scene.get_instance_id() == initial_id, "Paused sector retry retains its scene instance")
	check(not paused and not course.player.hud.is_paused and not course.player.hud.pause_screen.visible, "Sector retry resumes immediately")
	check(course.player.global_transform.is_equal_approx(respawn.global_transform), "Sector retry applies checkpoint position and facing")
	check(course.player.velocity.is_equal_approx(entry_velocity.limit_length(course.player.parkour_speed_limit)), "Sector retry applies authored entry momentum")
	check(course.clock.elapsed == before_total and course.clock.checkpoint_splits.size() == 1, "Sector retry retains total elapsed and ordered progress")
	check(course.clock.current_sector_elapsed == 0.0 and not course.clock.clean_run, "Retried sector starts its own clock and remains practice")
	check(course.player._pull_input_sources.is_empty() and course.player._jump_buffer_left == 0.0 and course.player._coyote_time_left == 0.0, "Retry clears held pull, jump buffer and coyote window")
	check(not course.player.is_hooking and not course.player._capsule_reduced and course.player.camera.rotation.is_zero_approx(), "Retry restores capsule, camera and hook state")
	check(course.recorder.practice and not course.recorder.active and course.recorder.samples.is_empty(), "Retry discards PB recording")
	check(not FileAccess.file_exists(save_path), "Sector practice never writes a total or sector PB")
	course._checkpoint_entered(course.player, 3)
	check(course.clock.checkpoint_splits.size() == 1, "Practice still rejects out-of-order boundaries")
	if course_path == CITY:
		check(course.sector_retry_enabled and course.sector_names.size() == 7 and course._checkpoints.size() == 6, "City enables sector retry across seven continuous sectors")
		for index in range(course._checkpoints.size()):
			var boundary = course._checkpoints[index]
			if index > 0:
				course.clock.advance(5.0)
				course._checkpoint_entered(course.player, index + 1)
			check(boundary.order_index == index + 1 and not boundary.checkpoint_id.is_empty(), "CP%d has its stable ID and ordered index" % (index + 1))
			check(boundary.sector_name == course.sector_names[index + 1], "CP%d names its upcoming active sector" % (index + 1))
			var marker: Marker3D = boundary.get_node("Respawn")
			var seed: Vector3 = boundary.practice_velocity()
			course.player.global_position += Vector3(10, 10, 10)
			await retry_key()
			check(course.get_instance_id() == initial_id and course.player.global_transform.is_equal_approx(marker.global_transform), "CP%d R instantly restores its authored respawn pose" % (index + 1))
			check(course.player.velocity.is_equal_approx(seed.limit_length(course.player.parkour_speed_limit)), "CP%d restores its authored entry speed" % (index + 1))
			check(seed.length() > 0.0 and seed.normalized().dot(-marker.global_basis.z.normalized()) > 0.8, "CP%d entry velocity points along the authored facing" % (index + 1))
			check(course._progress_label.text.contains(boundary.sector_name), "CP%d HUD shows the active sector name" % (index + 1))
			check(course._sector_label.text.begins_with("SECTOR 00:00.000") and course.clock.current_sector_elapsed == 0.0, "CP%d resets the local sector clock and HUD" % (index + 1))
			var overlap := false
			for collision in course.player.get_world_3d().direct_space_state.intersect_shape(_capsule_query(course.player), 8):
				if collision.collider is StaticBody3D:
					overlap = true
					print("CITY_RESPAWN_OVERLAP ", JSON.stringify({"checkpoint": index + 1, "position": str(marker.global_position), "collider": str(collision.collider.get_path())}))
			check(not overlap, "CP%d full capsule has clear authored practice entry" % (index + 1))
	await retry_key(true)
	await frames(12)
	course = current_scene
	check(course.get_instance_id() != initial_id, "Shift+R recreates a complete clean attempt")
	check(course.clock.state == 0 and course.clock.clean_run and course.clock.elapsed == 0.0 and course.clock.checkpoint_splits.is_empty(), "Full retry restores clean READY and no sector progress")
	check(course.player.is_on_floor(), "Full retry preserves the authored collision floor")
	var sound := root.get_node("SoundManager")
	for child in sound.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	root.get_node("GameManager").player = null
	current_scene.queue_free()
	current_scene = null
	await frames(3)
	DirAccess.remove_absolute(save_path)
	OS.delay_msec(200)
	print("SECTOR_RETRY_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _capsule_query(player: CharacterBody3D) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = player._full_capsule
	query.transform = player._body_collision.global_transform
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	return query
