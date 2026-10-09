extends SceneTree
## Independent approaches in the real city, using the city surf+momentum player.
## Pose/velocity are seeded once at each probe entry; all recorded motion then
## comes from production input, attraction, gravity and swept capsule collisions.
## This is not a full clean racing run or evidence of human balance/device feel.
## Godot --headless --fixed-fps 60 --path . --script tests/validate_main_city_flow.gd -- --flow-fps=60

const AudioCleanup = preload("res://tests/audio_test_cleanup.gd")
var course
var player
var fps := 60
var checks := 0
var failures: Array[String] = []
var metrics := {}
var manifest: Dictionary
var saved_files := {}
var save_path := "user://main_city_flow_%d.cfg" % OS.get_process_id()
var _trace: Array[Dictionary] = []
var _peak := 0.0
var _travel := 0.0
var _max_step := 0.0
var _wall_frames := 0
var _bank_frames := 0
var _last_bank := ""
var _airborne := false
var _landed := false
var _landed_on := ""
var _lowest_horizontal := INF
var _land_speed := 0.0
var _last_position := Vector3.ZERO
var _snags := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--flow-fps="):
			fps = int(argument.get_slice("=", 1))
	Engine.physics_ticks_per_second = fps
	call_deferred("run")

func frames(count: int) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame

func check(value: bool, message: String) -> void:
	checks += 1
	print("CITY_FLOW_CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)

func vector(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func route_point(sector: int, index: int) -> Vector3:
	var value: Array = manifest.sectors[sector-1].safe_points[index]
	return Vector3(value[0],value[1],value[2])

func fixture(sector: int, name: String) -> Node3D:
	return course.get_node("CitySections/Sector%02d/ArchitecturalAnchors/%s" % [sector,name])

func release_inputs() -> void:
	for action in ["move_forwards", "move_backwards", "move_left", "move_right", "jump_or_dash", "grapple"]:
		Input.action_release(action)
	player.hud.mobile_controls.reset_touches()
	player.hud.mobile_controls.enabled = false
	player.hud.mobile_controls.set_active(false)

func aim(target: Node3D) -> void:
	var offset: Vector3 = target.global_position - player.to_global(player._camera_base_pos)
	player.rotation.y = -atan2(offset.x,-offset.z)
	# Main-city intent is yaw-only; architectural targets above/below the player
	# must be acquired from the real level camera's existing forgiving cone.
	player.camera.rotation.x = 0.0
	player.grapple.aim_assist_target = null

func steer(point: Vector3) -> void:
	var offset: Vector3 = point-player.global_position
	offset.y = 0.0
	if offset.length() < 1.0:
		Input.action_release("move_forwards")
		return
	player.rotation.y = -atan2(offset.x,-offset.z)
	player.camera.rotation.x = 0.0
	Input.action_press("move_forwards")

func mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.device = 0
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	event.position = root.get_final_transform() * Vector2(640,360)
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func begin_probe(position: Vector3, velocity: Vector3) -> void:
	player.set_physics_process(false)
	release_inputs()
	player.reset_movement_input()
	mouse(false)
	player._end_hook(true)
	player._recent_anchor = null
	player._anchor_cooldown = 0.0
	player._hook_slide_timer = 0.0
	player._body_collision.shape = player._full_capsule
	player._body_collision.position = player._full_capsule_position
	player._capsule_reduced = false
	player.global_position = position
	player.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.camera.position = player._camera_base_pos
	player.velocity = Vector3.ZERO
	player.input_dir = Vector3.ZERO
	player.gameplay_active = true
	# Refresh the previous probe's grounded flag before the only velocity seed.
	player.move_and_slide()
	player.reset_movement_input()
	player.velocity = velocity
	player.set_physics_process(true)
	_trace.clear()
	_peak = velocity.length()
	_travel = 0.0
	_max_step = 0.0
	_wall_frames = 0
	_bank_frames = 0
	_last_bank = ""
	_airborne = false
	_landed = false
	_landed_on = ""
	_land_speed = 0.0
	_lowest_horizontal = Vector2(velocity.x,velocity.z).length()
	_last_position = player.global_position
	_snags = 0
	course.clock.state = 0
	course.clock.clean_run = false
	course.clock.checkpoint_splits.clear()

func sample() -> void:
	var step: float = _last_position.distance_to(player.global_position)
	_travel += step
	_max_step = maxf(_max_step,step)
	_last_position = player.global_position
	_peak = maxf(_peak,player.velocity.length())
	var horizontal: float = Vector2(player.velocity.x,player.velocity.z).length()
	_lowest_horizontal = minf(_lowest_horizontal,horizontal)
	if not player.is_on_floor():
		_airborne = true
	elif _airborne and not _landed:
		_landed = true
		_land_speed = horizontal
		for i in player.get_slide_collision_count():
			var collider = player.get_slide_collision(i).get_collider()
			if collider is Node:
				_landed_on = str(course.get_path_to(collider))
	if player.is_on_wall():
		_wall_frames += 1
		if horizontal < 1.0:
			_snags += 1
	var bank_contact := false
	var contacts: Array[Dictionary] = []
	for i in player.get_slide_collision_count():
		var collision = player.get_slide_collision(i)
		var collider = collision.get_collider()
		var normal: Vector3 = collision.get_normal()
		if collider is Node:
			contacts.append({"body":str(course.get_path_to(collider)),"normal":vector(normal)})
			if collider.get_parent().is_in_group("city_surf") and normal.y>.4 and normal.y<.7:
				bank_contact = true
				_last_bank = collider.get_parent().name
	if bank_contact:
		_bank_frames += 1
	_trace.append({"position":vector(player.global_position),"velocity":vector(player.velocity),"floor":player.is_on_floor(),"wall":player.is_on_wall(),"pulling":player.is_hooking,"contacts":contacts})

func tick(count: int, destination := Vector3.INF) -> void:
	for _index in range(count):
		if destination != Vector3.INF:
			steer(destination)
		await frames(1)
		sample()

func chase_safe(sector: int, count: int, look_ahead := 25.0) -> void:
	# A look-ahead racing line avoids braking to stop at an airborne waypoint.
	# This steers ordinary input only; it never writes position or velocity.
	var points: Array = manifest.sectors[sector-1].safe_points
	for _tick in range(count):
		var nearest := INF
		var segment := 0
		var progress := 0.0
		for i in range(points.size()-1):
			var a := route_point(sector,i)
			var b := route_point(sector,i+1)
			a.y = 0.0
			b.y = 0.0
			var position: Vector3 = player.global_position
			position.y = 0.0
			var t := clampf((position-a).dot(b-a)/(b-a).length_squared(),0.0,1.0)
			var distance := position.distance_squared_to(a.lerp(b,t))
			if distance < nearest:
				nearest = distance
				segment = i
				progress = t
		var remaining := look_ahead
		var target := route_point(sector,segment).lerp(route_point(sector,segment+1),progress)
		while segment < points.size()-1:
			var end := route_point(sector,segment+1)
			var length := Vector2(end.x-target.x,end.z-target.z).length()
			if remaining <= length:
				target = target.lerp(end,remaining/maxf(length,.001))
				break
			remaining -= length
			target = end
			segment += 1
		steer(target)
		await frames(1)
		sample()

func summary(label: String) -> void:
	var compressed: Array[Dictionary] = []
	for i in range(0,_trace.size(),maxi(1,fps/10)):
		var entry: Dictionary = _trace[i].duplicate()
		entry["seconds"] = float(i+1)/fps
		compressed.append(entry)
	metrics[label] = {"entry_seeded":true,"position":vector(player.global_position),"velocity":vector(player.velocity),"seconds":float(_trace.size())/fps,
		"peak_speed":_peak,"travelled":_travel,"max_step":_max_step,"wall_frames":_wall_frames,"bank_frames":_bank_frames,"last_bank":_last_bank,"snags":_snags,"minimum_horizontal":_lowest_horizontal,
		"airborne":_airborne,"landed":_landed,"landing_speed":_land_speed,"landed_on":_landed_on,"trace":compressed}
	check(_peak <= player.parkour_speed_limit+0.02 and _max_step <= player.parkour_speed_limit/fps+0.04,label+" remains capped with continuous swept motion")
	check(_snags == 0,label+" has no sustained stopped wall snag")

func start_pull(target: Node3D, label: String) -> void:
	aim(target)
	check(player.grapple.get_lock_target() == target,label+" acquires the architectural fixture through production range/cone/LOS")
	mouse(true)
	check(player.is_hooking and player._hook_target == target,label+" real held mouse press starts the intended pull")

func end_pull(label: String) -> void:
	var before: Vector3 = player.velocity
	mouse(false)
	check(not player.is_hooking and player.velocity.distance_to(before) < 0.001,label+" mouse-up releases immediately without replacing velocity")

func opening() -> void:
	begin_probe(Vector3(0,24.55,12),Vector3(0,0,-12))
	start_pull(fixture(1,"EaveRing00"),"Opening eave")
	await tick(maxi(1,roundi(.14*fps)))
	check(player.velocity.x > 0.5 and player.velocity.z < -10.0,"Opening pull bends the line while retaining forward momentum")
	end_pull("Opening eave")
	await tick(roundi(2.0*fps),Vector3(-2,24,-35))
	check(_landed and _land_speed > 8.0,"Opening arc lands on an authored roof with useful carried speed")
	summary("opening_eave")

func blackglass() -> void:
	var bank: Node3D = course.get_node("CitySections/Sector03/Architecture/FactoryBank0_1")
	var normal: Vector3 = bank.global_basis.y.normalized()
	var support: float = player._full_capsule.radius+(player._full_capsule.height*.5-player._full_capsule.radius)*normal.y
	var surface := bank.to_global(Vector3(0,.4,8))
	var position: Vector3 = surface+Vector3.UP*(support/normal.y-player._full_capsule_position.y+.035)
	var direction: Vector3 = bank.global_basis.z.normalized()
	if direction.z > 0.0:
		direction = -direction
	begin_probe(position,direction*18.0)
	var start: Vector3 = player.global_position
	await tick(roundi(1.0*fps))
	check(_bank_frames >= roundi(.25*fps),"Blackglass skim makes sustained actual52-degree bank contact")
	check(player.global_position.y < start.y-.5 and Vector2(player.velocity.x,player.velocity.z).length()>12.0,"Blackglass gravity descent retains forward bank momentum")
	await chase_safe(3,roundi(.8*fps),20.0)
	check(_last_bank=="FactoryBank1_1" and player.global_position.z < -550.0,"Blackglass skim transfers into the next authored bank without reset")
	summary("blackglass_bank")

func bell_corner() -> void:
	begin_probe(route_point(5,3)+Vector3.UP*.55,Vector3(0,0,-24))
	start_pull(fixture(5,"OuterBellRing"),"Bell corner")
	await tick(roundi(.55*fps))
	check(player.velocity.x > 12.0,"Bell anchor curves inherited forward motion toward the outer apex")
	end_pull("Bell corner")
	await chase_safe(5,roundi(2.7*fps),22.0)
	check(_landed and _land_speed>10.0,"Bell-assisted apex rejoins a city roof or lower catch with momentum")
	summary("bell_assisted_apex")

func spire() -> void:
	begin_probe(route_point(6,2)+Vector3.UP*.55,Vector3(4,0,-14))
	var start: Vector3 = player.global_position
	start_pull(fixture(6,"SpireBrace04"),"Spire balcony")
	await tick(roundi(.4*fps))
	check(player.global_position.y>start.y+1.0 and player.velocity.y>8.0,"Spire architectural brace creates a useful rising arc")
	end_pull("Spire balcony")
	await tick(roundi(2.8*fps),Vector3(175,38,-1200))
	check(_landed and player.global_position.y>start.y+5.0,"Spire pull reaches a higher authored roof or recovery balcony")
	summary("spire_lift")

func final_send() -> void:
	var ridge = course.get_node("CitySections/Sector07/FinalPressureRidge")
	var start_activations: int = ridge.activations
	begin_probe(Vector3(ridge.global_position.x,68.55,-1342),Vector3(0,0,-20))
	var launched := false
	for _i in range(fps):
		await tick(1)
		if ridge.activations>start_activations:
			launched = true
			break
	check(launched and player.velocity.y>5.0,"Final pressure ridge launches once through actual capsule entry")
	await tick(roundi(.65*fps))
	start_pull(fixture(7,"CraneRing02"),"Final crane")
	await tick(roundi(.15*fps))
	end_pull("Final crane")
	await chase_safe(7,roundi(3.4*fps),25.0)
	check(_airborne and _landed and _land_speed>10.0,"Final ridge/pull release completes a real flight onto city roof collision")
	check(ridge.activations==start_activations+1,"Final ridge applies one launch for its physical entry")
	summary("final_ridge_flight")

func run() -> void:
	for path in ["user://parkour_bests.cfg","user://parkour_settings.cfg"]:
		saved_files[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/main_city/route_manifest.json"))
	course = load("res://levels/parkour/MainCityRun.tscn").instantiate()
	course.clock.save_path = save_path
	root.add_child(course)
	current_scene = course
	player = course.player
	course.set_physics_process(false)
	player.set_process(false)
	root.get_node("SoundManager").music_player.stop()
	await frames(3)
	check(player.surf_mode and player.use_momentum_pull and not player.vertical_look_enabled,"Probes use the actual hybrid city profile with a level camera")
	await opening()
	await blackglass()
	await bell_corner()
	await spire()
	await final_send()
	for path in saved_files:
		var after = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		check(after==saved_files[path],path.get_file()+" remains byte identical")
	release_inputs()
	AudioCleanup.stop_voices(self)
	root.get_node("GameManager").player = null
	course.queue_free()
	await frames(3)
	AudioCleanup.drain_mixer()
	DirAccess.remove_absolute(save_path)
	print("MAIN_CITY_FLOW_RESULT ",JSON.stringify({"physics_fps":fps,"checks":checks,"failures":failures,"metrics":metrics}))
	quit(0 if failures.is_empty() else 1)
