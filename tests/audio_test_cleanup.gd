extends RefCounted
## Test-only teardown: fixed-fps physics can outrun the wall-time audio mixer.

static func stop_voices(tree: SceneTree) -> void:
	for voice in tree.root.find_children("*", "AudioStreamPlayer", true, false):
		voice.stop()
		voice.stream = null

static func drain_mixer() -> void:
	OS.delay_msec(150)
