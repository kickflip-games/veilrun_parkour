extends RefCounted
## Bounded transform samples for future ghosts; no player or filesystem access.
## Actual physics timestamps are retained. Missed samples never invent poses.

var sample_rate: float = 10.0
var max_samples: int = 9000
var samples: Array[Dictionary] = []
var course_id := ""
var active := false
var truncated := false
var practice := false
var _next_sample_time := 0.0
var _interval := 0.1

func reset() -> void:
	samples.clear()
	course_id = ""
	active = false
	truncated = false
	practice = false
	_next_sample_time = 0.0

func start(id: String, initial_transform: Transform3D) -> void:
	reset()
	course_id = id
	_interval = 1.0 / clampf(sample_rate, 1.0, 60.0) if is_finite(sample_rate) else 0.1
	active = true
	capture(0.0, initial_transform, true, false, true)
	_next_sample_time = _interval

func capture(elapsed: float, pose: Transform3D, running: bool, paused: bool, force := false) -> bool:
	if not active or practice or not running or paused or not is_finite(elapsed) or elapsed < 0.0:
		return false
	if not pose.is_finite():
		return false
	if not samples.is_empty() and elapsed <= float(samples[-1].time):
		return false
	if not force and elapsed + 0.000001 < _next_sample_time:
		return false
	if samples.size() >= clampi(max_samples, 1, 9000):
		truncated = true
		return false
	samples.append({"time": elapsed, "transform": pose})
	# Skip missed intervals rather than manufacturing repeated past poses.
	_next_sample_time = (floorf(elapsed / _interval) + 1.0) * _interval
	return true

func mark_practice() -> void:
	practice = true
	active = false
	samples.clear()

func finish(clean_run: bool, improved_best: bool, saved_best: bool) -> Dictionary:
	active = false
	var valid := clean_run and not practice and not samples.is_empty()
	return {"version": 1, "course_id": course_id, "sample_rate": 1.0 / _interval,
		"truncated": truncated, "personal_best_eligible": valid and improved_best and saved_best and not truncated,
		"samples": samples.duplicate(true) if valid else []}
