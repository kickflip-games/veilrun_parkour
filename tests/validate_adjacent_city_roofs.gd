extends "res://tests/validate_main_city_flow.gd"
## Independent real-capsule approaches to selected existing visual buildings.
## Each probe seeds pose and velocity once, then uses ordinary movement and
## production held pull input. These probes do not establish a complete route
## detour, human launch accuracy or physical-device handling.
## Godot --headless --fixed-fps 60 --path . --script tests/validate_adjacent_city_roofs.gd

var _roof: Dictionary
var _roof_floor_frames := 0
var _roof_first_contact := {}
var _roof_last_contact := {}
var _roof_left := false
var _return_floor := false
var _return_body := ""
var _return_speed := 0.0
var _roof_wall_contacts := 0
var _surface_error := 0.0
var _incoming_velocity := Vector3.ZERO
var _entry_seed := {}

func check(value: bool, message: String) -> void:
	checks += 1
	print("CITY_ADJACENT_CHECK ", "PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)

func point(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])

func roof_center() -> Vector3:
	return point(_roof.center)

func roof_height(position: Vector3) -> float:
	return roof_center().y+float(_roof.rise)*(1.0-absf(position.x-roof_center().x)/(float(_roof.size[0])*.5))

func is_roof_body(body: Node) -> bool:
	return body is StaticBody3D and body.get_parent().name in _roof.collider_names and str(course.get_path_to(body.get_parent())).begins_with(str(_roof.collider_parent))

func is_route_body(body: Node) -> bool:
	return body is StaticBody3D and (body.get_parent().is_in_group("city_safe") or body.get_parent().is_in_group("city_recovery"))

func begin_probe(position: Vector3, velocity: Vector3) -> void:
	super.begin_probe(position,velocity)
	_entry_seed = {"position":vector(position),"velocity":vector(velocity),"support_position":vector(player.global_position)}
	_roof_floor_frames = 0
	_roof_first_contact = {}
	_roof_last_contact = {}
	_roof_left = false
	_return_floor = false
	_return_body = ""
	_return_speed = 0.0
	_roof_wall_contacts = 0
	_surface_error = 0.0
	_incoming_velocity = velocity

func sample() -> void:
	var before := _incoming_velocity
	var supported_on_roof := false
	super.sample()
	for i in player.get_slide_collision_count():
		var collision = player.get_slide_collision(i)
		var body = collision.get_collider()
		if not body is Node:
			continue
		var normal: Vector3 = collision.get_normal()
		if is_roof_body(body):
			if normal.y > .7 and player.is_on_floor():
				supported_on_roof = true
				var contact := {"body":str(course.get_path_to(body)),"position":vector(player.global_position),"velocity":vector(player.velocity),"normal":vector(normal),"seconds":float(_trace.size())/fps,"incoming":vector(before)}
				if _roof_first_contact.is_empty():
					_roof_first_contact = contact
				_roof_last_contact = contact
				if str(body.get_parent().name).ends_with("Gable"):
					# Capsule support distance against the manifest's exact visual
					# gable plane. Ridge crossings use the supporting face normal.
					var support: float = player._full_capsule.radius/normal.y+(player._full_capsule.height*.5-player._full_capsule.radius)-player._full_capsule_position.y
					_surface_error = maxf(_surface_error,absf(player.global_position.y-roof_height(player.global_position)-support))
			elif normal.y < .7:
				_roof_wall_contacts += 1
		if is_route_body(body) and player.is_on_floor() and normal.y>.7 and not _roof_first_contact.is_empty():
			_return_floor = true
			_return_body = str(course.get_path_to(body))
			_return_speed = Vector2(player.velocity.x,player.velocity.z).length()
	if supported_on_roof:
		_roof_floor_frames += 1
	if _roof_floor_frames > 0 and not player.is_on_floor():
		_roof_left = true
	_incoming_velocity = player.velocity

func summary(label: String) -> void:
	super.summary(label)
	metrics[label]["roof_id"] = _roof.id
	metrics[label]["entry_seed"] = _entry_seed
	metrics[label]["roof_floor_frames"] = _roof_floor_frames
	metrics[label]["roof_floor_seconds"] = float(_roof_floor_frames)/fps
	metrics[label]["first_roof_contact"] = _roof_first_contact
	metrics[label]["last_roof_contact"] = _roof_last_contact
	metrics[label]["left_roof_into_air"] = _roof_left
	metrics[label]["return_floor"] = _return_floor
	metrics[label]["return_body"] = _return_body
	metrics[label]["return_speed"] = _return_speed
	metrics[label]["roof_wall_contacts"] = _roof_wall_contacts
	metrics[label]["maximum_roof_surface_error"] = _surface_error

func validate_manifest_roof() -> void:
	var label := str(_roof.id)
	var exported := true
	for name in _roof.collider_names:
		var node = course.get_node_or_null("%s/%s" % [_roof.collider_parent,name])
		exported = exported and node != null and node.get_node_or_null("collision_body") is StaticBody3D
	check(exported,label+" uses exported static Cyclops building collision")
	# Nine rays sample both sloping faces and the ridge, away from ornamental
	# chimney silhouettes. The roof height comes from the visual gable schema.
	var matching := true
	var largest_error := 0.0
	for x in [-.3,0.0,.3]:
		for z in [-.3,0.0,.3]:
			var surface := roof_center()+Vector3(float(_roof.size[0])*x,0,float(_roof.size[1])*z)
			var query := PhysicsRayQueryParameters3D.create(Vector3(surface.x,float(_roof.roof_top)+8,surface.z),Vector3(surface.x,roof_center().y-1,surface.z),1,[player.get_rid()])
			var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or not is_roof_body(hit.collider):
				matching = false
			else:
				largest_error = maxf(largest_error,absf(hit.position.y-roof_height(surface)))
				matching = matching and hit.normal.y>.7 and largest_error<.025
	check(matching,label+" collision agrees with both visible gable planes and ridge")
	metrics[label+"_static"] = {"rays":9,"maximum_plane_error":largest_error,"collider_parent":_roof.collider_parent,"collider_names":_roof.collider_names}

func incoming_land_and_leave() -> void:
	var center := roof_center()
	var side := 1.0 if point(_roof.rejoin).x<center.x else -1.0
	# A lateral 24 m/s approach crosses the gable toward its route-facing eave.
	# Descending relative to the uphill face gives a real swept first landing.
	var entry := center+Vector3(-side*float(_roof.size[0])*.30,0,0)
	entry.y = roof_height(entry)+1.3
	begin_probe(entry,Vector3(side*24.0,-4.0,0))
	var label := str(_roof.id)+" lateral landing"
	for _i in roundi(1.8*fps):
		await tick(1,center+Vector3(side*50.0,0,0))
		if _roof_left and absf(player.global_position.x-center.x)>float(_roof.size[0])*.5+.6:
			break
	check(not _roof_first_contact.is_empty() and str(_roof_first_contact.get("body","")).contains("Gable/collision_body") and player._body_collision.shape==player._full_capsule and not player._capsule_reduced,label+" lands on the known building gable with the full capsule")
	var carry := false
	if not _roof_first_contact.is_empty():
		var normal := point(_roof_first_contact.normal)
		var incoming := point(_roof_first_contact.incoming).slide(normal)
		var outgoing := point(_roof_first_contact.velocity)
		carry = outgoing.dot(incoming.normalized())>=incoming.length()*.94
	check(carry,label+" preserves incoming collision-projected forward momentum")
	check(_roof_floor_frames>=2 and _roof_wall_contacts==0 and _surface_error<.09,label+" crosses supporting roof collision without hidden walls or bumps")
	check(_roof_left and absf(player.global_position.x-center.x)>float(_roof.size[0])*.5+.6,label+" naturally leaves the visible roof edge into air")
	summary(str(_roof.id)+"_land_walkoff")

func return_to_route() -> void:
	var center := roof_center()
	var side := 1.0 if point(_roof.rejoin).x<center.x else -1.0
	# The Underway sign fixture is behind the usual forward-running direction.
	# Approach that roof along its ridge toward the sign, so its first closest
	# pass is useful rather than consuming a hold while incoming motion recedes.
	var ridge_direction := 1.0 if int(_roof.sector_index)==4 else -1.0
	var entry := center+Vector3(side*2.0,0,-ridge_direction*float(_roof.size[1])*.30)
	entry.y = roof_height(entry)+1.7
	begin_probe(entry,Vector3(0,-2.0,ridge_direction*14.0))
	var label := str(_roof.id)+" return"
	for _i in fps:
		await tick(1)
		if _roof_floor_frames>=3:
			break
	check(not _roof_first_contact.is_empty(),label+" begins with a real airborne roof landing")
	var target = course.get_node_or_null(_roof.nearby_return_anchor)
	check(target is Node3D,label+" has an existing architectural return fixture")
	if target is Node3D:
		start_pull(target,label)
		await tick(roundi(.35*fps))
		end_pull(label)
	# Continue along the manifested route using ordinary look-ahead input.
	# Steering to stop at a single airborne point brakes the carried speed.
	# The final side roof returns toward the earlier flat finish approach because
	# its forward end is only twenty meters from the end of city collision.
	for _i in roundi(4.0*fps):
		if int(_roof.sector_index)==2:
			await tick(1,point(_roof.rejoin))
		elif int(_roof.sector_index)==6:
			# Land before climbing the steeper next spire roof.
			await tick(1,route_point(6,1))
		elif int(_roof.sector_index)==7:
			await tick(1,route_point(7,5))
		else:
			await chase_safe(int(_roof.sector_index),1,20.0)
		if _return_floor:
			break
	check(_roof_left and _return_floor and _return_speed>6.0,label+" pulls from the side roof onto actual main or lower-route collision with useful speed")
	summary(str(_roof.id)+"_route_return")

func jump_key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.device = 0
	event.physical_keycode = KEY_SPACE
	event.keycode = KEY_SPACE
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func route_launch_detour() -> void:
	var entry := point(_roof.entry)
	var direction := roof_center()-entry
	direction.y = 0.0
	direction = direction.normalized()
	begin_probe(entry,direction*18.0)
	# One initial authored route approach seed, followed by actual grounded
	# Space dispatch. No pose or velocity replacement occurs during the detour.
	for _i in roundi(.2*fps):
		await tick(1)
		if player.is_on_floor():
			break
	check(player.is_on_floor(),str(_roof.id)+" route launch starts on real main-roof support")
	jump_key(true)
	check(player.velocity.y>=player.JUMP_SPEED,str(_roof.id)+" actual Space input launches the route approach")
	jump_key(false)
	for _i in roundi(2.0*fps):
		await tick(1)
		if not _roof_first_contact.is_empty():
			break
	check(not _roof_first_contact.is_empty(),str(_roof.id)+" normal jump reaches actual neighboring gable collision")
	var target = course.get_node_or_null(_roof.nearby_return_anchor)
	if target is Node3D and not _roof_first_contact.is_empty():
		start_pull(target,str(_roof.id)+" continuous detour")
		await tick(roundi(.45*fps))
		end_pull(str(_roof.id)+" continuous detour")
		for _i in roundi(4.0*fps):
			steer(point(_roof.rejoin))
			await tick(1)
			if _return_floor:
				break
	check(_return_floor and _return_speed>6.0,str(_roof.id)+" continuous jump/held-pull detour rejoins real route collision")
	summary(str(_roof.id)+"_continuous_launch_detour")

func run() -> void:
	save_path = "user://adjacent_city_roofs_%d.cfg" % OS.get_process_id()
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
	check(player.surf_mode and player.use_momentum_pull and not player.vertical_look_enabled,"Roof probes use the actual main-city movement profile and level camera")
	var roofs: Array = manifest.get("playable_adjacent_roofs",[])
	var covered: Array[int] = []
	for roof in roofs:
		covered.append(int(roof.sector_index))
	check(roofs.size()>=7 and covered.has(1) and covered.has(2) and covered.has(3) and covered.has(4) and covered.has(5) and covered.has(6) and covered.has(7),"Manifest supplies selected physical neighboring roofs in all seven sectors")
	for roof in roofs:
		_roof = roof
		validate_manifest_roof()
		await incoming_land_and_leave()
		await return_to_route()
	if not roofs.is_empty():
		_roof = roofs[0]
		await route_launch_detour()
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
	print("ADJACENT_CITY_ROOFS_RESULT ",JSON.stringify({"physics_fps":fps,"checks":checks,"failures":failures,"metrics":metrics}))
	quit(0 if failures.is_empty() else 1)
