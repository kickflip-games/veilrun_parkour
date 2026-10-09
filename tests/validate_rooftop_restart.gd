extends SceneTree
## Actual physical keyboard events and authored scene reload, including paused R.
## Godot --headless --fixed-fps 60 --path . --script tests/validate_rooftop_restart.gd
## Omit --headless to additionally check actual rendered Compatibility frames.
## PBs stay isolated, and the presentation preference is never changed/saved.
const ROOF := "res://levels/parkour/rooftop_trial.tscn"
const CITY := "res://levels/parkour/rooftop_city_district.tscn"
class Errors extends Logger:
	var captured: Array[String]=[]
	func _log_error(function:String,file:String,line:int,code:String,rationale:String,_notify:bool,error_type:int,_traces:Array)->void:
		if error_type==ERROR_TYPE_SCRIPT:
			captured.append("%s (%s:%d %s)"%[rationale if not rationale.is_empty() else code,file,line,function])
var error_log := Errors.new()
var failures: Array[String]=[]
var checks := 0
var save_path := ""
var snapshots: Array[Dictionary]=[]
func _initialize()->void:
	OS.add_logger(error_log)
	save_path="user://rooftop_restart_validation_%d.cfg"%OS.get_process_id()
	node_added.connect(_isolate_rooftop)
	call_deferred("run")
func _isolate_rooftop(node:Node)->void:
	if node.scene_file_path==ROOF:
		node.clock.save_path=save_path
func check(value:bool,message:String)->void:
	checks+=1
	print("CHECK ","PASS " if value else "FAIL ",message)
	if not value:
		failures.append(message)
func frames(count:int)->void:
	for _i in range(count):
		await physics_frame
		await process_frame
func key(physical:int,logical:int,device:int,pressed:bool)->InputEventKey:
	var event:=InputEventKey.new()
	event.physical_keycode=physical
	event.keycode=logical
	event.device=device
	event.pressed=pressed
	return event
func fresh(label:String,previous_id:int)->void:
	await frames(16)
	var course=current_scene
	check(is_instance_valid(course) and course.scene_file_path==ROOF,label+" installs the authored rooftop scene")
	if not is_instance_valid(course):
		return
	check(course.get_instance_id()!=previous_id,label+" creates a fresh course instance")
	check(course.clock.state==0 and course.clock.elapsed==0.0 and course.clock.checkpoint_splits.is_empty() and course.clock.clean_run,label+" restores clean READY and empty checkpoints")
	check(course.recorder.samples.is_empty() and not course.recorder.active,label+" clears active recording")
	check(not paused and not course.restarting and not course.player.hud.is_paused and not course.player.hud.pause_screen.visible,label+" clears pause and restart flags")
	check(course.player.gameplay_active and course.player.hud.game_started,label+" enables fresh player gameplay")
	check(course.player.global_position.distance_to(Vector3(0,12.55,10))<.2,label+" returns player to spawn")
	check(absf(course.player.camera.rotation.x)<.00001 and not course.player.is_hooking and course.player._pull_solver.elapsed==0.0,label+" clears pitch and pull state")
	check(course.player.camera.current and root.get_camera_3d()==course.player.camera,label+" restores the current viewport camera")
	var district: Node = null
	for child in course.get_children():
		if child.scene_file_path == CITY:
			district = child
			break
	var boxes := 0
	for shape_node in course.find_children("*", "CollisionShape3D", true, false):
		if shape_node.shape is BoxShape3D and shape_node.get_parent() is StaticBody3D:
			boxes += 1
	var meshes := district.find_children("*", "MeshInstance3D", true, false).size() if district else 0
	check(district != null and meshes > 0, label + " reloads the batched architectural district")
	check(boxes >= 60, label + " retains the authored roof, chimney and recovery collision boxes")
	var snapshot:Dictionary={"label":label,"id":course.get_instance_id(),"paused":paused,"state":course.clock.state,"position":str(course.player.global_position),"camera_current":course.player.camera.current,"district_meshes":meshes,"collision_boxes":boxes}
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image()
		var luminance:=0.0
		var count:=0
		for y in range(0,image.get_height(),32):
			for x in range(0,image.get_width(),32):
				var color:=image.get_pixel(x,y)
				luminance+=(color.r+color.g+color.b)/3.0
				count+=1
		luminance/=maxi(count,1)
		snapshot["mean_rgb"]=luminance
		check(luminance>.01,label+" renders a nonblack GPU frame")
	snapshots.append(snapshot)
func real_space_jump()->void:
	var player=current_scene.player
	check(player.is_on_floor(),"Authored rooftop player settles on its actual collision roof")
	var space:=key(KEY_SPACE,KEY_SPACE,0,true)
	check(space.is_action_pressed("jump_or_dash"),"Physical Space from keyboard device0 matches jump")
	var before_y:float=player.global_position.y
	var before_jumps:int=player.parkour_juice.jump_count
	Input.parse_input_event(space)
	await frames(2)
	Input.parse_input_event(key(KEY_SPACE,KEY_SPACE,0,false))
	check(player.global_position.y>before_y+.04 and player.velocity.y>0.0 and player.parkour_juice.jump_count==before_jumps+1,"Physical Space produces one real upward jump from the authored roof")
func dirty_course()->void:
	current_scene.clock.start()
	current_scene.clock.advance(3.0)
	current_scene.clock.checkpoint(1)
	current_scene.clock.mark_practice()
	current_scene.recorder.start("rooftop_pull_v1",current_scene.player.global_transform)
	current_scene.player.camera.rotation.x=.6
	current_scene.player._pull_solver.elapsed=.5
func restart_key(label:String,from_pause:bool)->void:
	dirty_course()
	if from_pause:
		current_scene.player.hud.toggle_pause()
		check(paused and current_scene.player.hud.pause_screen.visible,label+" begins from the real pause overlay")
	var previous_id:int=current_scene.get_instance_id()
	Input.parse_input_event(key(KEY_R,KEY_R,0,true))
	await frames(2)
	Input.parse_input_event(key(KEY_R,KEY_R,0,false))
	await fresh(label,previous_id)
func run()->void:
	root.size=Vector2i(1280,720)
	print("RESTART_ENV ",Engine.get_version_info().string," display=",DisplayServer.get_name()," renderer=",ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	var physical:=key(KEY_R,KEY_R,0,true)
	var logical:=key(0,KEY_R,0,true)
	print("RESTART_KEY_MATCH physical0=",physical.is_action_pressed("trial_restart")," physical16=",key(KEY_R,KEY_R,16,true).is_action_pressed("trial_restart")," logical_only=",logical.is_action_pressed("trial_restart"))
	check(physical.is_action_pressed("trial_restart"),"Real physical R event from device0 matches the project action")
	var course=load(ROOF).instantiate()
	course.clock.save_path=save_path
	root.add_child(course)
	current_scene=course
	await fresh("initial",0)
	await real_space_jump()
	await restart_key("running_R",false)
	await restart_key("paused_R",true)
	await restart_key("repeat_R",false)
	var sound=root.get_node("SoundManager")
	for child in sound.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream=null
	root.get_node("GameManager").player=null
	current_scene.queue_free()
	current_scene=null
	await frames(3)
	DirAccess.remove_absolute(save_path)
	OS.remove_logger(error_log)
	for error in error_log.captured:
		failures.append("SCRIPT ERROR "+error)
	OS.delay_msec(200)
	print("ROOFTOP_RESTART_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"snapshots":snapshots}))
	quit(0 if failures.is_empty() else 1)
