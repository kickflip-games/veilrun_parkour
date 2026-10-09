extends CanvasLayer
## Shared parkour input and pause UI. Course scenes own timers and results.

signal start_game_requested

const MOBILE_CONTROLS = preload("res://scenes/player/mobile_controls.gd")
const UI = preload("res://scenes/playtest/playtest_ui.gd")
const Effects = preload("res://scenes/parkour/presentation_settings.gd")
var mobile_controls = MOBILE_CONTROLS.new()

class PullIndicator extends Control:
	var phase := 0.0
	var pulling := false
	var acquire_left := 0.0
	func acquired() -> void:
		acquire_left = .18
	func step(delta: float, active_pull: bool, animate: bool) -> void:
		pulling = active_pull
		acquire_left = maxf(0.0,acquire_left-delta) if animate else 0.0
		phase = fmod(phase+delta,.7) if pulling and animate else 0.0
		queue_redraw()
	func circle_radius() -> float:
		return lerpf(30.0,21.0,phase/.7) if pulling else lerpf(27.0,32.0,acquire_left/.18)
	func _draw() -> void:
		var center := size*.5
		var cyan := Color(.35,.86,.92,.88)
		var radius := circle_radius()
		draw_arc(center,radius,0,TAU,48,cyan,1.7,true)
		for i in range(4):
			var outward := Vector2.from_angle(float(i)*PI*.5)
			var tip := center+outward*(radius-6.0)
			var back := center+outward*radius
			var side := outward.orthogonal()*3.0
			draw_line(back+side,tip,cyan,1.5,true)
			draw_line(back-side,tip,cyan,1.5,true)

@onready var speedlines: ColorRect = $SpeedlinesOverlay
@onready var pause_screen: Control = $PauseScreen

var player: CharacterBody3D
var _grapple: Node
var _aim_assist_indicator: PullIndicator
var _indicator_target: Node3D
var game_started := false
var is_paused := false

func _ready() -> void:
	player = get_parent()
	_grapple = player.get_node("Grapple")
	mobile_controls.name = "MobileControls"
	if bool(player.get("vertical_look_enabled")):
		mobile_controls.look_caption = "LOOK"
	add_child(mobile_controls)
	mobile_controls.pull_pressed.connect(player.press_pull)
	mobile_controls.pull_released.connect(player.release_pull)
	mobile_controls.jump_requested.connect(player.request_jump)
	mobile_controls.pause_requested.connect(toggle_pause)
	pause_screen.theme = UI.theme()
	$PauseScreen/PanelContainer/VBoxContainer/ResumeButton.pressed.connect(_on_resume_pressed)
	$PauseScreen/PanelContainer/VBoxContainer/RetryButton.pressed.connect(_on_restart_pressed)
	$PauseScreen/PanelContainer/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)
	_setup_aim_assist_indicator()
	mobile_controls.set_active(false)
	pause_screen.hide()

func _process(delta: float) -> void:
	mobile_controls.set_active(game_started and player.gameplay_active and not get_tree().paused)
	mobile_controls.set_pull_active(player.is_hooking)
	_update_aim_assist_indicator()
	if _aim_assist_indicator.visible and not get_tree().paused:
		_aim_assist_indicator.step(delta,player.is_hooking,Effects.effects_strength > 0.0)

func _setup_aim_assist_indicator() -> void:
	_aim_assist_indicator = PullIndicator.new()
	_aim_assist_indicator.name = "GrappleTargetIndicator"
	_aim_assist_indicator.size = Vector2(80, 80)
	_aim_assist_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_assist_indicator.z_index = 20
	_aim_assist_indicator.hide()
	add_child(_aim_assist_indicator)

func _update_aim_assist_indicator() -> void:
	if not game_started or not player.gameplay_active or get_tree().paused or not is_instance_valid(_grapple):
		_aim_assist_indicator.hide()
		return
	var target := player._hook_target as Node3D if player.is_hooking else _grapple.get("aim_assist_target") as Node3D
	if not _grapple.can_hook_target(target):
		_aim_assist_indicator.hide()
		return
	var camera := player.get_node("Camera3D") as Camera3D
	var target_point := target.global_position
	var body_shape := target.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if body_shape:
		target_point = body_shape.global_position
	if camera.is_position_behind(target_point):
		_aim_assist_indicator.hide()
		return
	var screen_point := camera.unproject_position(target_point)
	if not get_viewport().get_visible_rect().has_point(screen_point):
		_aim_assist_indicator.hide()
		return
	if target != _indicator_target or not _aim_assist_indicator.visible:
		_aim_assist_indicator.acquired()
	_indicator_target = target
	_aim_assist_indicator.modulate = Color.WHITE
	_aim_assist_indicator.position = screen_point - _aim_assist_indicator.size * 0.5
	_aim_assist_indicator.show()

func parkour_ready() -> void:
	game_started = true
	is_paused = false
	pause_screen.hide()
	mobile_controls.set_active(true)
	start_game_requested.emit()

func _on_start_pressed() -> void:
	parkour_ready()

func _start_game() -> void:
	parkour_ready()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if game_started and player.gameplay_active:
			toggle_pause()
			get_viewport().set_input_as_handled()

func toggle_pause() -> void:
	if not game_started or not player.gameplay_active:
		return
	is_paused = not is_paused
	player.reset_movement_input()
	get_tree().paused = is_paused
	pause_screen.visible = is_paused
	mobile_controls.set_active(not is_paused)
	SoundManager.play_sfx(SoundManager.SFX_PAUSE if is_paused else SoundManager.SFX_UNPAUSE)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if is_paused or mobile_controls.enabled else Input.MOUSE_MODE_CAPTURED)

func _on_resume_pressed() -> void:
	if is_paused:
		toggle_pause()

func _on_restart_pressed() -> void:
	player.reset_movement_input()
	get_tree().paused = false
	is_paused = false
	pause_screen.hide()
	mobile_controls.reset_touches()
	var course := get_tree().current_scene
	if course and course.has_method("restart"):
		course.restart()
	else:
		get_tree().reload_current_scene()

func _on_quit_pressed() -> void:
	player.reset_movement_input()
	get_tree().paused = false
	is_paused = false
	game_started = false
	player.gameplay_active = false
	mobile_controls.set_active(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	GameManager.player = null
	get_tree().change_scene_to_file("res://scenes/playtest/main_menu.tscn")
