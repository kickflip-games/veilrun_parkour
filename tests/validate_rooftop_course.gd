extends SceneTree
const Settings = preload("res://scenes/parkour/presentation_settings.gd")
## Actual authored-city sweeps. Only independent advanced approaches are seeded.
## The complete safe attempt receives input, aim and pull requests with no warps.
var course
var player
var failures: Array[String] = []
var checks := 0
var links: Array[Dictionary] = []
var save_path := "user://rooftop_course_validation_%d.cfg" % OS.get_process_id()
var elapsed_ticks := 0
var initial_strength := 1.0
var preference_bytes := PackedByteArray()
var preference_existed := false
var best_bytes := PackedByteArray()
var best_existed := false
var safe_distance := 0.0

func _initialize() -> void:
	call_deferred("run")

func frames(count: int) -> void:
	for _tick in range(count):
		await physics_frame

func check(value: bool, message: String) -> void:
	checks += 1
	print("CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)

func aim_at(anchor: Node3D) -> void:
	var offset: Vector3 = anchor.global_position - player.to_global(player._camera_base_pos)
	player.rotation.y = atan2(-offset.x, -offset.z)
	player.camera.rotation.x = atan2(offset.y, Vector2(offset.x, offset.z).length())

func drive_to(point: Vector3, label: String, limit := 1500) -> bool:
	var reached := false
	var start: Vector3 = player.global_position
	var old_splits: int = course.clock.checkpoint_splits.size()
	for tick in range(limit):
		var offset: Vector3 = point - player.global_position
		offset.y = 0.0
		if offset.length() < 1.0 or course.clock.state == 2:
			reached = true
			break
		var desired := offset.normalized() * minf(8.0, offset.length() * 2.0)
		var steering := desired - Vector3(player.velocity.x, 0, player.velocity.z)
		if steering.length() > 0.3:
			player.rotation.y = atan2(-steering.x, -steering.z)
			Input.action_press("move_forwards")
		else:
			Input.action_release("move_forwards")
		player.camera.rotation.x = 0.0
		await physics_frame
		elapsed_ticks += 1
	Input.action_release("move_forwards")
	check(reached, label + " " + str(player.global_position))
	print("ROOF_WALK ", JSON.stringify({"label":label,"start":str(start),"end":str(player.global_position),"splits_before":old_splits,"splits_after":course.clock.checkpoint_splits.size(),"time":course.clock.elapsed,"clean":course.clock.clean_run,"state":course.clock.state}))
	return reached

func pull(name: String, release_ticks := -1) -> bool:
	var anchor: Node3D = course.get_node(name)
	Input.action_release("move_forwards")
	aim_at(anchor)
	var lock = player.grapple._find_lock_target(player.camera.global_position)
	check(lock == anchor, name + " acquires through real range, view and collision checks")
	if lock != anchor:
		print("ROOF_LOCK_FAIL ", JSON.stringify({"anchor":name,"selected":str(lock),"position":str(player.global_position),"distance":player.to_global(player._camera_base_pos).distance_to(anchor.global_position),"velocity":str(player.velocity),"aim_local":str(player.get_aim_basis().inverse() * (anchor.global_position-player.to_global(player._camera_base_pos))),"ray":str(player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(player.to_global(player._camera_base_pos),anchor.global_position,3,[player.get_rid()])))}))
		return false
	var previous_pulse = anchor._pulse
	var start: Vector3 = player.global_position
	var start_velocity: Vector3 = player.velocity
	player.request_hook()
	check(player.is_hooking, name + " starts attraction through the ordinary request")
	var contacts: Array[Dictionary] = []
	var ticks := 0
	var released := false
	while player.is_hooking and ticks < 200:
		aim_at(anchor)
		await physics_frame
		ticks += 1
		elapsed_ticks += 1
		for index in range(player.get_slide_collision_count()):
			var hit: KinematicCollision3D = player.get_slide_collision(index)
			if hit.get_normal().y < 0.7:
				var collider = hit.get_collider()
				contacts.append({"tick":ticks,"body":str(collider.name) if collider else "unknown","normal":str(hit.get_normal()),"position":str(player.global_position)})
		if release_ticks >= 0 and ticks == release_ticks and player.is_hooking:
			player.request_hook()
			released = true
	var arrived: bool = anchor._pulse != previous_pulse
	var result := {"anchor":name,"ticks":ticks,"arrived":arrived,"released":released,"start":str(start),"end":str(player.global_position),"start_velocity":str(start_velocity),"exit_velocity":str(player.velocity),"contacts":contacts}
	links.append(result)
	print("ROOF_PULL ", JSON.stringify(result))
	check(released if release_ticks >= 0 else arrived, name + (" manually releases with live momentum" if release_ticks >= 0 else " reaches arrival without blocked timeout"))
	return released if release_ticks >= 0 else arrived

func safe_run() -> void:
	if not await drive_to(Vector3(0,12,-16), "Intro approach"):
		return
	check(course.clock.state == 1, "Real START overlap begins timing")
	if not await pull("IntroRing"):
		return
	if not await drive_to(Vector3(0,12,-64), "Intro checkpoint"):
		return
	check(course.clock.checkpoint_splits.size() == 1, "Eaves reconverges through CP1")
	if not await drive_to(Vector3(-10,12,-85), "Gap approach"):
		return
	if not await pull("GapLeftRing"):
		return
	# The released camera origin can still graze the previous ring sphere.
	# Look toward the next fixture and physically coast clear before clicking;
	# acquisition still uses the unchanged real LOS/range/collision checks.
	aim_at(course.get_node("GapRightRing"))
	await frames(1)
	if not await pull("GapRightRing", 36):
		return
	if not await drive_to(Vector3(8,12,-124), "Gap right landing"):
		return
	if not await pull("GapExitRing"):
		return
	if not await drive_to(Vector3(0,12,-154), "Gap checkpoint"):
		return
	check(course.clock.checkpoint_splits.size() == 2, "Gap braid reconverges through CP2")
	if not await drive_to(Vector3(0,12,-157), "Courtyard takeoff"):
		return
	await frames(30)
	player.request_jump()
	await frames(6)
	if not await pull("CourtyardLowRing"):
		return
	if not await pull("CourtyardMidRing", 42):
		return
	if not await drive_to(Vector3(8,20,-194), "Courtyard middle landing"):
		return
	await frames(35)
	player.request_jump()
	await frames(6)
	if not await pull("CourtyardTopRing"):
		return
	if not await drive_to(Vector3(0,24,-247), "Tower checkpoint"):
		return
	check(course.clock.checkpoint_splits.size() == 3, "Vertical route reconverges through CP3")
	if not await drive_to(Vector3(-6,24,-248), "Chain approach"):
		return
	if not await pull("ChainLeftRing"):
		return
	if not await pull("ChainRightRing", 42):
		return
	if not await drive_to(Vector3(7,24,-300), "Chain right landing"):
		return
	if not await pull("ChainExitRing"):
		return
	if not await drive_to(Vector3(0,24,-339), "Chain checkpoint"):
		return
	check(course.clock.checkpoint_splits.size() == 4, "Momentum chain reconverges through CP4")
	if not await drive_to(Vector3(-8,24,-339), "Final service bridge approach"):
		return
	if not await drive_to(Vector3(-8,24,-351), "Final left roof"):
		return
	if not await drive_to(Vector3(-8,24,-366), "Final transfer approach"):
		return
	if not await drive_to(Vector3(8,24,-384), "Final transfer bridge"):
		return
	if not await drive_to(Vector3(5,24,-414), "Final roof"):
		return
	await drive_to(Vector3(0,24,-430), "Finish")

func seed_approach(position: Vector3, velocity: Vector3, settle := 0) -> void:
	Input.action_release("move_forwards")
	player._end_hook(true)
	player.reset_pull_state()
	player.grapple._clear_pending()
	player._recent_anchor = null
	player._anchor_cooldown = 0.0
	player._hook_slide_timer = 0.0
	player._body_collision.shape = player._full_capsule
	player._body_collision.position = player._full_capsule_position
	player._capsule_reduced = false
	player.global_position = position
	player.velocity = velocity
	player.gameplay_active = true
	player.hud.game_started = true
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	course._finish_panel.hide()
	course.set_physics_process(false)
	course.clock.state = 0
	course.clock.elapsed = 0.0
	course.clock.checkpoint_splits.clear()
	course.clock.clean_run = true
	await frames(settle)

func advanced_routes() -> void:
	# These seed only the incoming state, then use attraction/release and swept
	# flight on the actual authored masses. They do not execute per-frame warps.
	await seed_approach(Vector3(0,13,-91), Vector3(0,3,-16))
	if await pull("GapSkipRing", 30):
		await frames(12)
		if await pull("GapExitRing", 30):
			await drive_to(Vector3(8,12,-146), "Expert gap landing")
			await frames(30)
			check(player.is_on_floor() and player.global_position.y > 12, "Expert gap bypass lands on the real exit roof")
	await seed_approach(Vector3(8,12.55,-164), Vector3.ZERO, 12)
	check(player.is_on_floor(), "Expert courtyard begins on a real approach roof")
	player.request_jump()
	await frames(6)
	if await pull("CourtyardSkipRing", 48):
		await frames(28)
		if await pull("CourtyardTopRing", 36):
			await drive_to(Vector3(0,24,-234), "Expert tower landing")
			await frames(30)
			check(player.is_on_floor() and player.global_position.y > 24, "Expert courtyard bypass reaches the real upper roof")
	await seed_approach(Vector3(-7,25.5,-248), Vector3(0,1,-16))
	if await pull("ChainLeftRing", 32):
		await frames(6)
		if await pull("ChainRightRing", 42):
			check(player.velocity.length() > 20, "Advanced corner carries momentum between successive live pulls")
			if await pull("ChainExitRing", 36):
				await drive_to(Vector3(0,24,-328), "Advanced chain landing")
				await frames(30)
				check(player.is_on_floor() and player.global_position.y > 24, "Advanced momentum chain reaches a real exit roof")
	await seed_approach(Vector3(-8,25.5,-338), Vector3(0,1,-24))
	if await pull("FinalLeftRing", 20):
		await frames(24)
		if await pull("FinalRightRing", 40):
			await frames(12)
			if await pull("FinishRing", 32):
				await drive_to(Vector3(0,24,-432), "Direct stored-speed finale landing")
				await frames(30)
				check(player.is_on_floor() and player.global_position.y > 24, "Stored-speed finale bypass lands beyond the actual finish gate")

func bridge_alternatives() -> void:
	# Each fallback is a separate real walking approach; only its start is seeded.
	await seed_approach(Vector3(10,12.55,-22), Vector3.ZERO, 12)
	for point in [Vector3(16,10,-26), Vector3(16,10,-33), Vector3(16,12,-47), Vector3(8,12,-47)]:
		if not await drive_to(point, "Intro catch bridge"):
			break
	await frames(20)
	check(player.is_on_floor() and player.global_position.y > 12, "Intro low catch rejoins the landing roof")
	await seed_approach(Vector3(-10,12.55,-84), Vector3.ZERO, 12)
	for point in [Vector3(-14,12,-104), Vector3(-14,12,-111), Vector3(14,12,-121), Vector3(14,12,-128), Vector3(12,12,-146)]:
		if not await drive_to(point, "Gap service bridge"):
			break
	await frames(20)
	check(player.is_on_floor() and player.global_position.y > 12, "Gap braid has a continuous recovery bridge")
	await seed_approach(Vector3(14,12.55,-157), Vector3.ZERO, 12)
	for point in [Vector3(14,12,-159), Vector3(30,16,-185), Vector3(30,20,-209), Vector3(30,24,-237), Vector3(14,24,-237), Vector3(0,24,-246)]:
		if not await drive_to(point, "Courtyard service climb"):
			break
	await frames(20)
	check(player.is_on_floor() and player.global_position.y > 24, "Courtyard slower ramps rejoin the upper gate roof")
	await seed_approach(Vector3(-15,24.55,-246), Vector3.ZERO, 12)
	for point in [Vector3(-30,22,-264), Vector3(-30,22,-315), Vector3(-21,24,-325), Vector3(-10,24,-332), Vector3(0,24,-339)]:
		if not await drive_to(point, "Chain lower service bridge"):
			break
	await frames(20)
	check(player.is_on_floor() and player.global_position.y > 24, "Chain lower fallback reconnects before its gate")

func checkpoint_recovery() -> void:
	var targets := ["IntroRing", "GapExitRing", "CourtyardTopRing", "ChainExitRing"]
	course.clock.state = 1
	course.clock.elapsed = 10.0
	course.clock.checkpoint_splits.clear()
	course.clock.clean_run = true
	for index in range(4):
		course._checkpoint_entered(player, index + 1)
		var marker: Marker3D = course._checkpoints[index].get_node("Respawn")
		player.global_position = marker.global_position + Vector3(0,2,12)
		player.velocity = Vector3(0,0,-20)
		player._anchor_cooldown = 0.0
		player._recent_anchor = null
		var target: Node3D = course.get_node(targets[index])
		aim_at(target)
		player.request_hook()
		check(player.is_hooking, "CP%d recovery begins with a live force/capsule state" % (index + 1))
		course.respawn_checkpoint()
		await frames(15)
		check(player.is_on_floor() and player.global_position.distance_to(marker.global_position) < 0.1, "CP%d actual respawn settles on broad roof" % (index + 1))
		check(not player.is_hooking and not player._capsule_reduced and not player.get_pull_debug().active and player.velocity.length() < 0.01, "CP%d clears force, carry and reduced capsule" % (index + 1))
		check(player.camera.rotation.is_zero_approx() and not course.clock.clean_run, "CP%d restores view and marks practice" % (index + 1))

func run() -> void:
	preference_existed = FileAccess.file_exists(Settings.SAVE_PATH)
	preference_bytes = FileAccess.get_file_as_bytes(Settings.SAVE_PATH) if preference_existed else PackedByteArray()
	best_existed = FileAccess.file_exists("user://parkour_bests.cfg")
	best_bytes = FileAccess.get_file_as_bytes("user://parkour_bests.cfg") if best_existed else PackedByteArray()
	initial_strength = Settings.effects_strength
	Settings.effects_strength = 0.0
	course = load("res://levels/parkour/rooftop_trial.tscn").instantiate()
	course.clock.save_path = save_path
	root.add_child(course)
	current_scene = course
	await frames(10)
	player = course.player
	root.get_node("SoundManager").music_player.stop()
	root.get_node("SoundManager").music_player.stream = null
	check(player.use_momentum_pull and player.vertical_look_enabled and not player.surf_mode, "Rooftop opts into momentum pull and pitch before player ready")
	check(course.clock.checkpoint_count == 4 and course._checkpoints.size() == 4, "Rooftop has four ordered checkpoint gates")
	check(player.is_on_floor(), "Spawn stands on authored roof collision")
	await safe_run()
	check(course.clock.state == 2 and course.clock.clean_run, "Input-driven rooftop attempt reaches real FINISH cleanly")
	check(course.clock.checkpoint_splits.size() == 4, "Actual body crosses all four ordered gates")
	var recording: Dictionary = course.last_finish_result.get("recording", {})
	var samples: Array = recording.get("samples", [])
	for index in range(1, samples.size()):
		safe_distance += samples[index - 1].transform.origin.distance_to(samples[index].transform.origin)
	check(recording.get("personal_best_eligible", false) and recording.get("course_id", "") == "rooftop_pull_v1" and samples.size() > 400, "Clean physical finish produces a bounded course-specific PB recording")
	check(FileAccess.file_exists(save_path), "Clean physical finish saves only to its isolated test path")
	print("ROOFTOP_SAFE_TIME ", course.clock.elapsed, " DISTANCE ", safe_distance, " STATE ", course.clock.state," CLEAN ", course.clock.clean_run)
	await advanced_routes()
	await bridge_alternatives()
	await checkpoint_recovery()
	var clear_routes := true
	for link in links:
		clear_routes = clear_routes and link.contacts.is_empty()
	check(clear_routes, "All 20 tested pull paths clear actual upright collision")
	check(FileAccess.file_exists(Settings.SAVE_PATH) == preference_existed and (FileAccess.get_file_as_bytes(Settings.SAVE_PATH) if preference_existed else PackedByteArray()) == preference_bytes, "Route probes never write actual effects preferences")
	check(FileAccess.file_exists("user://parkour_bests.cfg") == best_existed and (FileAccess.get_file_as_bytes("user://parkour_bests.cfg") if best_existed else PackedByteArray()) == best_bytes, "Route probes leave actual personal best file unchanged")
	Settings.effects_strength = initial_strength
	DirAccess.remove_absolute(save_path)
	for audio in root.get_node("SoundManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	course.queue_free()
	root.get_node("GameManager").player = null
	await frames(3)
	OS.delay_msec(200)
	print("ROOFTOP_RESULT ", JSON.stringify({"checks":checks,"failures":failures,"links":links}))
	quit(0 if failures.is_empty() else 1)
