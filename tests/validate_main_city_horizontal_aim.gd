extends SceneTree
## Independent stationary entry samples on actual safe-roof collision. Only yaw
## is aimed; pitch stays exactly zero. Each selection uses production frustum,
## range, angular assistance, entry-motion scoring and LOS. No recording or PB
## is saved. This is acquisition evidence, not a continuous run or device test.
## Godot --headless --path . --script tests/validate_main_city_horizontal_aim.gd
const Cleanup = preload("res://tests/audio_test_cleanup.gd")
var course
var player
var manifest: Dictionary
var result: Dictionary={}
var checks := 0
var failures: Array[String] = []
var saved_files := {}
var save_path := "user://city_horizontal_aim_%d.cfg" % OS.get_process_id()

func check(value: bool, message: String) -> void:
	checks += 1
	print("CITY_HORIZONTAL_CHECK ","PASS " if value else "FAIL ",message)
	if not value:
		failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func vec(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])

func pose_probe(position: Vector3, target: Node3D, motion := Vector3.ZERO) -> Dictionary:
	player.global_position=position
	player.velocity=motion
	player.vertical_look_enabled=false
	player.camera.rotation=Vector3.ZERO
	var offset: Vector3=target.global_position-player.to_global(player._camera_base_pos)
	player.rotation.y=atan2(-offset.x,-offset.z)
	player.grapple.aim_assist_target=null
	player._recent_anchor=null
	player._anchor_cooldown=0.0
	var lock=player.grapple._find_lock_target(player.camera.global_position)
	return {"position":str(position),"distance":offset.length(),"vertical_angle":rad_to_deg(atan2(offset.y,Vector2(offset.x,offset.z).length())),"selected":str(lock.name) if lock else "none","success":lock==target}

func run() -> void:
	for path in ["user://parkour_bests.cfg","user://parkour_settings.cfg"]:
		saved_files[path]=FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/main_city/route_manifest.json"))
	course=load("res://levels/parkour/MainCityRun.tscn").instantiate()
	course.clock.save_path=save_path
	root.add_child(course)
	current_scene=course
	player=course.player
	course.set_physics_process(false)
	player.set_physics_process(false)
	player.set_process(false)
	player.grapple.set_process(false)
	root.get_node("SoundManager").music_player.stop()
	await physics_frame
	await physics_frame
	check(not player.vertical_look_enabled,"Actual main-city profile locks manual pitch horizontally")
	var success:=0
	var total:=0
	for sector_index in range(manifest.sectors.size()):
		var sector: Dictionary=manifest.sectors[sector_index]
		for spec in sector.anchors:
			var target: Node3D=course.get_node("CitySections/Sector%02d/ArchitecturalAnchors/%s" % [sector_index+1,spec.name])
			var samples: Array[Dictionary]=[]
			for i in range(sector.safe_points.size()-1):
				var a:=vec(sector.safe_points[i]); var b:=vec(sector.safe_points[i+1])
				var count:=ceili(a.distance_to(b)/2.0)
				for k in range(count):
					var floor_point:=a.lerp(b,(float(k)+.5)/count)
					if floor_point.distance_to(target.global_position)>34:
						continue
					var forward:=Vector3(b.x-a.x,0,b.z-a.z)
					var to_fixture:=Vector3(target.global_position.x-floor_point.x,0,target.global_position.z-floor_point.z)
					# Require a useful forward entry: looking back after passing
					# the fixture cannot establish availability for racing flow.
					if to_fixture.dot(forward)<0.0:
						continue
					var hit=player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(floor_point+Vector3.UP*5,floor_point-Vector3.UP*5,1,[player.get_rid()]))
					if hit.is_empty():
						continue
					var probe:=pose_probe(hit.position+Vector3.UP*.55,target,(b-a).normalized()*12)
					samples.append(probe)
			var accepted:=samples.filter(func(p): return p.success)
			var min_distance:=INF
			var min_angle:=INF
			var max_distance:=0.0
			var max_angle:=0.0
			for probe in accepted:
				min_distance=minf(min_distance,probe.distance)
				max_distance=maxf(max_distance,probe.distance)
				min_angle=minf(min_angle,absf(probe.vertical_angle))
				max_angle=maxf(max_angle,absf(probe.vertical_angle))
			result[spec.name]={"samples":samples.size(),"accepted_samples":accepted.size(),"min_distance":min_distance,"max_distance":max_distance,"min_angle":min_angle,"max_angle":max_angle}
			if not accepted.is_empty():
				success+=1
			else:
				print("YAW_UNAVAILABLE ",spec.name," ",JSON.stringify(samples))
			check(not accepted.is_empty(),spec.name+" selects through actual safe-floor approach with zero pitch")
			total+=1
	for spec in [{"sector":1,"name":"EaveRing00","pose":Vector3(0,24.55,12),"motion":Vector3(0,0,-12)}, {"sector":5,"name":"OuterBellRing","pose":Vector3(24,16.55,-1118),"motion":Vector3(0,0,-24)}, {"sector":6,"name":"SpireBrace04","pose":Vector3(155,28.55,-1150),"motion":Vector3(4,0,-14)}]:
		var target: Node3D=course.get_node("CitySections/Sector%02d/ArchitecturalAnchors/%s" % [spec.sector,spec.name])
		var critical:=pose_probe(spec.pose,target,spec.motion)
		print("YAW_CRITICAL_SEED ",spec.name," ",JSON.stringify(critical))
		check(critical.success,spec.name+" original flow entry still acquires with level camera")
	check(is_zero_approx(player.camera.rotation.x),"Manual and queried camera pitch remain zero")
	print("YAW_PROFILE total=",total," available=",success," FOV=",player._base_fov," camera_keep_aspect=",player.camera.keep_aspect," viewport=",player.camera.get_viewport().get_visible_rect().size," pitch=",player.camera.rotation.x)
	print("YAW_ANCHOR_WINDOWS ",JSON.stringify(result))
	for path in saved_files:
		var after=FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		check(after==saved_files[path],path.get_file()+" remains byte identical")
	DirAccess.make_dir_recursive_absolute("res://build")
	var output:=FileAccess.open("res://build/main_city_horizontal_aim.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"anchor_count":total,"acquirable_anchors":success,"base_fov":player._base_fov,"manual_pitch":0.0,"anchors":result},"\t"))
	output.close()
	Cleanup.stop_voices(self)
	root.get_node("GameManager").player=null
	course.queue_free()
	await process_frame
	await process_frame
	Cleanup.drain_mixer()
	DirAccess.remove_absolute(save_path)
	print("MAIN_CITY_HORIZONTAL_AIM_RESULT checks=",checks," failures=",failures.size()," anchors=",success,"/",total)
	quit(0 if failures.is_empty() else 1)
