extends SceneTree
## Actual upright capsule checks and a whole ordinary-input safe run. The full
## run never teleports. Independent route/fixture probes are explicitly seeded.
var course
var player
var failures: Array[String] = []
var checks := 0
var travelled := 0.0
var save_path := "user://main_city_geometry_%d.cfg" % OS.get_process_id()
var manifest: Dictionary

func _initialize() -> void:
	call_deferred("run")

func vec(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])

func check(value: bool, label: String) -> void:
	checks += 1
	print("CITY_CHECK ","PASS " if value else "FAIL ",label)
	if not value:
		failures.append(label)

func frames(count: int) -> void:
	for _i in range(count):
		await physics_frame

func drive_to(point: Vector3, label: String, limit := 1800) -> bool:
	var reached := false
	for tick in range(limit):
		var offset: Vector3 = point - player.global_position
		offset.y = 0.0
		if offset.length() < 1.15 or course.clock.state == 2:
			reached = true
			break
		var desired := offset.normalized() * minf(8.0,offset.length()*2.0)
		var steering := desired-Vector3(player.velocity.x,0,player.velocity.z)
		if steering.length()>0.20:
			player.rotation.y=atan2(-steering.x,-steering.z)
			Input.action_press("move_forwards")
		else:
			Input.action_release("move_forwards")
		player.camera.rotation.x = 0.0
		var prior: Vector3 = player.global_position
		await physics_frame
		travelled += prior.distance_to(player.global_position)
	Input.action_release("move_forwards")
	check(reached,label+" pos="+str(player.global_position))
	return reached

func corridor_probes() -> void:
	var space=player.get_world_3d().direct_space_state
	var capsule=player._full_capsule
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=capsule
	query.collision_mask=1
	query.exclude=[player.get_rid()]
	var sampled:=0
	for sector in manifest.sectors:
		for route in sector.routes:
			var all_clear:=true
			var supported:=true
			for i in range(route.points.size()-1):
				var a:=vec(route.points[i]); var b:=vec(route.points[i+1])
				var steps:=ceili(a.distance_to(b)/3.0)
				for k in range(steps):
					var center:=a.lerp(b,(float(k)+.5)/steps)
					var side:=(b-a).normalized().cross(Vector3.UP)
					var offsets: Array[float]=[0.0]
					if route.kind=="safe" and sector.slug!="02_chimney_row":
						offsets=[-float(route.width)*.25,0.0,float(route.width)*.25]
					for offset in offsets:
						var p:=center+side*offset
						var ray:=PhysicsRayQueryParameters3D.create(p+Vector3.UP*5.0,p-Vector3.UP*5.0,1,[player.get_rid()])
						var floor_hit: Dictionary=space.intersect_ray(ray)
						if floor_hit.is_empty():
							supported=false
							print("CITY_FLOOR_MISSING ",route.name," ",p)
							continue
						# Use the actual floor and full collider local offset. Braid
						# joins share main roofs before branching to a lower layer.
						var floor_point: Vector3=floor_hit.position
						var floor_normal: Vector3=floor_hit.normal
						# A capsule rests higher on a sloped plane than on a flat
						# one because the lower hemisphere touches away from its tip.
						var grounded_origin_height: float=capsule.height*.5-capsule.radius-player._full_capsule_position.y+capsule.radius/maxf(floor_normal.y,.1)+.05
						query.transform=Transform3D(Basis.IDENTITY,floor_point+Vector3.UP*grounded_origin_height+player._full_capsule_position)
						if not space.intersect_shape(query,1).is_empty():
							var motion_query:=PhysicsTestMotionParameters3D.new()
							motion_query.from=query.transform
							motion_query.from.origin-=player._full_capsule_position
							motion_query.motion=Vector3.UP*.001
							motion_query.margin=.001
							motion_query.max_collisions=8
							motion_query.recovery_as_collision=true
							var motion_result:=PhysicsTestMotionResult3D.new()
							PhysicsServer3D.body_test_motion(player.get_rid(),motion_query,motion_result)
							var floor_only:=motion_result.get_collision_count()>0
							for hit_index in range(motion_result.get_collision_count()):
								var normal:=motion_result.get_collision_normal(hit_index)
								if normal.y<.70:
									floor_only=false
									print("CITY_OVERLAP_NORMAL ",route.name," ",p," normal=",normal)
							if not floor_only:
								all_clear=false
								print("CITY_CAPSULE_BLOCKED ",route.name," ",p," floor=",floor_point)
						sampled+=1
			check(all_clear,sector.title+" "+route.name+" full upright capsule has no wall/ceiling overlap")
			check(supported,sector.title+" "+route.name+" continuous supporting collision")
	print("CITY_CAPSULE_SAMPLES ",sampled)
	for checkpoint in course._checkpoints:
		var pose: Transform3D=checkpoint.get_node("Respawn").global_transform
		query.transform=pose
		query.transform.origin+=player._full_capsule_position
		check(space.intersect_shape(query,1).is_empty(),checkpoint.name+" practice spawn full capsule clear")

func anchor_probes() -> void:
	# Independent ordinary-range LOS test from nearby sampled roof, without any
	# claim that this is a continuous expert run or validated human timing.
	var total:=0
	var clear:=0
	var space=player.get_world_3d().direct_space_state
	for sector in manifest.sectors:
		for spec in sector.anchors:
			var target:=vec(spec.position)
			var best:=Vector3.ZERO
			var distance:=INF
			for route in sector.routes:
				if route.kind != "safe":
					continue
				for i in range(route.points.size()-1):
					var a:=vec(route.points[i]); var b:=vec(route.points[i+1])
					var t:=clampf((target-a).dot(b-a)/(b-a).length_squared(),0.0,1.0)
					var p:=a.lerp(b,t)+Vector3.UP*1.7
					if p.distance_to(target)<distance:
						distance=p.distance_to(target)
						best=p
			var ray:=PhysicsRayQueryParameters3D.create(best,target,1,[player.get_rid()])
			if distance<=course.grapple_range and space.intersect_ray(ray).is_empty():
				clear+=1
			else:
				print("CITY_ANCHOR_INACCESSIBLE ",spec.name," distance=",distance," hit=",space.intersect_ray(ray))
			total+=1
	check(clear==total,"All %d architectural fixtures have a range-valid unobstructed safe-roof approach" % total)

func safe_run() -> void:
	var started:=false
	for sector in manifest.sectors:
		for i in range(1,sector.safe_points.size()):
			if not await drive_to(vec(sector.safe_points[i]),sector.title+" waypoint%d" % i):
				return
			started=started or course.clock.state==1
	check(started,"Physical StartGate overlap starts timer")
	check(course.clock.state==2,"Whole safe run physically crosses finish")
	check(course.clock.checkpoint_splits.size()==6,"Whole safe run crosses six ordered checkpoints")
	check(course.clock.clean_run,"Whole safe run completes without recovery or teleports")
	print("CITY_SAFE_RUN ",JSON.stringify({"seconds":course.clock.elapsed,"travelled":travelled,"clean":course.clock.clean_run,"splits":course.clock.checkpoint_splits}))

func independent_braid_runs() -> void:
	# Every braid is a separate seeded entry, never part of the whole-run result.
	var space=player.get_world_3d().direct_space_state
	var walked:=0
	var traversal_lines:=0
	for sector in manifest.sectors:
		for route in sector.routes:
			if route.kind=="safe":
				continue
			if route.get("requires_traversal",false):
				# Capsule/support/LOS probes above still cover this corridor. Its
				# physical launcher and uninterrupted entry-to-exit motion belong
				# to the named racing-slice harness, rather than a walking claim.
				var traversal: Dictionary=route.get("traversal",{})
				var mechanism: String=traversal.get("mechanism","")
				var validation: String=traversal.get("validation","")
				var launcher=course.get_node_or_null("CitySections/Sector%s/%s" % [sector.slug.get_slice("_",0),mechanism])
				check(launcher is Area3D and launcher.has_method("launch_velocity") and ResourceLoader.exists("res://"+validation),route.name+" declares an actual spring and existing continuous traversal harness")
				traversal_lines+=1
				print("CITY_TRAVERSAL_LINE ",route.name," mechanism=",mechanism," validation=",validation," reason=",traversal.get("reason",""))
				continue
			var points: Array=route.points
			var start:=vec(points[0])
			var floor_hit: Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(start+Vector3.UP*5,start-Vector3.UP*5,1,[player.get_rid()]))
			if floor_hit.is_empty():
				check(false,route.name+" seeded entry has support")
				continue
			player._end_hook(false)
			course._reset_player_inputs()
			player.global_position=floor_hit.position+Vector3.UP*.65
			player.velocity=Vector3.ZERO
			player.gameplay_active=true
			player.hud.game_started=true
			player._body_collision.shape=player._full_capsule
			player._body_collision.position=player._full_capsule_position
			player._capsule_reduced=false
			course.clock.state=1
			course.clock.mark_practice()
			await frames(3)
			var reached:=true
			for i in range(1,points.size()):
				if not await drive_to(vec(points[i]),"Seeded "+route.name+" waypoint%d" % i):
					reached=false
					break
			check(reached,route.name+" physical no-warp traversal after independent entry seed")
			if reached:
				walked+=1
	check(walked==12 and traversal_lines==1,"Twelve walking braids complete and one declared spring line has separate continuous slice coverage")
	print("CITY_BRAID_COVERAGE walked=",walked," traversal_slice_lines=",traversal_lines)

func run() -> void:
	manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/main_city/route_manifest.json"))
	course=load("res://levels/parkour/MainCityRun.tscn").instantiate()
	course.clock.save_path=save_path
	root.add_child(course)
	current_scene=course
	player=course.player
	root.get_node("SoundManager").music_player.stop()
	await frames(3)
	Engine.physics_ticks_per_second=1200
	Engine.max_physics_steps_per_frame=64
	Engine.time_scale=20
	print("CITY_EFFECTIVE_PHYSICS_DELTA ",20.0/1200.0," simulated_seconds_per_tick")
	check(course._checkpoints.size()==6,"Six checkpoints bound to shared clock")
	check(course.get_meta("safe_route_length")>1700.0,"Measured safe route exceeds1700m")
	var markers_hidden:=true
	for anchor in get_nodes_in_group("grapple_anchors"):
		markers_hidden=markers_hidden and not anchor.get_node("HookSign").visible and not anchor.get_node("Diamond/Core").visible
	for pad in course.find_children("*","Area3D",true,false):
		if pad.has_method("launch_velocity"):
			markers_hidden=markers_hidden and pad.architectural_launcher and not pad.get_node("Arrow").visible and not pad.get_node("Heading").visible and not pad.get_node("Sign").visible
	check(markers_hidden,"Normal game hides all prototype anchor and launch markers")
	corridor_probes()
	anchor_probes()
	if not "--probes-only" in OS.get_cmdline_user_args():
		if "--braids-only" in OS.get_cmdline_user_args():
			await independent_braid_runs()
		else:
			await safe_run()
	Input.action_release("move_forwards")
	player.parkour_juice.wind_player.stop()
	player.parkour_juice.wind_player.stream=null
	root.get_node("GameManager").player=null
	course.queue_free()
	for audio in root.get_node("SoundManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop(); audio.stream=null
	await frames(3)
	await process_frame
	await process_frame
	await process_frame
	OS.delay_msec(150)
	DirAccess.remove_absolute(save_path)
	print("MAIN_CITY_GEOMETRY_RESULT checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
