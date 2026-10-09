extends SceneTree
## Standalone clock assertions; no editor addon or test framework required.
## Godot --headless --path . --script tests/test_parkour_clock.gd

const Clock = preload("res://scenes/parkour/trial_clock.gd")
var test_path := ""
var failures: Array[String] = []
var assertion_count := 0
var _current_test := ""

func _initialize() -> void:
	test_path = "user://parkour_clock_validation_%d.cfg" % OS.get_process_id()
	call_deferred("run")

func run() -> void:
	var names: Array[String] = []
	for method in get_method_list():
		var name := String(method.name)
		if name.begins_with("test_"):
			names.append(name)
	names.sort()
	for name in names:
		_current_test = name
		var before := failures.size()
		setup()
		call(name)
		teardown()
		print("TEST ", "PASS " if failures.size() == before else "FAIL ", name)
	var sound := root.get_node_or_null("SoundManager")
	if sound != null:
		for child in sound.get_children():
			if child is AudioStreamPlayer:
				child.stop()
				child.stream = null
	await process_frame
	await process_frame
	OS.delay_msec(200)
	print("PARKOUR_CLOCK_RESULT ", JSON.stringify({"tests": names.size(), "assertions": assertion_count, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _assert(value: bool, message: String) -> void:
	assertion_count += 1
	if not value:
		failures.append(_current_test + ": " + message)

func assert_true(value: bool, message := "Expected true") -> void:
	_assert(value, message)

func assert_false(value: bool, message := "Expected false") -> void:
	_assert(not value, message)

func assert_eq(actual: Variant, expected: Variant, message := "") -> void:
	_assert(actual == expected, message if not message.is_empty() else "Expected %s, got %s" % [str(expected), str(actual)])

func setup() -> void:
	DirAccess.remove_absolute(test_path)

func teardown() -> void:
	DirAccess.remove_absolute(test_path)

func test_ready_and_finish_gates() -> void:
	var clock = Clock.new()
	clock.save_path = test_path
	clock.advance(2.0)
	assert_eq(clock.elapsed, 0.0, "Ready does not accrue time")
	assert_eq(clock.finish(), ERR_INVALID_DATA, "Finish before start is ignored")
	clock.start()
	clock.advance(1.25)
	clock.start()
	clock.advance(0.5)
	assert_eq(clock.elapsed, 1.75, "Reentering start does not reset the timer")
	assert_eq(clock.finish(), OK)
	clock.advance(4.0)
	assert_eq(clock.elapsed, 1.75, "Finish freezes elapsed time")
	assert_eq(clock.finish(), ERR_INVALID_DATA, "Duplicate finish does not save again")

func test_best_persists_and_only_improves() -> void:
	var first = Clock.new()
	first.save_path = test_path
	first.start()
	first.advance(20.0)
	assert_eq(first.finish(), OK)
	var second = Clock.new()
	second.save_path = test_path
	second.load_best()
	assert_eq(second.personal_best, 20.0)
	assert_eq(second.state, Clock.State.READY, "Fresh retry starts ready")
	assert_eq(second.elapsed, 0.0)
	second.start()
	second.advance(25.0)
	assert_eq(second.finish(), OK)
	var third = Clock.new()
	third.save_path = test_path
	third.load_best()
	assert_eq(third.personal_best, 20.0, "Slower finish cannot replace best")
	third.start()
	third.advance(18.0)
	assert_eq(third.finish(), OK)
	var reloaded = Clock.new()
	reloaded.save_path = test_path
	reloaded.load_best()
	assert_eq(reloaded.personal_best, 18.0, "Improved best survives a new instance")

func test_invalid_best_and_negative_delta() -> void:
	var config := ConfigFile.new()
	config.set_value("switchback_v1", "seconds", -4.0)
	config.save(test_path)
	var clock = Clock.new()
	clock.save_path = test_path
	clock.load_best()
	assert_eq(clock.personal_best, 0.0)
	clock.start()
	clock.advance(-1.0)
	clock.advance(INF)
	clock.advance(NAN)
	assert_eq(clock.elapsed, 0.0)
	assert_eq(clock.finish(), ERR_INVALID_DATA, "Zero-duration runs do not set a best")

func test_checkpoints_must_be_running_and_sequential() -> void:
	var clock = Clock.new()
	clock.save_path = test_path
	clock.checkpoint_count = 2
	assert_false(clock.checkpoint(1), "Ready cannot record a split")
	clock.start()
	clock.advance(1.25)
	assert_false(clock.checkpoint(0), "Checkpoint indices start at one")
	assert_false(clock.checkpoint(2), "Skipping the next checkpoint is rejected")
	assert_true(clock.checkpoint(1))
	assert_false(clock.has_split_comparison, "No best means no split comparison")
	assert_false(clock.checkpoint(1), "Reentering a checkpoint does not change its split")
	clock.advance(2.0)
	assert_true(clock.checkpoint(2))
	assert_false(clock.checkpoint(3), "Indices beyond the course count are rejected")
	assert_eq(clock.checkpoint_splits, [1.25, 3.25])
	clock.advance(0.75)
	assert_eq(clock.finish(), OK)
	assert_false(clock.checkpoint(1), "Finished runs cannot record more splits")
	assert_eq(clock.checkpoint_splits, [1.25, 3.25])

func test_missing_checkpoint_keeps_run_running() -> void:
	var clock = Clock.new()
	clock.save_path = test_path
	clock.checkpoint_count = 2
	clock.start()
	clock.advance(3.0)
	assert_true(clock.checkpoint(1))
	assert_eq(clock.finish(), ERR_INVALID_DATA, "Finish requires the entire ordered course")
	assert_eq(clock.state, Clock.State.RUNNING)
	assert_eq(clock.personal_best, 0.0)
	assert_false(FileAccess.file_exists(test_path), "An incomplete course cannot save a best")
	clock.advance(4.0)
	assert_true(clock.checkpoint(2))
	clock.advance(1.0)
	assert_eq(clock.finish(), OK)
	assert_eq(clock.personal_best, 8.0)

func test_practice_finish_preserves_saved_best_and_splits() -> void:
	var best = _new_long_clock()
	best.start()
	best.advance(6.0)
	assert_true(best.checkpoint(1))
	best.advance(8.0)
	assert_true(best.checkpoint(2))
	best.advance(6.0)
	assert_eq(best.finish(), OK)
	var practice = _new_long_clock()
	practice.load_best()
	practice.mark_practice()
	assert_true(practice.clean_run, "Ready cannot be marked as a practice run")
	practice.start()
	practice.advance(2.0)
	assert_true(practice.checkpoint(1))
	practice.mark_practice()
	practice.advance(2.0)
	assert_true(practice.checkpoint(2))
	practice.advance(1.0)
	assert_eq(practice.finish(), OK)
	assert_eq(practice.state, Clock.State.FINISHED, "Practice runs still get a finish time")
	assert_eq(practice.elapsed, 5.0)
	assert_false(practice.clean_run)
	assert_eq(practice.personal_best, 20.0, "A checkpoint respawn cannot claim a personal best")
	assert_eq(practice.best_splits, [6.0, 14.0])
	var reloaded = _new_long_clock()
	reloaded.load_best()
	assert_eq(reloaded.personal_best, 20.0)
	assert_eq(reloaded.best_splits, [6.0, 14.0], "Practice cannot overwrite the saved splits")

func test_practice_without_existing_best_does_not_create_save() -> void:
	var clock = Clock.new()
	clock.save_path = test_path
	clock.start()
	clock.mark_practice()
	clock.advance(2.0)
	assert_eq(clock.finish(), OK)
	assert_eq(clock.state, Clock.State.FINISHED)
	assert_eq(clock.personal_best, 0.0)
	assert_eq(clock.best_splits, [])
	assert_false(FileAccess.file_exists(test_path))

func test_splits_persist_with_best_and_course_version() -> void:
	var old_course = Clock.new()
	old_course.save_path = test_path
	old_course.start()
	old_course.advance(5.0)
	assert_eq(old_course.finish(), OK)
	var first = _new_long_clock()
	first.load_best()
	assert_eq(first.personal_best, 0.0, "The expanded course has a separate personal best")
	first.start()
	first.advance(7.0)
	assert_true(first.checkpoint(1))
	first.advance(7.0)
	assert_true(first.checkpoint(2))
	first.advance(6.0)
	assert_eq(first.finish(), OK)
	var slower = _new_long_clock()
	slower.load_best()
	assert_eq(slower.personal_best, 20.0)
	assert_eq(slower.best_splits, [7.0, 14.0])
	slower.start()
	slower.advance(6.0)
	assert_true(slower.checkpoint(1))
	slower.advance(7.0)
	assert_true(slower.checkpoint(2))
	slower.advance(8.0)
	assert_eq(slower.finish(), OK)
	assert_eq(slower.best_splits, [7.0, 14.0], "Splits belong to the complete PB run, not the quickest sector")
	var improved = _new_long_clock()
	improved.load_best()
	assert_eq(improved.best_splits, [7.0, 14.0])
	improved.start()
	improved.advance(5.0)
	assert_true(improved.checkpoint(1))
	improved.advance(7.0)
	assert_true(improved.checkpoint(2))
	improved.advance(6.0)
	assert_eq(improved.finish(), OK)
	var reloaded = _new_long_clock()
	reloaded.load_best()
	assert_eq(reloaded.personal_best, 18.0)
	assert_eq(reloaded.best_splits, [5.0, 12.0], "A new PB replaces its matching split record")
	old_course.load_best()
	assert_eq(old_course.personal_best, 5.0, "Saving the expanded course preserves the old record")
	assert_eq(old_course.best_splits, [])

func test_checkpoint_delta_compares_cumulative_best_time() -> void:
	var config := ConfigFile.new()
	config.set_value("switchback_long_v2", "seconds", 20.0)
	config.set_value("switchback_long_v2", "splits", [6.0, 14.0])
	assert_eq(config.save(test_path), OK)
	var clock = _new_long_clock()
	clock.load_best()
	clock.start()
	clock.advance(4.0)
	assert_true(clock.checkpoint(1))
	assert_true(clock.has_split_comparison)
	assert_eq(clock.last_split_delta, -2.0, "Negative delta means ahead of the PB")
	clock.advance(11.0)
	assert_true(clock.checkpoint(2))
	assert_eq(clock.last_split_delta, 1.0, "Positive delta means behind the PB")

func test_load_rejects_invalid_or_mismatched_splits() -> void:
	var config := ConfigFile.new()
	config.set_value("switchback_long_v2", "seconds", 20.0)
	var invalid_records: Array = [[6.0], [6.0, 21.0], [14.0, 6.0], [-1.0, 14.0], [6.0, INF], [6.0, "14"], "invalid"]
	for splits: Variant in invalid_records:
		config.set_value("switchback_long_v2", "splits", splits)
		assert_eq(config.save(test_path), OK)
		var clock = _new_long_clock()
		clock.load_best()
		assert_eq(clock.personal_best, 20.0, "A valid finish time survives an invalid split record")
		assert_eq(clock.best_splits, [], "Only a complete, ordered, numeric split record can be compared")
		clock.start()
		clock.advance(2.0)
		assert_true(clock.checkpoint(1))
		assert_false(clock.has_split_comparison)
		assert_eq(clock.last_split_delta, 0.0)
	config.set_value("switchback_long_v2", "splits", [6.0, 14.0])
	assert_eq(config.save(test_path), OK)
	var clock = _new_long_clock()
	clock.load_best()
	assert_eq(clock.best_splits, [6.0, 14.0])
	clock.course_id = "unplayed_course"
	clock.load_best()
	assert_eq(clock.personal_best, 0.0, "Loading another course clears a stale best")
	assert_eq(clock.best_splits, [])

func _new_long_clock():
	var clock = Clock.new()
	clock.save_path = test_path
	clock.course_id = "switchback_long_v2"
	clock.checkpoint_count = 2
	return clock

func test_sector_time_is_local_and_total_split_stays_cumulative() -> void:
	var clock = _new_long_clock()
	clock.start()
	clock.advance(6.25)
	assert_eq(clock.current_sector_elapsed, 6.25)
	assert_true(clock.checkpoint(1))
	assert_eq(clock.last_sector_time, 6.25)
	assert_eq(clock.current_sector_elapsed, 0.0)
	clock.advance(4.0)
	assert_true(clock.checkpoint(2))
	assert_eq(clock.last_sector_time, 4.0)
	assert_eq(clock.checkpoint_splits, [6.25, 10.25])
	clock.advance(3.0)
	assert_eq(clock.finish(), OK)
	assert_eq(clock.sector_times, [6.25, 4.0, 3.0])
	assert_eq(clock.best_sector_times, [6.25, 4.0, 3.0])

func test_slower_clean_run_can_improve_an_independent_sector() -> void:
	var first = _new_long_clock()
	first.start()
	first.advance(6.0)
	assert_true(first.checkpoint(1))
	first.advance(7.0)
	assert_true(first.checkpoint(2))
	first.advance(7.0)
	assert_eq(first.finish(), OK)
	var second = _new_long_clock()
	second.load_best()
	assert_eq(second.best_sector_times, [6.0, 7.0, 7.0])
	second.start()
	second.advance(5.0)
	assert_true(second.checkpoint(1))
	assert_true(second.has_sector_comparison)
	assert_eq(second.last_sector_delta, -1.0)
	second.advance(9.0)
	assert_true(second.checkpoint(2))
	assert_eq(second.last_sector_delta, 2.0)
	second.advance(9.0)
	assert_eq(second.finish(), OK)
	var reloaded = _new_long_clock()
	reloaded.load_best()
	assert_eq(reloaded.personal_best, 20.0, "Slower run preserves the full PB")
	assert_eq(reloaded.best_splits, [6.0, 13.0], "Cumulative splits still belong to the full PB")
	assert_eq(reloaded.best_sector_times, [5.0, 7.0, 7.0], "Independent sector record survives the slower full run")

func test_sector_retry_keeps_total_progress_and_rejects_seeded_records() -> void:
	var clock = _new_long_clock()
	clock.start()
	clock.advance(7.0)
	assert_true(clock.checkpoint(1))
	clock.advance(3.0)
	clock.restart_sector()
	assert_eq(clock.elapsed, 10.0, "Sector retry retains full elapsed time")
	assert_eq(clock.checkpoint_splits, [7.0], "Sector retry retains ordered completed boundaries")
	assert_eq(clock.current_sector_elapsed, 0.0)
	assert_false(clock.clean_run)
	clock.advance(2.0)
	assert_true(clock.checkpoint(2))
	assert_eq(clock.last_sector_time, 2.0, "Only time after the sector retry is measured")
	assert_eq(clock.best_sector_times[1], 0.0, "Authored velocity seeds do not claim a clean sector record")
	clock.advance(1.0)
	assert_eq(clock.finish(), OK)
	assert_eq(clock.personal_best, 0.0)
	assert_false(FileAccess.file_exists(test_path), "Practice does not save total or sector records")
	assert_eq(clock.checkpoint_splits, [7.0, 12.0])

func test_ready_sector_retry_starts_practice_immediately() -> void:
	var clock = _new_long_clock()
	clock.restart_sector()
	assert_eq(clock.state, Clock.State.RUNNING)
	assert_false(clock.clean_run)
	clock.advance(0.25)
	assert_eq(clock.current_sector_elapsed, 0.25)
	assert_eq(clock.elapsed, 0.25)
	clock.start()
	assert_false(clock.clean_run, "Crossing START cannot restore a retried attempt to clean")

func test_invalid_sector_records_do_not_corrupt_total_pb() -> void:
	var config := ConfigFile.new()
	config.set_value("switchback_long_v2", "seconds", 20.0)
	config.set_value("switchback_long_v2", "splits", [6.0, 13.0])
	for sectors: Variant in [[5.0, 7.0], [5.0, -1.0, 7.0], [5.0, INF, 7.0], [5.0, "7", 7.0], "invalid"]:
		config.set_value("switchback_long_v2:sectors", "seconds", sectors)
		assert_eq(config.save(test_path), OK)
		var clock = _new_long_clock()
		clock.load_best()
		assert_eq(clock.personal_best, 20.0)
		assert_eq(clock.best_splits, [6.0, 13.0])
		assert_eq(clock.best_sector_times, [0.0, 0.0, 0.0], "Malformed sectors are rejected independently")
