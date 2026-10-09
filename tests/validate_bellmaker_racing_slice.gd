extends "res://tests/validate_main_city_flow.gd"
## Actual exported Bellmaker lines. A line gets one CP4 entry seed; every later
## step uses ordinary movement, parsed Space and production held mouse input.
## Separate gap entries compare the same real jump at different incoming speeds.
## These are scripted engine routes, not human discovery or readability evidence.
## Godot --headless --fixed-fps 60 --path . --script tests/validate_bellmaker_racing_slice.gd -- --flow-fps=60

var slice: Dictionary
var _jump_release := false
var _pull_remaining := 0.0
var _pull_fixture: Node3D
var _device_contacts := {}
var _floor_contacts := {}
var _jump_count := 0
var _pull_count := 0
var _checkpoint_exit := false
var _entry_seed := {}
var _recovered := false
var _used_fixtures := {}
var _spring_counts := {}
var _contact_steps := {}
var _action_log: Array[Dictionary] = []
var _gap_approached := false
var _missed_gap_caught := false
var _upper_floor_peak := -INF
var _low_floor_min := INF
var _gap_entry_pose := {}
var _upper_gap_crossed := false
var _gap_crossing_pose := {}
var _brake_remaining := 0.0
var _brake_heading := Vector3.RIGHT
var _brake_count := 0
var _brake_frames := 0
var _high_rejoin_after_gap := false
var _after_gap_landing_pose := {}

func check(value: bool, message: String) -> void:
	checks += 1
	print("BELL_SLICE_CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)

func vec(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

func space(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.keycode = KEY_SPACE
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func backwards(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_S
	event.keycode = KEY_S
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func begin_probe(position: Vector3, velocity: Vector3) -> void:
	super.begin_probe(position, velocity)
	space(false)
	backwards(false)
	_jump_release = false
	_pull_remaining = 0.0
	_pull_fixture = null
	_device_contacts.clear()
	_floor_contacts.clear()
	_jump_count = 0
	_pull_count = 0
	_checkpoint_exit = false
	_recovered = false
	_used_fixtures.clear()
	_spring_counts.clear()
	_contact_steps.clear()
	_action_log.clear()
	_gap_approached = false
	_missed_gap_caught = false
	_upper_floor_peak = -INF
	_low_floor_min = INF
	_gap_entry_pose.clear()
	_upper_gap_crossed = false
	_gap_crossing_pose.clear()
	_brake_remaining = 0.0
	_brake_count = 0
	_brake_frames = 0
	_high_rejoin_after_gap = false
	_after_gap_landing_pose.clear()
	for spec in slice.get("passive_devices", []):
		var device = course.get_node_or_null(NodePath(spec.path))
		if is_instance_valid(device) and device.has_method("step_velocity"):
			_contact_steps[str(spec.name)] = int(device.contact_steps)
		if str(spec.get("type", "")) == "spring":
			var spring = device
			if is_instance_valid(spring):
				_spring_counts[str(spec.name)] = int(spring.activations)
	_entry_seed = {"position": vector(player.global_position), "velocity": vector(velocity)}
	# Prefix times model an already completed CP1..CP4. The seeded slice is
	# practice and cannot manufacture records; CP5 must still be entered by
	# the moving body through its production Area3D callback.
	course.clock.elapsed = 4.0
	course.clock.checkpoint_splits.assign([1.0, 2.0, 3.0, 4.0])
	course.clock.sector_times.assign([1.0, 1.0, 1.0, 1.0])
	course.clock.sector_start_elapsed = 4.0
	course.clock.state = course.Clock.State.RUNNING
	course.clock.clean_run = false
	course._respawn = course._checkpoints[3].get_node("Respawn")
	course.recorder.mark_practice()
	course.set_physics_process(true)

func sample() -> void:
	super.sample()
	if Input.is_action_pressed("move_backwards"):
		_brake_frames += 1
	if slice.has("gap"):
		var takeoff := vec(slice.gap.takeoff)
		var flat_distance := Vector2(player.global_position.x - takeoff.x, player.global_position.z - takeoff.z).length()
		_gap_approached = _gap_approached or (flat_distance < 3.0 and player.global_position.y > takeoff.y - 1.0)
		if _gap_approached and _gap_entry_pose.is_empty():
			_gap_entry_pose = {"position": vector(player.global_position), "velocity": vector(player.velocity), "grounded": player.is_on_floor(), "seconds": float(_trace.size()) / fps}
		var edge := vec(slice.gap.takeoff_edge)
		var heading := vec(slice.gap.forward).normalized()
		var progress: float = (player.global_position - edge).dot(heading)
		var side := heading.cross(Vector3.UP)
		var lateral: float = absf((player.global_position - edge).dot(side))
		if _gap_approached and progress >= float(slice.gap.span) - player._full_capsule.radius and progress <= float(slice.gap.span) + 1.0 + player.parkour_speed_limit / fps and lateral < 3.0 and player.global_position.y >= edge.y - .1:
			_upper_gap_crossed = true
			if _gap_crossing_pose.is_empty():
				_gap_crossing_pose = {"position": vector(player.global_position), "velocity": vector(player.velocity), "grounded": player.is_on_floor(), "seconds": float(_trace.size()) / fps}
	_checkpoint_exit = _checkpoint_exit or course.clock.checkpoint_splits.size() == 5
	if course.clock.sector_start_elapsed > 4.0 and not _checkpoint_exit:
		_recovered = true
	for index in player.get_slide_collision_count():
		var collision = player.get_slide_collision(index)
		var body = collision.get_collider()
		if body is Node and collision.get_normal().y > .7:
			var path := str(course.get_path_to(body))
			_floor_contacts[path] = true
			if player.is_on_floor() and path.contains("BellUpperGallery"):
				_upper_floor_peak = maxf(_upper_floor_peak, player.global_position.y)
			if _upper_gap_crossed and player.is_on_floor() and (path.contains("BellGapLanding") or (path.contains("BellUpperGallery") and player.global_position.y >= 24.4)):
				_high_rejoin_after_gap = true
				if _after_gap_landing_pose.is_empty():
					_after_gap_landing_pose = {"position": vector(player.global_position), "velocity": vector(player.velocity), "body": path, "seconds": float(_trace.size()) / fps}
			if player.is_on_floor() and path.contains("BellPressureAlley"):
				_low_floor_min = minf(_low_floor_min, player.global_position.y)
				_missed_gap_caught = _missed_gap_caught or _gap_approached
	for spec in slice.get("passive_devices", []):
		var device = course.get_node_or_null(NodePath(spec.path))
		if device is Area3D and device.overlaps_body(player):
			_device_contacts[str(spec.name)] = int(_device_contacts.get(str(spec.name), 0)) + 1

func line_frame(destination: Vector3, corner_braking := false) -> void:
	if _jump_release:
		space(false)
		_jump_release = false
	var release_brake := false
	if _brake_remaining > 0.0:
		player.rotation.y = atan2(-_brake_heading.x, -_brake_heading.z)
		player.camera.rotation.x = 0.0
		Input.action_release("move_forwards")
		_brake_remaining -= 1.0 / fps
		release_brake = _brake_remaining <= .00001
	elif _pull_remaining > 0.0 and is_instance_valid(_pull_fixture):
		aim(_pull_fixture)
		Input.action_press("move_forwards")
		_pull_remaining -= 1.0 / fps
		if _pull_remaining <= 0.0:
			mouse(false)
			_pull_fixture = null
	elif not player.is_on_floor():
		# Production air control turns the earned horizontal vector toward W.
		# A desired-minus-current ground controller would point W backwards in
		# an airborne turn and falsely brake the launch before testing the gap.
		steer(destination)
	else:
		# Every line uses the same lookahead and ordinary yaw/W policy. Preserve
		# straight carry; anticipate sharp corners with ordinary opposing input.
		# The desired velocity chooses input direction only, never body velocity.
		var horizontal: Vector3 = Vector3(player.velocity.x, 0, player.velocity.z)
		var offset: Vector3 = destination - player.global_position
		offset.y = 0.0
		var desired_speed: float = 8.0 if corner_braking else maxf(8.0, horizontal.length())
		var steering: Vector3 = offset.normalized() * desired_speed - horizontal
		if steering.length() > .25:
			player.rotation.y = atan2(-steering.x, -steering.z)
			Input.action_press("move_forwards")
		else:
			steer(destination)
		player.camera.rotation.x = 0.0
	await frames(1)
	sample()
	if release_brake:
		backwards(false)
		_brake_remaining = 0.0
		_action_log.append({"type": "brake_end", "seconds": float(_trace.size()) / fps,
			"position": vector(player.global_position), "velocity": vector(player.velocity), "frames": _brake_frames})

func action(event: Dictionary) -> void:
	var record := {"type": event.type, "seconds": float(_trace.size()) / fps,
		"position": vector(player.global_position), "incoming_velocity": vector(player.velocity)}
	match str(event.type):
		"jump":
			space(true)
			_jump_release = true
			_jump_count += 1
		"pull":
			_pull_fixture = fixture(5, str(event.target))
			_used_fixtures[str(event.target)] = int(_used_fixtures.get(str(event.target), 0)) + 1
			aim(_pull_fixture)
			check(player.grapple.get_lock_target() == _pull_fixture, str(event.target) + " is acquired from its line through the production level-camera cone and LOS")
			mouse(true)
			_pull_count += 1
			_pull_remaining = float(event.get("hold_seconds", .4))
			check(player.is_hooking, str(event.target) + " actual held mouse starts its line action")
		"brake":
			_brake_heading = vec(event.get("heading", [1, 0, 0])).normalized()
			_brake_heading.y = 0.0
			player.rotation.y = atan2(-_brake_heading.x, -_brake_heading.z)
			Input.action_release("move_forwards")
			backwards(true)
			_brake_remaining = float(event.get("hold_seconds", .2))
			_brake_count += 1
			check(Input.is_action_pressed("move_backwards"), "Missed expert uses an authenticated physical S action to brake its earned launch")
	record["resulting_velocity"] = vector(player.velocity)
	_action_log.append(record)

func action_ready(event: Dictionary) -> bool:
	if str(event.type) != "pull":
		return true
	# The zone identifies the architectural decision, rather than asking for
	# an impossible early click outside range. Press once the real Pull cue can
	# select this fixture while still inside that same authored approach zone.
	var prior_yaw: float = player.rotation.y
	var target := fixture(5, str(event.target))
	aim(target)
	var selected: bool = player.grapple.get_lock_target() == target
	player.rotation.y = prior_yaw
	player.grapple.aim_assist_target = null
	return selected

func follow_line(spec: Dictionary) -> Dictionary:
	var marker: Marker3D = course._checkpoints[3].get_node("Respawn")
	begin_probe(marker.global_position, course._checkpoints[3].practice_velocity())
	var pending: Array = spec.get("actions", []).duplicate(true)
	var reached := true
	for index in range(spec.points.size()):
		var destination := vec(spec.points[index])
		var segment_start := vec(spec.points[index - 1]) if index > 0 else marker.global_position
		var segment := Vector3(destination.x - segment_start.x, 0, destination.z - segment_start.z)
		var done := false
		for _tick in range(fps * 40):
			var flat: Vector3 = destination - player.global_position
			flat.y = 0.0
			for event in pending.duplicate():
				var trigger := vec(event.get("position", spec.points[int(event.get("at_index", index))]))
				if player.global_position.distance_to(trigger) <= float(event.get("trigger_distance", 2.0)) and action_ready(event):
					action(event)
					pending.erase(event)
			var progress: float = Vector3(player.global_position.x - segment_start.x, 0, player.global_position.z - segment_start.z).dot(segment) / maxf(segment.length_squared(), .01)
			if flat.length() < float(spec.get("waypoint_radius", 1.4)) or progress >= 1.0 or _checkpoint_exit:
				done = true
				break
			var lookahead := 5.0
			var target: Vector3 = destination
			var corner_braking := false
			if index + 1 < spec.points.size() and flat.length() < lookahead:
				var next := vec(spec.points[index + 1])
				var next_length := Vector2(next.x - destination.x, next.z - destination.z).length()
				target = destination.lerp(next, clampf((lookahead - flat.length()) / maxf(next_length, .01), 0, 1))
			if index + 1 < spec.points.size() and not segment.is_zero_approx():
				var next := vec(spec.points[index + 1]) - destination
				next.y = 0.0
				var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
				corner_braking = segment.normalized().dot(next.normalized()) < cos(deg_to_rad(30.0)) and flat.length() < maxf(8, speed * .8)
			await line_frame(target, corner_braking)
			if _recovered:
				break
		if not done:
			reached = false
			print("BELL_LINE_STOP ", JSON.stringify({"name": spec.name, "waypoint": index,
				"destination": vector(destination), "position": vector(player.global_position),
				"velocity": vector(player.velocity), "last_sample": _trace.back() if not _trace.is_empty() else {}, "recovered": _recovered}))
			break
		if _checkpoint_exit:
			break
	space(false)
	mouse(false)
	backwards(false)
	Input.action_release("move_forwards")
	var name := str(spec.name)
	check(reached and _checkpoint_exit, name + " reaches actual CP5 after one entry seed and ordinary input")
	check(not _recovered and _max_step <= player.parkour_speed_limit / fps + .10, name + " has no intermediate warp, retry or discontinuous movement")
	check(not course.clock.clean_run and course.clock.checkpoint_splits.size() == 5, name + " remains practice with the correct ordered checkpoint progress")
	var sector_seconds: float = course.clock.last_sector_time if _checkpoint_exit else course.clock.current_sector_elapsed
	check(absf(sector_seconds - float(_trace.size()) / fps) <= 2.0 / fps, name + " shared sector clock agrees with its physical elapsed frames")
	check(is_zero_approx(player.camera.rotation.x), name + " uses horizontal manual aim throughout")
	check(_peak <= player.parkour_speed_limit + .02, name + " stays within the shared speed cap")
	check(not player._capsule_reduced and player._body_collision.shape == player._full_capsule, name + " restores the full upright capsule at its physical exit")
	var repeated := false
	for count in _used_fixtures.values():
		repeated = repeated or int(count) > 1
	check(not repeated, name + " does not require repeated use of any pull fixture")
	if name == "mid":
		check(_pull_count > 0, "Mid line physically executes its optional acquired pull")
	if name == "expert":
		check(_upper_gap_crossed and _high_rejoin_after_gap and not _after_gap_landing_pose.is_empty(), "Complete expert line crosses the upper gap then physically rejoins a high roof with earned launch momentum")
	if name == "failed_expert":
		check(_gap_approached and _missed_gap_caught and not _upper_gap_crossed, "Failed expert physically misses the upper gap then lands in its lower catch before returning")
		check(_brake_count > 0 and _brake_frames > 0, "Failed expert records real backwards-input frames rather than replacing velocity")
	var spring_activations := {}
	for spec_device in slice.get("passive_devices", []):
		if str(spec_device.get("type", "")) == "spring":
			var spring = course.get_node_or_null(NodePath(spec_device.path))
			if is_instance_valid(spring):
				var count := int(spring.activations) - int(_spring_counts.get(str(spec_device.name), 0))
				spring_activations[str(spec_device.name)] = count
				check(count <= 1, name + " activates " + str(spec_device.name) + " at most once during its physical passage")
	if name == "high" and spring_activations.has("BellGallerySpring"):
		check(int(spring_activations.BellGallerySpring) == 1, "High line physically enters the authored spring and receives exactly one launch")
	var force_steps := {}
	for spec_device in slice.get("passive_devices", []):
		var device = course.get_node_or_null(NodePath(spec_device.path))
		if is_instance_valid(device) and device.has_method("step_velocity"):
			force_steps[str(spec_device.name)] = int(device.contact_steps) - int(_contact_steps.get(str(spec_device.name), 0))
	if name == "low" or name == "failed_expert":
		check(int(force_steps.get("BellPressureBoost", 0)) > 0 and int(force_steps.get("BellPressureReturn", 0)) > 0, name + " receives actual contact boost and pressure lift on its physical route")
	var required_contacts: Array = spec.get("must_contact", []).duplicate()
	if name == "high":
		required_contacts.append("BellUpperGallery")
		check(_upper_floor_peak >= 24.4, "High line physically stands on the 24m upper gallery")
	if name == "low" or name == "failed_expert":
		required_contacts.append("BellPressureAlley")
		check(_low_floor_min <= 8.0, name + " physically uses the 7m lower catch rather than silently staying above it")
	for required in required_contacts:
		var contacted := false
		for path in _floor_contacts:
			contacted = contacted or str(path).contains(str(required))
		for device in _device_contacts:
			contacted = contacted or str(device).contains(str(required))
		check(contacted, name + " physically contacts its intended " + str(required))
	var result := {"entry_seeded": true, "entry": _entry_seed.duplicate(true), "driver": "carry5m_lookahead_ground_corners_air_forward", "seconds": sector_seconds, "sampled_seconds": float(_trace.size()) / fps,
		"exit_position": vector(player.global_position), "exit_velocity": vector(player.velocity),
		"exit_speed": player.velocity.length(), "peak_speed": _peak, "travelled": _travel,
		"max_step": _max_step, "snags": _snags, "jumps": _jump_count, "pulls": _pull_count,
		"device_contacts": _device_contacts.duplicate(), "support_bodies": _floor_contacts.keys(),
		"checkpoint_exit": _checkpoint_exit, "recovered": _recovered, "fixtures": _used_fixtures.duplicate(), "spring_activations": spring_activations,
		"force_steps": force_steps, "actions": _action_log.duplicate(true), "gap_approached": _gap_approached, "missed_gap_caught": _missed_gap_caught,
		"brakes": _brake_count, "backwards_frames": _brake_frames,
		"upper_gap_crossed": _upper_gap_crossed, "gap_entry": _gap_entry_pose.duplicate(true), "gap_crossing": _gap_crossing_pose.duplicate(true),
		"high_rejoin_after_gap": _high_rejoin_after_gap, "after_gap_landing": _after_gap_landing_pose.duplicate(true),
		"upper_floor_peak": _upper_floor_peak if is_finite(_upper_floor_peak) else null,
		"low_floor_min": _low_floor_min if is_finite(_low_floor_min) else null}
	metrics[name] = result
	print("BELL_LINE_RESULT ", JSON.stringify(result.merged({"name": name})))
	return result

func passive_targets() -> void:
	for spec in slice.get("passive_devices", []):
		var device = course.get_node_or_null(NodePath(spec.path))
		check(device is Area3D and device.collision_layer == 0 and device.collision_mask == 4, str(spec.name) + " is a passive player-only overlap area")
		if not device is Node3D:
			continue
		check(not device.is_in_group("grapple_anchors") and not player.grapple.can_hook_target(device), str(spec.name) + " cannot be an active pull target")
		var point: Vector3 = device.global_position + Vector3(0, 1, 5)
		begin_probe(point, Vector3.ZERO)
		player.set_physics_process(false)
		aim(device)
		check(player.grapple.get_lock_target() != device, str(spec.name) + " is rejected by production target selection even when aimed at directly")

func decision_fixtures() -> void:
	var decision: Dictionary = slice.get("decision", {})
	var names: Array = decision.get("fixtures", [])
	check(names.size() >= 2 and names.size() <= 4, "Decision exposes two to four useful pull fixtures")
	for name in names:
		begin_probe(vec(decision.position), Vector3(0, 0, -12))
		player.set_physics_process(false)
		var target := fixture(5, str(name))
		aim(target)
		check(player.grapple.get_lock_target() == target and is_zero_approx(player.camera.rotation.x), str(name) + " acquires from the common decision with level camera")

func gap_trial(speed: float) -> Dictionary:
	var gap: Dictionary = slice.gap
	var heading := vec(gap.forward).normalized()
	begin_probe(vec(gap.takeoff), heading * speed)
	steer(vec(gap.landing))
	await frames(1)
	sample()
	space(true)
	check(player.velocity.y >= player.JUMP_SPEED, "Gap " + str(speed) + "m/s real Space applies the unchanged jump")
	space(false)
	var crossed := false
	var landing_contact := false
	var catch_contact := false
	for _tick in range(fps * 5):
		# Hold ordinary forward input without a steering brake during the jump.
		steer(vec(gap.landing))
		await frames(1)
		sample()
		var progress: float = (player.global_position - vec(gap.takeoff)).dot(heading)
		crossed = crossed or (progress >= float(gap.span) - player._full_capsule.radius and player.global_position.y >= vec(gap.landing).y - 1.0)
		for path in _floor_contacts:
			catch_contact = catch_contact or str(path).contains(str(gap.get("catch_name", "ExpertLowCatch")))
			landing_contact = landing_contact or str(path).contains(str(gap.get("landing_name", "BellGapLanding")))
		if player.is_on_floor() and _airborne:
			break
	Input.action_release("move_forwards")
	var result := {"entry_speed": speed, "crossed": crossed, "catch_contact": catch_contact, "landing_contact": landing_contact,
		"position": vector(player.global_position), "velocity": vector(player.velocity),
		"seconds": float(_trace.size()) / fps, "landed_on": _floor_contacts.keys(), "max_step": _max_step}
	print("BELL_GAP_RESULT ", JSON.stringify(result))
	metrics["gap_" + str(speed)] = result
	return result

func gap_geometry() -> void:
	var gap: Dictionary = slice.gap
	var space_state = player.get_world_3d().direct_space_state
	var from: Vector3 = vec(gap.get("takeoff_edge", gap.takeoff))
	var to: Vector3 = vec(gap.get("landing_edge", gap.landing))
	var distance := Vector2(to.x - from.x, to.z - from.z).length()
	check(absf(distance - 24.0) < .05, "Actual authored gap edges are 24m apart")
	var unsupported := true
	var supported_catch := true
	for index in range(1, 24):
		var point := from.lerp(to, float(index) / 24.0)
		var hit: Dictionary = space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2, point - Vector3.UP * 30, 1, [player.get_rid()]))
		unsupported = unsupported and (hit.is_empty() or hit.position.y < point.y - 3)
		supported_catch = supported_catch and not hit.is_empty()
	check(unsupported, "Gap interior has no hidden floor that can turn the jump into walking")
	check(supported_catch, "The full unsupported span has a physical lower recovery roof")

func run() -> void:
	for path in ["user://parkour_bests.cfg", "user://parkour_settings.cfg"]:
		saved_files[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/main_city/route_manifest.json"))
	slice = manifest.get("bellmaker_slice", {})
	check(not slice.is_empty(), "Authored manifest supplies the Bellmaker racing slice")
	if slice.is_empty():
		quit(1)
		return
	save_path = "user://bellmaker_slice_%d.cfg" % OS.get_process_id()
	course = load("res://levels/parkour/MainCityRun.tscn").instantiate()
	course.clock.save_path = save_path
	root.add_child(course)
	current_scene = course
	player = course.player
	player.set_process(false)
	await frames(3)
	check(player.surf_mode and player.use_momentum_pull and not player.vertical_look_enabled, "Slice uses the unchanged actual main-city body and level camera")
	decision_fixtures()
	passive_targets()
	var names: Array = []
	for spec in slice.get("lines", []):
		names.append(str(spec.name))
		await follow_line(spec)
	for required in ["safe", "mid", "high", "low", "expert"]:
		check(required in names, "Manifest provides the " + required + " complete racing line")
	check(is_equal_approx(float(slice.gap.span), 24.0), "Expert gap has a declared 24m unsupported span")
	gap_geometry()
	var slow: Dictionary = await gap_trial(float(slice.gap.get("low_speed", 8.0)))
	var fast: Dictionary = await gap_trial(float(slice.gap.get("high_speed", 24.0)))
	check(not slow.crossed and slow.catch_contact, "Low-speed real jump fails into the physical lower catch")
	check(fast.crossed and fast.landing_contact, "High-speed real jump lands beyond the 24m gap without an active pull")
	if slice.has("failed_expert"):
		var recovery: Dictionary = await follow_line(slice.failed_expert)
		if metrics.has("expert"):
			check(recovery.seconds > metrics.expert.seconds, "Failed expert catch and physical return cost time against the completed expert line")
	else:
		check(false, "Manifest supplies a complete failed-expert lower catch and return route")
	check(not FileAccess.file_exists(save_path), "Seeded slice and gap practice never save total or sector records")
	for path in saved_files:
		var after = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		check(after == saved_files[path], path.get_file() + " remains byte identical")
	release_inputs()
	space(false)
	backwards(false)
	AudioCleanup.stop_voices(self)
	root.get_node("GameManager").player = null
	course.queue_free()
	await frames(3)
	AudioCleanup.drain_mixer()
	DirAccess.remove_absolute(save_path)
	DirAccess.make_dir_recursive_absolute("res://build")
	var output := FileAccess.open("res://build/bellmaker_racing_slice%d.json" % fps, FileAccess.WRITE)
	output.store_string(JSON.stringify({"physics_fps": fps, "checks": checks, "failures": failures, "metrics": metrics}, "\t"))
	output.close()
	print("BELLMAKER_SLICE_RESULT ", JSON.stringify({"physics_fps": fps, "checks": checks, "failures": failures, "metrics": metrics}))
	quit(0 if failures.is_empty() else 1)
