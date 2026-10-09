extends Node
## Parkour music and traversal feedback. Short sounds free themselves.

const MUSIC = preload("res://sfx/music.mp3")
const SFX_GRAPPLE_ARRIVAL = preload("res://sfx/grapple_arrival.wav")
const SFX_CHECKPOINT = preload("res://sfx/checkpoint.wav")
const SFX_SPRING = SFX_CHECKPOINT
const SFX_PAUSE = preload("res://sfx/pause.wav")
const SFX_UNPAUSE = preload("res://sfx/unpause.wav")
const SFX_WIN = preload("res://sfx/win.wav")
const SFX_ANCHOR_LOCK = preload("res://sfx/anchor_lock.wav")
const SFX_PULL_ON = preload("res://sfx/pull_on.wav")
const SFX_PULL_RELEASE = preload("res://sfx/pull_release.wav")
const SPEED_WIND = preload("res://sfx/speed_wind.wav")
const PRESENTATION = preload("res://scenes/parkour/presentation_settings.gd")

@onready var music_player: AudioStreamPlayer = $MusicPlayer
var _speed_wind: AudioStreamWAV
var _pressure_hiss: AudioStreamWAV

func _ready() -> void:
	music_player.stream = MUSIC
	music_player.stream.loop = true
	# Background music stays off; traversal feedback uses separate SFX players.
	music_player.stop()
	_speed_wind = SPEED_WIND.duplicate() as AudioStreamWAV
	_speed_wind.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_speed_wind.loop_end = int(_speed_wind.get_length() * _speed_wind.mix_rate)
	_pressure_hiss = SPEED_WIND.duplicate() as AudioStreamWAV
	_pressure_hiss.loop_mode = AudioStreamWAV.LOOP_DISABLED

func play_pressure_hiss() -> AudioStreamPlayer:
	var strength: float = PRESENTATION.effects_strength
	if strength <= 0.0 or get_tree().paused:
		return null
	var sound := AudioStreamPlayer.new()
	sound.name = "PressureHiss"
	sound.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(sound)
	sound.add_to_group("pressure_hiss")
	sound.stream = _pressure_hiss
	sound.pitch_scale = .8
	sound.volume_db = -24.0+linear_to_db(strength)
	sound.finished.connect(sound.queue_free)
	sound.play()
	# Reuse the existing wind sample for a short entry hiss. The bound tween
	# freezes with the voice on pause and stops playback before removing it.
	var fade := sound.create_tween()
	fade.tween_interval(.18)
	fade.tween_property(sound,"volume_db",-60.0,.12)
	fade.tween_callback(sound.stop)
	fade.tween_callback(sound.queue_free)
	return sound

func play_pull_cue(stream: AudioStream) -> void:
	var strength: float = PRESENTATION.effects_strength
	if strength <= 0.0:
		return
	var sound := AudioStreamPlayer.new()
	add_child(sound)
	sound.stream = stream
	sound.volume_db = -10.0 + linear_to_db(strength)
	sound.finished.connect(sound.queue_free)
	sound.play()

func create_wind_player(owner_node: Node) -> AudioStreamPlayer:
	var wind := AudioStreamPlayer.new()
	wind.name = "SpeedWind"
	wind.stream = _speed_wind
	wind.volume_db = -80.0
	wind.process_mode = Node.PROCESS_MODE_PAUSABLE
	owner_node.add_child(wind)
	return wind

func play_sfx(stream: AudioStream) -> void:
	var sound := AudioStreamPlayer.new()
	add_child(sound)
	sound.stream = stream
	sound.finished.connect(sound.queue_free)
	sound.play()
