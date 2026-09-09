extends SceneTree

const OPENING := preload("res://cutscenes/opening/OpeningCutscene.tscn")
const TIMELINE := preload("res://cutscenes/opening/scripts/opening_cutscene_timeline.gd")
var failures: Array[String] = []
var finishes := 0
var skips := 0
var cues: Array[StringName] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _create() -> Control:
	var cutscene := OPENING.instantiate() as Control
	cutscene.finished.connect(func(destination: StringName):
		_check(destination == &"bus_terminal_arrival", "Completion destination")
		finishes += 1)
	cutscene.skipped.connect(func(destination: StringName):
		_check(destination == &"bus_terminal_arrival", "Skip destination")
		skips += 1)
	cutscene.cue_requested.connect(func(id: StringName, _payload: Dictionary): cues.append(id))
	root.add_child(cutscene)
	return cutscene


func _run() -> void:
	_check(TIMELINE.SHOTS.size() == 10, "Ten authored shots")
	_check(TIMELINE.SHOTS[0].id == &"morning_coffee" and TIMELINE.SHOTS[1].id == &"family_photos", "Routine and family precede the call")
	for shot in TIMELINE.SHOTS.slice(0, 5):
		_check(String(shot.texture).contains("frame_v2_"), "Rebuilt morning visuals")
		for cue in shot.cues:
			_check(cue.id not in [&"rain_city", &"thunder_distant", &"lightning_flash"], "No storm audio over dry morning")
	var call: Dictionary = TIMELINE.SHOTS[3]
	# The timeline stores a translation key (extracted text), not the literal
	# line, so the narrative-content assertion resolves it through tr() first.
	var call_caption := tr(String(call.captions[0].text))
	_check(call_caption.contains("Seu irmão saiu"), "Opening establishes release and disappearance")
	_check(not call_caption.contains("assassinado"), "Opening no longer reports brother murdered")
	var duration := 0.0
	for shot in TIMELINE.SHOTS:
		duration += float(shot.duration)
		_check(load(shot.texture) is Texture2D, "Imported texture: " + shot.texture)
	_check(is_equal_approx(duration, 41.5), "Preserve 41.5-second timeline")
	var cutscene := _create()
	_check(not cutscene.get_node("ShotLabel").visible, "No review HUD in production")
	_check(cutscene.get_node("ProceduralAudio/ProvisionalUnderscore").bus == &"Music", "Music honors settings")
	_check(cutscene.get_node("ProceduralAudio/RainLoop").bus == &"SFX", "Foley honors settings")
	paused = true
	var start := Time.get_ticks_msec()
	var visited: Dictionary = {}
	while finishes == 0 and Time.get_ticks_msec() - start < 50000:
		visited[int(cutscene.get("_shot_index"))] = true
		await process_frame
	_check(finishes == 1 and skips == 0, "Natural playback finishes once while game paused")
	_check(visited.size() == 10, "Natural playback visits all ten images")
	_check(Time.get_ticks_msec() - start >= 41000, "Natural completion was not simulated by skip/seek")
	_check(cues.has(&"phone_ring_old") and cues.has(&"bus_air_brake"), "Phone and final bus audio cues ran")
	for audio in cutscene.get_node("ProceduralAudio").get_children():
		_check(not audio.playing, "Audio stops at completion")
	cutscene.skip()
	await create_timer(0.3).timeout
	_check(finishes == 1 and skips == 0, "Skip after finish cannot emit again")
	cutscene.queue_free()
	await process_frame
	cutscene = _create()
	cutscene.skip()
	cutscene.skip()
	_check(skips == 0, "Skip waits for actual fade")
	await create_timer(0.4).timeout
	_check(finishes == 1 and skips == 1, "Repeated skip completes exactly once")
	cutscene.queue_free()
	paused = false
	await process_frame
	print("OPENING_RUNTIME: %d failures; natural playback + skip + audio + production HUD" % failures.size())
	quit(0 if failures.is_empty() else 1)
