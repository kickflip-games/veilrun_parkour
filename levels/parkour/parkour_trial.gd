extends Node3D

const Clock = preload("res://scenes/parkour/trial_clock.gd")
const Recorder = preload("res://scenes/parkour/run_recorder.gd")
const UI = preload("res://scenes/playtest/playtest_ui.gd")
signal run_started(course_id: String)
signal run_sampled(sample_time: float, pose: Transform3D)
signal run_finished(result: Dictionary)
signal personal_best_recorded(recording: Dictionary)
const SECTORS := ["OPENING · Choose your line", "VELOCITY DRIVE · Link the anchors", "S CLIMB · Follow the arrows", "SKY HAIRPIN · Wide turn or beam cut", "DOWNHILL · Carry your speed", "RHYTHM STRAIGHT · Chain the springs", "FINAL SPRINT · Finish ahead"]
@export var course_id := "switchback_long_v2"
@export var course_title := "SWITCHBACK · LONG CIRCUIT"
@export var sector_names := PackedStringArray(SECTORS)
@export var checkpoint_paths: Array[NodePath] = [NodePath("Checkpoint1"), NodePath("LongCourse/Checkpoint2"), NodePath("LongCourse/Checkpoint3"), NodePath("LongCourse/Checkpoint4"), NodePath("LongCourse/Checkpoint5"), NodePath("LongCourse/Checkpoint6")]
@export var finish_path := NodePath("LongCourse/FinishGate")
@export_multiline var course_intro := ""
@export var medals_enabled := false
@export var medal_bronze := 75.0
@export var medal_silver := 60.0
@export var medal_gold := 45.0
@export var medal_developer := 35.0
@export var fall_height := -12.0
@export var show_developer_speed := false
@export var sector_retry_enabled := false
@export var grapple_range := 26.0
@export_range(0.0, 30.0, 0.5) var acquisition_horizontal_degrees := 18.0
@export_range(0.0, 45.0, 0.5) var acquisition_vertical_degrees := 40.0
var clock = Clock.new()
var recorder = Recorder.new()
var last_finish_result: Dictionary = {}
var restarting := false
var _save_failed := false
var _time_label: Label
var _progress_label: Label
var _sector_label: Label
var _speed_label: Label
var _progress_bar: ColorRect
var _progress_fill: ColorRect
var _hint: Label
var _finish_panel: CenterContainer
var _checkpoints: Array[Area3D] = []
var _respawn: Marker3D
var _spawn_transform := Transform3D.IDENTITY
var _feedback_time := 0.0
var _feedback := ""
@onready var player = $Player

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.time_scale = 1.0
	get_tree().paused = false
	if DebugFlyCamera.is_active():
		DebugFlyCamera.toggle()
	# A longer layout needs its own PB and matching checkpoint splits.
	clock.course_id = course_id
	clock.checkpoint_count = checkpoint_paths.size()
	clock.load_best()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.parkour_mode = true
	player.camera.current = true
	player.grapple.hook_range = grapple_range
	player.grapple.lock_horizontal_degrees = acquisition_horizontal_degrees
	player.grapple.lock_vertical_degrees = acquisition_vertical_degrees
	_spawn_transform = player.global_transform
	var spawn := get_node_or_null("PlayerSpawn") as Marker3D
	if spawn:
		_spawn_transform = spawn.global_transform
	player.hud.parkour_ready()
	player.hud.speedlines.material.set_shader_parameter("line_density", 0.0)
	player.hud.speedlines.hide()
	SoundManager.music_player.stop()
	$StartGate.body_entered.connect(_start_entered)
	for path in checkpoint_paths:
		_checkpoints.append(get_node(path))
	for index in range(_checkpoints.size()):
		if _checkpoints[index].has_method("practice_transform") and int(_checkpoints[index].order_index) != index + 1:
			push_error("Checkpoint %s has order %d; expected %d" % [_checkpoints[index].name, _checkpoints[index].order_index, index + 1])
		_checkpoints[index].body_entered.connect(_checkpoint_entered.bind(index + 1))
	get_node(finish_path).body_entered.connect(_finish_entered)
	_build_ui()

func _build_ui() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 12
	add_child(overlay)
	_time_label = UI.label("", 28)
	_time_label.position = Vector2(24, 20)
	_time_label.size = Vector2(850, 44)
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_time_label)
	_progress_label = UI.label(course_title, 18)
	_progress_label.position = Vector2(24, 58)
	_progress_label.size = Vector2(850, 30)
	_progress_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_progress_label)
	_sector_label = UI.label("", 16)
	_sector_label.position = Vector2(24, 84)
	_sector_label.size = Vector2(850, 26)
	_sector_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_sector_label)
	_progress_bar = ColorRect.new()
	_progress_bar.position = Vector2(24, 112)
	_progress_bar.size = Vector2(260, 4)
	_progress_bar.color = Color(0.18, 0.18, 0.18, 0.85)
	_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_progress_bar)
	_progress_fill = ColorRect.new()
	_progress_fill.size = Vector2(0, 4)
	_progress_fill.color = Color(0.8, 0.72, 0.48)
	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_bar.add_child(_progress_fill)
	_speed_label = UI.label("", 26)
	_speed_label.position = Vector2(1060, 20)
	_speed_label.size = Vector2(196, 50)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_speed_label)
	var retry_hint := "R sector retry · Shift+R full run" if sector_retry_enabled else "R full retry · Backspace checkpoint practice"
	var intro := course_intro if not course_intro.is_empty() else "Cross START to begin"
	_hint = UI.label("READY · " + intro + "\nWASD move · Mouse look · Space jump · Hold PULL, release to fly\n" + retry_hint + " · Esc pause", 16)
	_hint.position = Vector2(24, 128)
	_hint.size = Vector2(850, 90)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_hint)
	_finish_panel = CenterContainer.new()
	_finish_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_finish_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_finish_panel)
	_finish_panel.hide()
	for label in [_time_label, _progress_label, _sector_label, _speed_label, _hint]:
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 2)
	# Touch retry remains the full run; SECTOR resumes a practice entry.
	if player.hud.mobile_controls.enabled:
		_hint.text = "READY · " + intro + "\nMOVE / LOOK · JUMP · Hold PULL, let go to fly\nRETRY full run · " + ("SECTOR" if sector_retry_enabled else "CHECKPOINT") + " practice · II pause"
		var retry := UI.button("RETRY", restart)
		retry.position = Vector2(950, 78)
		overlay.add_child(retry)
		var checkpoint_retry := UI.button("SECTOR" if sector_retry_enabled else "CHECKPOINT", respawn_checkpoint)
		checkpoint_retry.position = Vector2(1070, 78)
		overlay.add_child(checkpoint_retry)
		player.hud.mobile_controls.extra_touch_buttons.assign([retry, checkpoint_retry])

func _physics_process(delta: float) -> void:
	if restarting or get_tree().paused or not player.gameplay_active:
		return
	clock.advance(delta)
	if recorder.capture(clock.elapsed, player.global_transform, clock.state == Clock.State.RUNNING, get_tree().paused):
		run_sampled.emit(clock.elapsed, player.global_transform)
	_feedback_time = maxf(0.0, _feedback_time - delta)
	if player.global_position.y < fall_height:
		respawn_checkpoint()

func _process(_delta: float) -> void:
	if not is_instance_valid(_time_label):
		return
	var best := "—" if clock.personal_best == 0.0 else _time_text(clock.personal_best)
	_time_label.text = "%s   PB %s" % [_time_text(clock.elapsed), best]
	if not clock.clean_run:
		_time_label.text += "   PRACTICE"
	var count: int = clock.checkpoint_splits.size()
	_progress_fill.size = Vector2(260.0 * count / maxf(clock.checkpoint_count, 1.0), 4)
	var sector := sector_names[mini(count, sector_names.size() - 1)] if not sector_names.is_empty() else course_title
	_progress_label.text = "%s   ·   %d / %d" % [sector, mini(count + 1, clock.checkpoint_count + 1), clock.checkpoint_count + 1]
	var sector_best := "—" if clock.current_sector_best <= 0.0 else _time_text(clock.current_sector_best)
	_sector_label.text = "SECTOR %s   BEST %s" % [_time_text(clock.current_sector_elapsed), sector_best]
	_speed_label.text = "%03d km/h" % roundi(player.velocity.length() * 3.6)
	if clock.state == Clock.State.RUNNING:
		_hint.text = _feedback if _feedback_time > 0.0 else ""
	if show_developer_speed and OS.is_debug_build():
		_time_label.text += "   %.1f m/s" % player.velocity.length()

static func _time_text(seconds: float) -> String:
	var milliseconds := floori(maxf(seconds, 0.0) * 1000.0)
	return "%02d:%02d.%03d" % [milliseconds / 60000, (milliseconds / 1000) % 60, milliseconds % 1000]

func _start_entered(body: Node3D) -> void:
	if body != player or restarting or clock.state != Clock.State.READY:
		return
	clock.start()
	last_finish_result.clear()
	recorder.start(course_id, player.global_transform)
	run_started.emit(course_id)
	run_sampled.emit(0.0, player.global_transform)
	_feedback = ""
	_feedback_time = 0.0

func _checkpoint_entered(body: Node3D, index: int) -> void:
	if body != player or restarting:
		return
	if not clock.checkpoint(index):
		if clock.state == Clock.State.RUNNING and index > clock.checkpoint_splits.size() + 1:
			_feedback = "Missed sector boundary %d · %s to recover" % [clock.checkpoint_splits.size() + 1, "R" if sector_retry_enabled else "Backspace"]
			_feedback_time = 4.0
		return
	_respawn = _checkpoints[index - 1].get_node("Respawn")
	var finished_sector := sector_names[index - 1] if index - 1 < sector_names.size() else "SECTOR %d" % index
	_feedback = "%s   %s" % [finished_sector, _time_text(clock.last_sector_time)]
	if clock.has_sector_comparison:
		_feedback += "   PB %+.3f" % clock.last_sector_delta
	if clock.has_split_comparison:
		_feedback += "   RUN %+.3f" % clock.last_split_delta
	_feedback_time = 3.0
	SoundManager.play_sfx(SoundManager.SFX_CHECKPOINT)
	if is_instance_valid(player.parkour_juice):
		player.parkour_juice.gate_passed()

func respawn_checkpoint() -> void:
	if restarting or clock.state == Clock.State.FINISHED:
		return
	if not is_instance_valid(_respawn):
		if not sector_retry_enabled:
			restart()
			return
	clock.restart_sector()
	recorder.mark_practice()
	get_tree().paused = false
	player.hud.is_paused = false
	player.hud.pause_screen.hide()
	player.hud.mobile_controls.reset_touches()
	_reset_player_inputs()
	player.grapple._clear_pending()
	player.grapple.aim_assist_target = null
	var retry_transform := _spawn_transform
	var retry_velocity := Vector3.ZERO
	if is_instance_valid(_respawn):
		retry_transform = _respawn.global_transform
		var boundary := _respawn.get_parent()
		if boundary.has_method("practice_velocity"):
			retry_velocity = boundary.practice_velocity()
	else:
		var spawn := get_node_or_null("PlayerSpawn") as Marker3D
		if spawn:
			retry_velocity = spawn.get_meta("initial_velocity", Vector3.ZERO)
	player.global_transform = retry_transform
	player.velocity = retry_velocity.limit_length(player.parkour_speed_limit) if retry_velocity.is_finite() else Vector3.ZERO
	player.input_dir = Vector3.ZERO
	player._hook_slide_timer = 0.0
	player._anchor_cooldown = 0.0
	player._recent_anchor = null
	player._hook_blocked_time = 0.0
	player._hook_previous_position = player.global_position
	player._body_collision.shape = player._full_capsule
	player._body_collision.position = player._full_capsule_position
	player._capsule_reduced = false
	player.camera.position = player._camera_base_pos
	player.camera.rotation = Vector3.ZERO
	if is_instance_valid(player.parkour_juice):
		player.parkour_juice.reset_effects()
	# A fall may have left an entry latch on a pad; a retry is a fresh approach.
	for pad in find_children("*", "Area3D", true, false):
		if pad.has_method("launch_velocity"):
			pad._occupants.clear()
	_feedback = "SECTOR RETRY · PRACTICE · " + ("Shift+R full run for a PB" if sector_retry_enabled else "R full run for a PB")
	_feedback_time = 2.0
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if player.hud.mobile_controls.enabled else Input.MOUSE_MODE_CAPTURED)

func _finish_entered(body: Node3D) -> void:
	if body != player or restarting or clock.state != Clock.State.RUNNING:
		return
	# finish() can replace the PB; the comparison always uses the prior run.
	var prior_best: float = clock.personal_best
	if clock.elapsed > 0.0 and clock.checkpoint_splits.size() == clock.checkpoint_count:
		if recorder.capture(clock.elapsed, player.global_transform, true, get_tree().paused, true):
			run_sampled.emit(clock.elapsed, player.global_transform)
	_save_failed = clock.finish() != OK
	if clock.state != Clock.State.FINISHED:
		_feedback = "Cross all %d checkpoints before FINISH · Backspace to recover" % clock.checkpoint_count
		_feedback_time = 4.0
		return
	last_finish_result = finish_result_for(prior_best)
	var recording: Dictionary = recorder.finish(clock.clean_run, last_finish_result.new_personal_best, not _save_failed)
	last_finish_result["recording"] = recording
	run_finished.emit(last_finish_result.duplicate(true))
	if recording.personal_best_eligible:
		personal_best_recorded.emit(recording)
	_reset_player_inputs()
	if is_instance_valid(player.parkour_juice):
		player.parkour_juice.reset_effects()
		player.parkour_juice.gate_passed(true)
	player.gameplay_active = false
	player.hud.game_started = false
	player.hud.mobile_controls.set_active(false)
	player.hud.speedlines.hide()
	player.hud._aim_assist_indicator.hide()
	_hint.hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	SoundManager.play_sfx(SoundManager.SFX_WIN)
	var panel := PanelContainer.new()
	panel.theme = UI.theme()
	panel.custom_minimum_size = Vector2(460, 0)
	_finish_panel.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	column.add_child(UI.label(course_title, 28))
	column.add_child(UI.label("FINISH   %.2f s" % clock.elapsed, 30))
	if last_finish_result.has_prior_best:
		column.add_child(UI.label("%+.2f s vs previous PB" % last_finish_result.delta_from_prior_best, 22))
	elif clock.clean_run:
		column.add_child(UI.label("First clean run", 18))
	var best_text := "—" if clock.personal_best <= 0.0 else "%.2f s" % clock.personal_best
	var best_label := "NEW PB SAVED · " if last_finish_result.new_personal_best and not _save_failed else "Personal best "
	if last_finish_result.new_personal_best and _save_failed:
		best_label = "Best this session "
	column.add_child(UI.label(best_label + best_text, 24))
	if medals_enabled:
		var medal_text: String = last_finish_result.medal
		if medal_text.is_empty():
			medal_text = "No medal yet"
		else:
			medal_text += " pace" if not clock.clean_run else " MEDAL"
		column.add_child(UI.label(medal_text, 24))
	if not clock.clean_run:
		column.add_child(UI.label("Practice complete · Retry for a clean PB", 18))
	else:
		column.add_child(UI.label("CLEAN RUN · All %d checkpoints" % clock.checkpoint_count, 18))
	if _save_failed:
		column.add_child(UI.label("Could not save PB to disk this run.", 16))
	var retry := UI.button("FULL RETRY  ·  Shift+R" if sector_retry_enabled else "RETRY  ·  R", restart)
	column.add_child(retry)
	column.add_child(UI.button("MAIN MENU", player.hud._on_quit_pressed))
	_finish_panel.show()
	retry.grab_focus()

func finish_result_for(prior_best: float) -> Dictionary:
	var improved: bool = clock.clean_run and (prior_best <= 0.0 or clock.elapsed < prior_best)
	return {"course_id": course_id, "time": clock.elapsed, "clean_run": clock.clean_run,
		"prior_personal_best": prior_best, "has_prior_best": prior_best > 0.0,
		"delta_from_prior_best": clock.elapsed - prior_best if prior_best > 0.0 else 0.0,
		"personal_best": clock.personal_best, "new_personal_best": improved,
		"best_saved": improved and not _save_failed,
		"medal": Clock.medal_for_time(clock.elapsed, medal_bronze, medal_silver, medal_gold, medal_developer) if medals_enabled else ""}

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("trial_full_restart", true) and not event.is_echo():
		restart()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("trial_restart") and not event.is_echo():
		if sector_retry_enabled and clock.state != Clock.State.FINISHED:
			respawn_checkpoint()
		else:
			restart()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_BACKSPACE:
		respawn_checkpoint()
		get_viewport().set_input_as_handled()

func _reset_player_inputs() -> void:
	if player.has_method("reset_movement_input"):
		player.reset_movement_input()
	else:
		player._end_hook(true)
		if player.has_method("reset_pull_state"):
			player.reset_pull_state()

func restart() -> void:
	if restarting:
		return
	restarting = true
	recorder.reset()
	last_finish_result.clear()
	player.gameplay_active = false
	_reset_player_inputs()
	player.grapple._clear_pending()
	get_tree().paused = false
	Engine.time_scale = 1.0
	GameManager.player = null
	# Recreate this small scene next idle frame: resets the capsule, camera,
	# timers, pads' overlap latches, anchor tweens and scene-owned FX.
	get_tree().call_deferred("reload_current_scene")
