@tool
extends RefCounted
## Course-local state. Physics time excludes pause; only RUNNING can finish.
enum State { READY, RUNNING, FINISHED }
var state := State.READY
var elapsed := 0.0
var personal_best := 0.0
var save_path := "user://parkour_bests.cfg"
var course_id := "switchback_v1"
var checkpoint_count: int = 0
var checkpoint_splits: Array[float] = []
var best_splits: Array[float] = []
var clean_run: bool = true
var last_split_delta: float = 0.0
var has_split_comparison: bool = false
var sector_start_elapsed := 0.0
var sector_times: Array[float] = []
var best_sector_times: Array[float] = []
var last_sector_time := 0.0
var last_sector_delta := 0.0
var has_sector_comparison := false
var _sector_bests_changed := false

var current_sector_elapsed: float:
	get:
		return maxf(0.0, elapsed - sector_start_elapsed)

var current_sector_best: float:
	get:
		var index := mini(checkpoint_splits.size(), checkpoint_count)
		return best_sector_times[index] if index < best_sector_times.size() else 0.0

static func medal_for_time(seconds: float, bronze: float, silver: float, gold: float, developer: float) -> String:
	if not is_finite(seconds) or seconds <= 0.0:
		return ""
	for threshold in [bronze, silver, gold, developer]:
		if not is_finite(threshold) or threshold <= 0.0:
			return ""
	if developer > gold or gold > silver or silver > bronze:
		return ""
	if seconds <= developer:
		return "DEVELOPER"
	if seconds <= gold:
		return "GOLD"
	if seconds <= silver:
		return "SILVER"
	if seconds <= bronze:
		return "BRONZE"
	return ""

func load_best() -> void:
	personal_best = 0.0
	best_splits.clear()
	best_sector_times.clear()
	best_sector_times.resize(checkpoint_count + 1)
	best_sector_times.fill(0.0)
	_sector_bests_changed = false
	var config := ConfigFile.new()
	if config.load(save_path) == OK:
		# Independent sectors are separate from the cumulative splits belonging
		# to one complete PB. Zero denotes a sector that has no clean record.
		var sectors: Variant = config.get_value(course_id + ":sectors", "seconds", [])
		if sectors is Array and sectors.size() == checkpoint_count + 1:
			var valid := true
			for value: Variant in sectors:
				if not (value is float or value is int) or not is_finite(float(value)) or float(value) < 0.0:
					valid = false
					break
			if valid:
				for index in range(sectors.size()):
					best_sector_times[index] = float(sectors[index])
		var saved_best: Variant = config.get_value(course_id, "seconds", 0.0)
		if not (saved_best is float or saved_best is int):
			return
		var value: float = float(saved_best)
		personal_best = value if is_finite(value) and value > 0.0 else 0.0
		if personal_best <= 0.0:
			return
		var saved_splits: Variant = config.get_value(course_id, "splits", [])
		if not saved_splits is Array or saved_splits.size() != checkpoint_count:
			return
		var previous := 0.0
		for split: Variant in saved_splits:
			if not (split is float or split is int):
				return
			var seconds := float(split)
			if not is_finite(seconds) or seconds < previous or seconds > personal_best:
				return
			previous = seconds
		for split: Variant in saved_splits:
			best_splits.append(float(split))

func start() -> void:
	if state == State.READY:
		state = State.RUNNING

func advance(delta: float) -> void:
	if state == State.RUNNING and is_finite(delta):
		elapsed += maxf(delta, 0.0)

func checkpoint(index: int) -> bool:
	if state != State.RUNNING or index != checkpoint_splits.size() + 1 or index > checkpoint_count:
		return false
	_complete_sector(index - 1)
	checkpoint_splits.append(elapsed)
	sector_start_elapsed = elapsed
	has_split_comparison = best_splits.size() == checkpoint_count
	last_split_delta = elapsed - best_splits[index - 1] if has_split_comparison else 0.0
	return true

func mark_practice() -> void:
	if state == State.RUNNING:
		clean_run = false

func restart_sector() -> void:
	# Keep total elapsed and completed gates: repeated sectors cannot manufacture
	# a clean full run. The individual sector clock starts at this retry.
	state = State.RUNNING
	clean_run = false
	sector_start_elapsed = elapsed
	has_sector_comparison = false
	last_sector_time = 0.0
	last_sector_delta = 0.0

func _complete_sector(index: int) -> void:
	last_sector_time = current_sector_elapsed
	if best_sector_times.size() != checkpoint_count + 1:
		best_sector_times.resize(checkpoint_count + 1)
		best_sector_times.fill(0.0)
	var previous := best_sector_times[index]
	has_sector_comparison = previous > 0.0
	last_sector_delta = last_sector_time - previous if has_sector_comparison else 0.0
	sector_times.append(last_sector_time)
	if clean_run and last_sector_time > 0.0 and (previous <= 0.0 or last_sector_time < previous):
		best_sector_times[index] = last_sector_time
		_sector_bests_changed = true

func finish() -> Error:
	if state != State.RUNNING or not is_finite(elapsed) or elapsed <= 0.0:
		return ERR_INVALID_DATA
	if checkpoint_splits.size() < checkpoint_count:
		return ERR_INVALID_DATA
	_complete_sector(checkpoint_count)
	state = State.FINISHED
	if not clean_run:
		return OK
	var improved := personal_best <= 0.0 or elapsed < personal_best
	if improved:
		personal_best = elapsed
		best_splits = checkpoint_splits.duplicate()
	if not improved and not _sector_bests_changed:
		return OK
	var config := ConfigFile.new()
	config.load(save_path)
	if improved:
		config.set_value(course_id, "seconds", personal_best)
		config.set_value(course_id, "splits", best_splits)
	config.set_value(course_id + ":sectors", "seconds", best_sector_times)
	return config.save(save_path)
