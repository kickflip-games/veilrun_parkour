extends SceneTree
## Adjacent-roof safety on the actual exported city. Resolves the 21 manifest
## colliders, checks six practice spawns and samples every route corridor with
## the full player capsule. START / skipped CP6 / FINISH entries test PB guards.
## Godot --headless --path . --script tests/validate_adjacent_roof_clearance.gd --fixed-fps 60
## PB storage is isolated; seeded trigger checks are not a continuous race run.
var manifest:Dictionary
var course
var player
var checks:=0
var failures:Array[String]=[]
var roof_names:Dictionary={}
var samples:=0
var declared_solids:=0
var save_path:="user://adjacent_roof_safety_%d.cfg"%OS.get_process_id()
func _initialize():
	call_deferred("run")
func check(value:bool,label:String):
	checks+=1
	print("ROOF_SAFETY_CHECK ","PASS " if value else "FAIL ",label)
	if not value:
		failures.append(label)
func frames(count:int):
	for _i in range(count):
		await physics_frame
		await process_frame
func vec(value:Array)->Vector3:
	return Vector3(value[0],value[1],value[2])
func is_new_roof(body:Node)->bool:
	if not is_instance_valid(body):
		return false
	if roof_names.has(String(body.name)):
		return true
	var parent:=body.get_parent()
	return parent!=null and roof_names.has(String(parent.name))
func roof_hits(query:PhysicsShapeQueryParameters3D)->Array:
	var hits:Array=[]
	for hit in player.get_world_3d().direct_space_state.intersect_shape(query,64):
		if is_new_roof(hit.collider):
			hits.append(str(hit.collider.get_path()))
	return hits
func run():
	manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/main_city/route_manifest.json"))
	for roof in manifest.get("playable_adjacent_roofs",[]):
		for collider in roof.collider_names:
			roof_names[String(collider)]=true
			declared_solids+=1
	check(manifest.get("playable_adjacent_roofs",[]).size()==7 and declared_solids==21,"Seven roofs declare their three supporting solids")
	course=load("res://levels/parkour/MainCityRun.tscn").instantiate()
	course.clock.save_path=save_path
	root.add_child(course)
	current_scene=course
	player=course.player
	course.set_physics_process(false)
	player.set_physics_process(false)
	player.set_process(false)
	await frames(3)
	var matched:=0
	var active:=true
	for body in course.find_children("*","StaticBody3D",true,false):
		if is_new_roof(body):
			matched+=1
			active=active and (body.collision_layer & 1)!=0
	check(matched==21 and active,"Manifest names resolve to all21 active layer1 runtime colliders")
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=player._full_capsule
	query.collision_mask=1
	query.exclude=[player.get_rid()]
	for checkpoint in course._checkpoints:
		var marker:Marker3D=checkpoint.get_node("Respawn")
		query.transform=marker.global_transform
		query.transform.origin+=marker.global_basis*player._full_capsule_position
		var hits:=roof_hits(query)
		check(hits.is_empty(),checkpoint.name+" has no new roof overlap at its authored full-capsule respawn")
		if not hits.is_empty():
			print("ROOF_RESPAWN_HITS ",hits)
	for sector in manifest.sectors:
		for route in sector.routes:
			var hits:Array=[]
			for i in range(route.points.size()-1):
				var a:=vec(route.points[i]);var b:=vec(route.points[i+1])
				var horizontal:=Vector3(b.x-a.x,0,b.z-a.z)
				var side:=horizontal.normalized().cross(Vector3.UP)
				var normal_y:=horizontal.length()/a.distance_to(b)
				var grounded_height:float=player._full_capsule.height*.5-player._full_capsule.radius-player._full_capsule_position.y+player._full_capsule.radius/maxf(normal_y,.1)+.08
				var steps:=ceili(a.distance_to(b)/1.5)
				for k in range(steps):
					var p:=a.lerp(b,(float(k)+.5)/steps)
					for offset in [-float(route.width)*.4,0.0,float(route.width)*.4]:
						query.transform=Transform3D(Basis.IDENTITY,p+side*offset+Vector3.UP*grounded_height+player._full_capsule_position)
						var current:=roof_hits(query)
						if not current.is_empty():
							hits.append({"position":str(query.transform.origin),"hits":current})
						samples+=1
			check(hits.is_empty(),sector.slug+" "+route.kind+" "+route.name+" protects center and two broad shoulders from new solids")
			if not hits.is_empty():
				print("ROOF_CORRIDOR_HITS ",JSON.stringify(hits.slice(0,5)))
	# Exercise actual Area3D entries with body physics frozen: the purpose is
	# timer/order isolation, not evidence of an unassisted racing route.
	player.global_position=course.get_node("StartGate").global_position
	await frames(3)
	check(course.clock.state==1,"Actual START trigger still starts the shared course clock")
	course.clock.advance(1.0)
	player.global_position=course._checkpoints[5].global_position
	await frames(3)
	check(course.clock.checkpoint_splits.is_empty(),"Off-route entry into CP6 cannot bypass the preceding five sectors")
	player.global_position=course.get_node("FinishGate").global_position
	await frames(3)
	check(course.clock.state==1 and course.clock.personal_best==0.0,"Actual FINISH rejects an off-route attempt with missing ordered checkpoints")
	check(not FileAccess.file_exists(save_path),"Rejected shortcut never writes a total or sector PB")
	for child in root.get_node("SoundManager").get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream=null
	root.get_node("GameManager").player=null
	course.queue_free()
	current_scene=null
	await frames(3)
	DirAccess.remove_absolute(save_path)
	OS.delay_msec(150)
	print("ADJACENT_ROOF_SAFETY_RESULT ",JSON.stringify({"checks":checks,"capsule_samples":samples,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
