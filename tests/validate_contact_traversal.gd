extends "res://tests/validate_main_city_flow.gd"
## Isolated live-capsule contact/force checks plus production Pull feedback.
## Every body probe seeds once at entry. Formula checks call the public force
## method with explicit vectors while the capsule has real supporting contact.
const Contact = preload("res://scenes/parkour/contact_traversal.tscn")
const Settings = preload("res://scenes/parkour/presentation_settings.gd")
var boost
var pressure
var test_anchor
var initial_effects := 1.0

func check(value: bool, message: String) -> void:
	checks += 1
	print("CONTACT_CHECK ","PASS " if value else "FAIL ",message)
	if not value:
		failures.append(message)

func contact_area(mode: int, position: Vector3, size: Vector3, shape_position: Vector3) -> Area3D:
	var area = Contact.instantiate()
	area.mode = mode
	area.position = position
	area.get_node("CollisionShape3D").shape = area.get_node("CollisionShape3D").shape.duplicate()
	area.get_node("CollisionShape3D").shape.size = size
	area.get_node("CollisionShape3D").position = shape_position
	area.lift_acceleration = 32.0
	area.maximum_upward_speed = 12.0
	root.add_child(area)
	return area

func ground() -> void:
	var body := StaticBody3D.new()
	body.name = "ContactProbeFloor"
	body.position = Vector3(1000,19.5,0)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200,1,200)
	collision.shape = box
	body.add_child(collision)
	root.add_child(body)

func boost_checks() -> void:
	begin_probe(Vector3(1000,20.55,10),Vector3(0,0,-12))
	await tick(roundi(.2*fps))
	check(player.is_on_floor() and boost.has_live_contact(player),"Boost requires actual full-capsule floor contact")
	var incoming := Vector3(3,2,-12)
	var changed: Vector3 = boost.step_velocity(player,incoming,.1)
	check(changed.distance_to(Vector3(3,2,-14))<.001,"Boost adds heading acceleration while retaining vertical and perpendicular motion")
	check(boost.step_velocity(player,Vector3(0,0,12),.1)==Vector3(0,0,12),"Opposed floor travel cannot activate the boost")
	check(boost.step_velocity(player,Vector3(0,0,-28),.1)==Vector3(0,0,-28),"Boost does not replace faster incoming forward momentum")
	var bounded: Vector3 = boost.step_velocity(player,Vector3(25,12,-15),.5)
	check(bounded.length()<=32.001 and bounded.x==25 and bounded.y==12,"Boost budgets its added heading speed without consuming retained components")
	await tick(roundi(.6*fps),Vector3(1000,20,-80))
	check(player.is_on_floor() and -player.velocity.z>23.0 and player.velocity.length()<=32.01,"Real sustained grounded traversal accelerates toward the authored speed")
	await tick(roundi(1.0*fps),Vector3(1000,20,-80))
	check(not boost.has_live_contact(player) and player._contact_traversal_areas.is_empty(),"Walking out stops the boost and removes contact registration")
	begin_probe(Vector3(1000,24.5,10),Vector3(0,0,-12))
	await tick(roundi(.15*fps))
	check(not player.is_on_floor() and boost.step_velocity(player,incoming,.1)==incoming,"Airborne overlap with the floor panel adds no force")
	check(not player.grapple.can_hook_target(boost) and boost.collision_layer==0 and boost.collision_mask==4 and not boost.is_in_group("grapple_anchors"),"Contact boost is physically sensed and cannot be remotely targeted")

func pressure_checks() -> void:
	boost.queue_free()
	await frames(2)
	pressure = contact_area(1,Vector3(1000,20,0),Vector3(40,20,50),Vector3(0,10,0))
	begin_probe(Vector3(1000,20.55,10),Vector3(12,0,-4))
	await tick(roundi(.1*fps))
	check(pressure.has_live_contact(player),"Updraft senses actual physical capsule overlap")
	var incoming := Vector3(12,-4,-9)
	var changed: Vector3 = pressure.step_velocity(player,incoming,.1)
	check(changed.distance_to(Vector3(12,-.8,-9))<.001,"Updraft adds vertical acceleration and preserves both horizontal components")
	var capped: Vector3 = pressure.step_velocity(player,Vector3(31,0,0),1.0)
	check(capped.x==31 and capped.z==0 and capped.length()<=32.001,"Updraft caps available vertical speed while preserving fast horizontal momentum")
	await tick(roundi(.6*fps))
	check(player.global_position.y>24.0 and player.velocity.y>8.0 and player.velocity.y<=12.01,"Actual updraft lifts a moving body with bounded upward speed")
	check(absf(player.velocity.x-12.0*exp(-.03*.7))<.08 and absf(player.velocity.z+4.0*exp(-.03*.7))<.08,"Updraft flight retains ordinary no-input horizontal carry")
	await tick(roundi(2.0*fps),Vector3(1070,20,0))
	check(not pressure.has_live_contact(player),"Ordinary steering leaves the physical pressure volume")
	var count: int = pressure.contact_steps
	var previous_y: float = player.velocity.y
	await tick(roundi(.2*fps))
	check(pressure.contact_steps==count and player.velocity.y<previous_y-.5,"Leaving the updraft removes lift immediately and restores the gravity arc")
	await tick(roundi(4.0*fps))
	check(player.is_on_floor(),"Released environmental flight lands through the actual capsule floor collision")

func pressure_hiss_checks() -> void:
	var sound = root.get_node("SoundManager")
	Settings.effects_strength = 1.0
	begin_probe(Vector3(1000,21,0),Vector3.ZERO)
	player.set_physics_process(false)
	await frames(2)
	var entries_before: int = pressure.entry_cues
	var incoming := Vector3(12,0,-4)
	pressure.step_velocity(player,Vector3(12,12,-4),.1)
	check(pressure.entry_cues==entries_before and get_nodes_in_group("pressure_hiss").is_empty(),"A capped updraft adds no force and cannot invent an entry hiss")
	var changed: Vector3 = pressure.step_velocity(player,incoming,.1)
	var voices := get_nodes_in_group("pressure_hiss")
	check(changed.y>incoming.y and pressure.entry_cues==entries_before+1 and voices.size()==1,"The first actual lift creates exactly one pressure entry cue")
	var voice: AudioStreamPlayer = voices[0]
	check(voice.get_parent()==sound and voice.stream.loop_mode==AudioStreamWAV.LOOP_DISABLED and voice.pitch_scale<1.0 and voice.volume_db<=-24.0,"Pressure hiss is quiet, low-pitched, non-looping and owned by SoundManager")
	for _index in range(12):
		pressure.step_velocity(player,incoming,.1)
	check(pressure.entry_cues==entries_before+1 and get_nodes_in_group("pressure_hiss").size()==1,"Sustained lift never spams an entry sound per frame")
	paused = true
	await process_frame
	await process_frame
	check(voice.stream_paused and not voice.can_process() and sound.play_pressure_hiss()==null,"Pause freezes the entry voice and rejects new pressure audio")
	paused = false
	await frames(roundi(.4*fps))
	check(get_nodes_in_group("pressure_hiss").is_empty(),"The short pressure cue stops and frees its playback node")
	pressure.reset_contact_state(player)
	pressure.step_velocity(player,incoming,.1)
	check(pressure.entry_cues==entries_before+2 and get_nodes_in_group("pressure_hiss").size()==1,"Recovery reset rearms one cue when physical lift next acts")
	player.set_physics_process(true)
	await tick(roundi(2.4*fps),Vector3(1070,20,0))
	check(not pressure.has_live_contact(player) and not pressure._pressure_cue_entries.has(player.get_instance_id()) and get_nodes_in_group("pressure_hiss").is_empty(),"Ordinary physical exit rearms the cue and leaves no lingering voice")
	Settings.effects_strength = 0.0
	begin_probe(Vector3(1000,21,0),Vector3.ZERO)
	entries_before = pressure.entry_cues
	await tick(maxi(3,roundi(.1*fps)))
	check(pressure.entry_cues==entries_before+1 and player.velocity.y>0.0 and get_nodes_in_group("pressure_hiss").is_empty(),"Zero effects suppresses pressure audio while actual physical lift remains active")
	Settings.effects_strength = 1.0
	pressure.step_velocity(player,incoming,.1)
	check(pressure.entry_cues==entries_before+1 and get_nodes_in_group("pressure_hiss").is_empty() and not sound.music_player.playing,"Strength changes inside the same entry cannot replay a muted hiss or start music")
	Settings.effects_strength = initial_effects

func lifecycle_feedback_checks() -> void:
	var spring = load("res://scenes/parkour/spring_pad.tscn").instantiate()
	spring.architectural_launcher = true
	spring.launch_direction = Vector3(1,.86,.4)
	spring.position = Vector3(1000,20,80)
	root.add_child(spring)
	var inlay: Node3D = spring.get_node("ArchitectureDirection")
	var heading := Vector3(1,0,.4).normalized()
	check((-inlay.global_basis.z).distance_to(heading)<.001 and not spring.get_node("Arrow").visible and not spring.get_node("Heading").visible and not spring.get_node("Sign").visible,"Architectural spring shows its actual horizontal direction through a deck inlay")
	var restrained := inlay.get_child_count()==4 and inlay.find_children("*","CollisionObject3D",true,false).is_empty()
	for mark in inlay.get_children():
		restrained = restrained and not mark.mesh.material.emission_enabled and mark.position.length()+mark.mesh.size.length()*.5<1.5
	check(restrained and not player.grapple.can_hook_target(spring),"Spring direction cue stays within the deck and adds no collision, emission or remote target")
	begin_probe(Vector3(1000,21,0),Vector3.ZERO)
	await tick(2)
	var incoming := Vector3(12,0,-4)
	player.set_physics_process(false)
	paused = true
	var clock_before: float = pressure.cue_clock
	var steam_before: float = pressure.get_node("Steam").lifetime
	check(pressure.step_velocity(player,incoming,.1)==incoming,"Pause blocks direct environmental force requests")
	await process_frame
	await process_frame
	check(pressure.cue_clock==clock_before and not pressure.get_node("Steam").can_process() and pressure.get_node("Steam").lifetime==steam_before,"Pause freezes the pressure cue clock and particle processing")
	paused = false
	player.gameplay_active = false
	check(pressure.step_velocity(player,incoming,.1)==incoming,"Inactive finish state cannot receive environmental force")
	player.gameplay_active = true
	var debug = root.get_node("DebugFlyCamera")
	debug.toggle()
	check(pressure.step_velocity(player,incoming,.1)==incoming,"Debug fly mode cannot receive environmental force")
	debug.toggle()
	player.register_contact_traversal(pressure)
	player.reset_movement_input()
	check(player._contact_traversal_areas.is_empty() and not pressure._occupants.has(player.get_instance_id()),"Recovery reset clears environmental registrations and occupants")
	var steps_before_reset: int = pressure.contact_steps
	begin_probe(Vector3(1080,20.55,0),Vector3(0,0,-8))
	await tick(2)
	check(not pressure.has_live_contact(player) and player._contact_traversal_areas.is_empty() and pressure.contact_steps==steps_before_reset,"A reset outside the old volume cannot replay stored pressure force")
	begin_probe(Vector3(1000,21,0),Vector3.ZERO)
	await tick(2)
	steps_before_reset = pressure.contact_steps
	var radius: float = player._full_capsule.radius
	begin_probe(Vector3(1020+radius*.8,21,25+radius*.8),Vector3(8,0,8))
	await tick(2)
	check(not pressure.has_live_contact(player) and pressure.contact_steps==steps_before_reset,"A reset just outside a rounded capsule corner cannot replay a stale broadphase hit")
	begin_probe(Vector3(1000,21,0),Vector3.ZERO)
	await tick(2)
	player.set_physics_process(false)
	test_anchor = load("res://scenes/parkour/grapple_anchor.tscn").instantiate()
	test_anchor.architectural_fixture = true
	test_anchor.position = Vector3(1000,28,-20)
	root.add_child(test_anchor)
	await frames(2)
	aim(test_anchor)
	check(player.grapple.get_lock_target()==test_anchor and not player.grapple.can_hook_target(pressure),"Production acquisition selects only a remote Pull fixture through the passive volume")
	player.grapple._refresh_anchor_feedback(test_anchor)
	check(test_anchor.feedback_state==2 and test_anchor._ring_material.albedo_color==test_anchor.targeted_color and test_anchor.targeted_color.b>test_anchor.targeted_color.r,"Selected architectural Pull feedback is restrained cyan")
	var indicator = player.hud._aim_assist_indicator
	indicator.acquired()
	indicator.step(0,false,true)
	var acquired_radius: float = indicator.circle_radius()
	indicator.step(.1,false,true)
	check(indicator.circle_radius()<acquired_radius and indicator.circle_radius()>=27,"Acquiring a Pull target gives a small circular inward contraction")
	mouse(true)
	player.hud._update_aim_assist_indicator()
	indicator.step(.15,true,true)
	check(player.is_hooking and player.hud._indicator_target==test_anchor and indicator.phase>0 and indicator.circle_radius()<30,"Held Pull tracks its actual fixture with inward circular feedback")
	var before: Vector3 = player.velocity
	mouse(false)
	check(not player.is_hooking and player.velocity==before,"Actual mouse-up preserves velocity after the environmental targeting check")
	# Let the physics server publish the flight-capsule shape change before a
	# separate direct force check against its actual overlap.
	await frames(2)
	Settings.effects_strength = 0.0
	indicator.step(.3,true,false)
	check(indicator.phase==0 and indicator.acquire_left==0,"Zero effects strength retains static cyan feedback without decorative motion")
	check(pressure.step_velocity(player,incoming,.1).y>incoming.y,"Zero presentation strength leaves physical updraft force active")
	Settings.effects_strength = initial_effects

func bell_bank_checks() -> void:
	# Independent entry seeds on the real exported banks. A floor snap can
	# maintain real support without adding a slide-collision record that tick;
	# verify the actual floor normal as well as a named body collision.
	for name in ["BellSlateBank3_T1","BellSlateBank4"]:
		var bank: Node3D = course.get_node("CitySections/Sector05/Architecture/"+name)
		var normal: Vector3 = bank.global_basis.y.normalized()
		var surface := bank.to_global(Vector3(0,.3,-8))
		var direction: Vector3 = bank.global_basis.z.normalized()
		if name=="BellSlateBank3_T1":
			# The tapered bank's actual 38-degree face is a triangle; its Node
			# transform is upright. Derive its entry from the authored vertices
			# and raycast the exported surface for the real supporting normal.
			var top: Array
			for solid in manifest.sectors[4].solids:
				if solid.name==name:
					top = solid.top
			var point := Vector3(top[0][0],top[0][1],top[0][2])*.65
			point += Vector3(top[1][0],top[1][1],top[1][2])*.175
			point += Vector3(top[2][0],top[2][1],top[2][2])*.175
			var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*10,point-Vector3.UP*10,1)
			var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(ray)
			normal = hit.normal
			surface = hit.position
			direction = Vector3(24,0,-7).normalized()
		var support: float = player._full_capsule.radius+(player._full_capsule.height*.5-player._full_capsule.radius)*normal.y
		var entry: Vector3 = surface+Vector3.UP*(support/normal.y-player._full_capsule_position.y+.035)
		var downhill := Vector3(normal.x,0,normal.z).normalized()
		var initial_downhill: float = (direction*25.0).dot(downhill)
		begin_probe(entry,direction*25.0)
		var supported_frames := 0
		var actual_bank_hit := false
		for _index in range(roundi(.6*fps)):
			await tick(1)
			if player.is_on_floor() and player.get_floor_normal().dot(normal)>.99:
				supported_frames += 1
			for index in player.get_slide_collision_count():
				var hit = player.get_slide_collision(index)
				if hit.get_collider().get_parent()==bank and hit.get_normal().dot(normal)>.99:
					actual_bank_hit = true
		check(actual_bank_hit and supported_frames>=roundi(.4*fps) and normal.y>.76 and normal.y<.81,name+" provides sustained actual capsule support on its 38-degree bank")
		check(player.velocity.dot(downhill)>initial_downhill+1.0 and player.velocity.dot(direction)>18.0,name+" gravity redirects the collision tangent downhill while retaining forward carry")
		check(_peak<=32.02 and _max_step<=32.0/fps+.04 and _wall_frames==0,name+" stays capped and continuous without a wall snag")
		metrics[name] = {"entry_seeded":true,"seconds":.6,"supported_frames":supported_frames,"support_seconds":float(supported_frames)/fps,"normal":vector(normal),
			"position":vector(player.global_position),"velocity":vector(player.velocity),"peak_speed":_peak,"horizontal_carry":Vector2(player.velocity.x,player.velocity.z).length(),
			"forward_carry":player.velocity.dot(direction),"downhill_speed_gain":player.velocity.dot(downhill)-initial_downhill,"body_height_change":player.global_position.y-entry.y}
	print("BELL_BANK_CONTACT_METRICS ",JSON.stringify(metrics))

func run() -> void:
	save_path = "user://contact_traversal_%d.cfg" % OS.get_process_id()
	for path in ["user://parkour_bests.cfg","user://parkour_settings.cfg"]:
		saved_files[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	initial_effects = Settings.effects_strength
	manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/main_city/route_manifest.json"))
	course = load("res://levels/parkour/MainCityRun.tscn").instantiate()
	course.clock.save_path = save_path
	root.add_child(course)
	current_scene = course
	player = course.player
	course.set_physics_process(false)
	player.set_process(false)
	root.get_node("SoundManager").music_player.stop()
	ground()
	boost = contact_area(0,Vector3(1000,20,0),Vector3(8,5,30),Vector3(0,2.5,0))
	await frames(3)
	await boost_checks()
	await pressure_checks()
	await pressure_hiss_checks()
	await lifecycle_feedback_checks()
	await bell_bank_checks()
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
	print("CONTACT_TRAVERSAL_RESULT ",JSON.stringify({"physics_fps":fps,"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
