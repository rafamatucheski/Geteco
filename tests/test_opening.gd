extends SceneTree
var failures: Array[String] = []
var completions: Array[bool] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	if not value: failures.append(label); push_error(label)
func run() -> void:
	var timeline := preload("res://cutscenes/opening/v3/opening_timeline.gd")
	check(timeline.SHOTS.size() == 28 and timeline.IMAGES.size() == 28, "all28 original shots")
	for path in timeline.IMAGES: check(ResourceLoader.exists(path), "original approved frame " + path)
	for skip in [true, false]:
		var presentation := preload("res://runtime/OpeningPresentation.gd").new()
		presentation.completed.connect(func(was_skipped: bool): completions.append(was_skipped))
		root.add_child(presentation)
		check(paused and not presentation.film.show_studio_intro, "film pauses native world without extra studio card")
		check(presentation.film.finish_before_travel,"native ferry opening ends before legacy bus journey")
		for i in 3: await process_frame
		check(presentation.film._textures.size() == 28, "complete imported image montage")
		check(presentation.film._procedural_audio.players.size() == 3, "original voice music foley stems")
		if skip:
			presentation.film.request_skip()
			check(presentation.film._paused and presentation.film._skip_dialog.visible, "skip asks original confirmation")
			presentation.film.skip()
		else:
			presentation.film.seek(55.0+timeline.E-.01)
			presentation.film._process(.1)
			check(presentation.film._shot_index==21,"ferry transition never displays legacy bus frame")
		presentation.film._process(1)
		check(not paused, "finish restores prior tree state")
		await process_frame
	check(completions == [true, false], "skip and actual ending each emit exactly once")
	var arrival := preload("res://runtime/Arrival.gd").new()
	arrival.opening_completed = true
	arrival.phase = "disembark"
	var restored := preload("res://runtime/Arrival.gd").new()
	check(restored.restore_state(arrival.snapshot()) and restored.opening_completed, "finished film checkpoint survives save for no replay")
	arrival.free()
	restored.free()
	print("OPENING failures=", failures)
	quit(0 if failures.is_empty() else 1)
