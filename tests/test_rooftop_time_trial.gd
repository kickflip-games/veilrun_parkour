extends SceneTree
## Isolated medal, PB comparison and ghost-ready recording checks.
## Godot --headless --path . --script tests/test_rooftop_time_trial.gd

const Clock = preload("res://scenes/parkour/trial_clock.gd")
const Recorder = preload("res://scenes/parkour/run_recorder.gd")
class ScriptErrorLog extends Logger:
	var errors: Array[String] = []
	var mutex := Mutex.new()
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, error_type: int, _backtraces: Array) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		mutex.lock()
		errors.append("%s (%s:%d in %s)" % [rationale if not rationale.is_empty() else code, file, line, function])
		mutex.unlock()
	func drain() -> Array[String]:
		mutex.lock()
		var result: Array[String] = errors.duplicate()
		errors.clear()
		mutex.unlock()
		return result

var test_path := ""
var failures: Array[String] = []
var assertions := 0
var _test := ""
var error_log := ScriptErrorLog.new()

func _initialize() -> void:
	OS.add_logger(error_log)
	test_path = "user://rooftop_time_trial_validation_%d.cfg" % OS.get_process_id()
	call_deferred("run")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(_test + ": " + message)

func run() -> void:
	var names: Array[String] = []
	for method in get_method_list():
		if String(method.name).begins_with("test_"):
			names.append(String(method.name))
	names.sort()
	for name in names:
		_test = name
		DirAccess.remove_absolute(test_path)
		var before := failures.size()
		await call(name)
		for error in error_log.drain():
			failures.append(_test + ": SCRIPT ERROR " + error)
		DirAccess.remove_absolute(test_path)
		print("TEST ", "PASS " if failures.size() == before else "FAIL ", name)
	var sound := root.get_node_or_null("SoundManager")
	if sound:
		for child in sound.get_children():
			if child is AudioStreamPlayer:
				child.stop()
				child.stream = null
	await process_frame
	await process_frame
	OS.delay_msec(200)
	for error in error_log.drain():
		failures.append("SCRIPT ERROR " + error)
	OS.remove_logger(error_log)
	print("ROOFTOP_TIME_TRIAL_RESULT ", JSON.stringify({"tests":names.size(),"assertions":assertions,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _medal(seconds: float) -> String:
	return Clock.medal_for_time(seconds,75.0,60.0,45.0,35.0)

func _trial():
	# Load after autoload initialization; this fixture stays outside the tree.
	var trial = load("res://levels/parkour/parkour_trial.gd").new()
	trial.course_id = "rooftop_pull_v1"
	trial.medals_enabled = true
	trial.clock.course_id = trial.course_id
	trial.clock.save_path = test_path
	trial.clock.checkpoint_count = 4
	return trial

func _complete(clock, duration: float) -> void:
	clock.start()
	for index in range(4):
		clock.advance(duration/4.0)
		check(clock.checkpoint(index+1),"Checkpoint order is preserved")
	check(clock.finish()==OK,"Complete run finishes")

func _pose(x: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY,Vector3(x,2,3))

func test_medal_thresholds_are_inclusive_and_validated() -> void:
	for item in [[35.0,"DEVELOPER"],[35.01,"GOLD"],[45.0,"GOLD"],[45.01,"SILVER"],[60.0,"SILVER"],[60.01,"BRONZE"],[75.0,"BRONZE"],[75.01,""]]:
		check(_medal(item[0])==item[1],"Boundary medal at %.2f"%item[0])
	check(_medal(0.0).is_empty() and _medal(INF).is_empty(),"Invalid finished times have no medal")
	check(Clock.medal_for_time(40,75,60,30,35).is_empty(),"Inverted medal thresholds are rejected")
	check(Clock.medal_for_time(40,75,60,45,NAN).is_empty(),"Nonfinite medal thresholds are rejected")
	var trial=_trial()
	trial.clock.elapsed=44.0
	trial.medals_enabled=false
	check(trial.finish_result_for(0.0).medal.is_empty(),"Existing courses opt out of placeholder medals")
	trial.medals_enabled=true
	check(trial.finish_result_for(0.0).medal=="GOLD","Rooftop opts into its exported thresholds")
	trial.free()

func test_new_best_delta_uses_previous_personal_best() -> void:
	var seed=_trial()
	_complete(seed.clock,75.0)
	seed.free()
	var trial=_trial()
	trial.clock.load_best()
	var prior: float=trial.clock.personal_best
	_complete(trial.clock,44.0)
	var result: Dictionary=trial.finish_result_for(prior)
	check(result.prior_personal_best==75.0 and result.personal_best==44.0,"Finish records prior and new PB separately")
	check(result.delta_from_prior_best==-31.0,"Improved PB delta is computed against the previous record")
	check(result.has_prior_best and result.new_personal_best and result.best_saved,"Clean saved improvement is marked as a new PB")
	check(result.medal=="GOLD","Medal reflects the finished run")
	var reload=Clock.new()
	reload.course_id="rooftop_pull_v1"
	reload.save_path=test_path
	reload.checkpoint_count=4
	reload.load_best()
	check(reload.personal_best==44.0 and reload.best_splits==[11.0,22.0,33.0,44.0],"New PB and matching splits persist in the rooftop section")
	trial._save_failed=true
	check(not trial.finish_result_for(prior).best_saved,"A failed save cannot be presented as a saved PB")
	trial.free()

func test_practice_finish_keeps_pb_and_discards_recording() -> void:
	var trial=_trial()
	_complete(trial.clock,75.0)
	var bytes:=FileAccess.get_file_as_bytes(test_path)
	trial.clock=Clock.new()
	trial.clock.course_id=trial.course_id
	trial.clock.save_path=test_path
	trial.clock.checkpoint_count=4
	trial.clock.load_best()
	trial.clock.start()
	trial.clock.mark_practice()
	_complete(trial.clock,43.0)
	var result: Dictionary=trial.finish_result_for(75.0)
	check(not result.clean_run and not result.new_personal_best and not result.best_saved,"Practice is never a saved PB")
	check(result.personal_best==75.0 and result.delta_from_prior_best==-32.0,"Practice pace compares to the prior PB without replacing it")
	check(FileAccess.get_file_as_bytes(test_path)==bytes,"Practice finish leaves the PB file byte-identical")
	var recorder=Recorder.new()
	recorder.start(trial.course_id,_pose(0))
	check(recorder.capture(.1,_pose(1),true,false),"Clean recording begins")
	recorder.mark_practice()
	check(not recorder.capture(.2,_pose(2),true,false),"Checkpoint recovery stops recording")
	var recording: Dictionary=recorder.finish(false,true,true)
	check(recording.samples.is_empty() and not recording.personal_best_eligible,"Practice cannot produce a PB ghost recording")
	trial.free()

func test_recorder_cadence_gates_and_finite_data() -> void:
	var recorder=Recorder.new()
	check(not recorder.capture(.1,_pose(0),true,false),"READY has no recording")
	recorder.start("rooftop_pull_v1",_pose(0))
	check(recorder.samples.size()==1 and recorder.samples[0].time==0.0,"Run starts with its initial pose")
	check(not recorder.capture(.05,_pose(1),true,false),"10 Hz recorder skips intermediate frames")
	check(not recorder.capture(.1,_pose(1),true,true),"Paused frames are not sampled")
	check(not recorder.capture(.1,_pose(1),false,false),"Non-running clock states are not sampled")
	check(recorder.capture(.1,_pose(1),true,false),"Running unpaused frame samples at cadence")
	check(not recorder.capture(.1,_pose(2),true,false),"Duplicate timestamps are rejected")
	check(not recorder.capture(NAN,_pose(2),true,false),"Nonfinite time is rejected")
	check(not recorder.capture(.2,_pose(INF),true,false),"Nonfinite pose is rejected")
	check(recorder.capture(3.0,_pose(3),true,false),"A long frame records its actual current pose")
	check(recorder.samples.size()==3 and recorder.samples[-1].time==3.0,"Missed intervals do not fabricate historical poses")
	var recording: Dictionary=recorder.finish(true,true,true)
	check(recording.personal_best_eligible and recording.course_id=="rooftop_pull_v1","A complete saved clean PB is eligible for a future ghost")
	check(recording.samples[1].transform==_pose(1),"Recording retains transform values")
	check(not recorder.capture(3.1,_pose(4),true,false),"Finished recorder is inactive")
	recorder.reset()
	check(recording.samples.size()==3,"Consumer recording survives recorder reset")
	check(recorder.samples.is_empty() and not recorder.active and not recorder.practice,"Retry clears current recording state")

func test_recorder_capacity_rate_and_pb_eligibility() -> void:
	var recorder=Recorder.new()
	recorder.sample_rate=20.0
	recorder.max_samples=3
	recorder.start("rooftop_pull_v1",_pose(0))
	check(recorder.capture(.05,_pose(1),true,false),"20 Hz is configurable")
	check(recorder.capture(.1,_pose(2),true,false),"Third bounded sample is retained")
	check(not recorder.capture(.15,_pose(3),true,false) and recorder.truncated,"Overflow stops appending and marks truncation")
	var recording: Dictionary=recorder.finish(true,true,true)
	check(recording.samples.size()==3 and recording.sample_rate==20.0,"Recording reports its bounded rate and sample count")
	check(not recording.personal_best_eligible,"Truncated recording cannot become a PB ghost")
	recorder.max_samples=9000
	recorder.start("new_course",_pose(10))
	check(not recorder.truncated and recorder.samples.size()==1,"A new clean run clears overflow and prior samples")
	check(not recorder.finish(true,false,true).personal_best_eligible,"A slower clean run is not a PB ghost")
	recorder.start("new_course",_pose(10))
	check(not recorder.finish(true,true,false).personal_best_eligible,"An unsaved PB is not a persisted PB ghost")
	check(not FileAccess.file_exists(test_path),"Recorder never creates a disk file")

func _open_rooftop():
	var scene = load("res://levels/parkour/rooftop_trial.tscn").instantiate()
	# The real shared course UI and signals run against an isolated save.
	# Gate methods and physics delta are driven here; this is not a route test.
	scene.clock.save_path = test_path
	root.add_child(scene)
	current_scene = scene
	scene.set_physics_process(false)
	scene.player.set_physics_process(false)
	scene.player.set_process(false)
	return scene

func _close_rooftop(scene) -> void:
	paused = false
	current_scene = null
	root.get_node("GameManager").player = null
	scene.queue_free()
	await process_frame
	await process_frame

func test_shared_course_signals_pause_finish_and_recovery() -> void:
	var seed = Clock.new()
	seed.course_id = "rooftop_pull_v1"
	seed.save_path = test_path
	seed.checkpoint_count = 4
	_complete(seed,75.0)
	var scene = _open_rooftop()
	var starts: Array[String] = []
	var samples: Array[Dictionary] = []
	var finishes: Array[Dictionary] = []
	var pb_recordings: Array[Dictionary] = []
	scene.run_started.connect(func(id: String): starts.append(id))
	scene.run_sampled.connect(func(time: float, pose: Transform3D): samples.append({"time":time,"transform":pose}))
	scene.run_finished.connect(func(result: Dictionary): finishes.append(result))
	scene.personal_best_recorded.connect(func(recording: Dictionary): pb_recordings.append(recording))
	check(scene.clock.state == Clock.State.READY and scene.recorder.samples.is_empty(),"Authored rooftop starts with an empty READY recording")
	check(scene.clock.checkpoint_count == 4 and scene.medals_enabled,"Rooftop configures four checkpoints and medals")
	scene._physics_process(1.0)
	check(scene.clock.elapsed == 0.0 and samples.is_empty(),"READY physics does not accrue time or emit samples")
	scene._start_entered(scene.player)
	scene._start_entered(scene.player)
	check(starts == ["rooftop_pull_v1"] and samples.size() == 1,"Start emits one course event and one initial sample")
	scene._finish_entered(scene.player)
	check(scene.clock.state == Clock.State.RUNNING and finishes.is_empty(),"Missing checkpoints cannot emit a finished run")
	paused = true
	scene._physics_process(1.0)
	check(scene.clock.elapsed == 0.0 and samples.size() == 1,"Pause excludes clock time and transform samples")
	paused = false
	for index in range(4):
		scene._physics_process(11.0)
		scene._checkpoint_entered(scene.player,index+1)
	scene.clock.advance(.037)
	scene._finish_entered(scene.player)
	check(finishes.size() == 1 and pb_recordings.size() == 1,"Clean saved improvement emits finish and PB recording events")
	check(is_equal_approx(finishes[0].prior_personal_best,75.0) and is_equal_approx(finishes[0].delta_from_prior_best,-30.963),"Finish signal compares against the PB loaded before this run")
	check(finishes[0].new_personal_best and finishes[0].best_saved and finishes[0].medal == "GOLD","Finish signal reports saved PB and medal")
	check(samples.size() == 6 and is_equal_approx(samples[-1].time,44.037),"Finish forces its endpoint sample between regular cadence intervals")
	check(pb_recordings[0].personal_best_eligible and pb_recordings[0].samples.size() == 6,"PB recording includes the complete signal sample sequence")
	check(not scene.player.gameplay_active and scene._finish_panel.visible,"Finished course disables movement and shows the result panel")
	await _close_rooftop(scene)
	var saved_bytes := FileAccess.get_file_as_bytes(test_path)
	scene = _open_rooftop()
	finishes.clear()
	pb_recordings.clear()
	scene.run_finished.connect(func(result: Dictionary): finishes.append(result))
	scene.personal_best_recorded.connect(func(recording: Dictionary): pb_recordings.append(recording))
	scene._start_entered(scene.player)
	scene._physics_process(2.0)
	scene._checkpoint_entered(scene.player,1)
	scene.respawn_checkpoint()
	check(not scene.clock.clean_run and scene.clock.elapsed == 2.0 and scene.clock.checkpoint_splits.size() == 1,"Checkpoint recovery preserves timing and progress while marking practice")
	check(scene.recorder.practice and scene.recorder.samples.is_empty(),"Checkpoint recovery discards the active recording")
	for index in range(1,4):
		scene._physics_process(2.0)
		scene._checkpoint_entered(scene.player,index+1)
	scene._finish_entered(scene.player)
	check(finishes.size() == 1 and not finishes[0].clean_run and not finishes[0].best_saved,"Practice completes with an explicit unsaved result")
	check(finishes[0].recording.samples.is_empty() and pb_recordings.is_empty(),"Practice finish never emits a PB recording")
	check(FileAccess.get_file_as_bytes(test_path) == saved_bytes,"Integrated checkpoint practice leaves saved PB bytes unchanged")
	await _close_rooftop(scene)
