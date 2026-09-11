extends SceneTree

const OPENING := preload("res://cutscenes/opening/OpeningCutscene.tscn")
const TIMELINE := preload("res://cutscenes/opening/v3/opening_timeline.gd")
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
	var timing: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://cutscenes/opening/v3/audio/voice_timing.json"))
	_check(timing.pt[0].text.contains("saiu da prisão"), "Soltura explícita, irmão vivo")
	for locale in ["pt","en"]:
		var end:=0.0
		for line in timing[locale]:
			_check(float(line.start)>=end and float(line.end)>float(line.start),"Falas completas sem sobreposição")
			end=float(line.end)
	var duration := 0.0
	for shot in TIMELINE.SHOTS:
		duration += float(shot.duration)
	_check(is_equal_approx(duration, 68.0), "Montagem autoral de 68 segundos")
	var cutscene := _create()
	_check(not cutscene.get_node("ShotLabel").visible, "No review HUD in production")
	_check(cutscene.get_node("ProceduralAudio/ProvisionalUnderscore").bus == &"Music", "Music honors settings")
	_check(cutscene.get_node("ProceduralAudio/RainLoop").bus == &"SFX", "Foley honors settings")
	paused = true
	var start := Time.get_ticks_msec()
	var visited: Dictionary = {}
	while finishes == 0 and Time.get_ticks_msec() - start < 76000:
		if cutscene._shot_index>=0: visited[int(cutscene._shot_index)] = true
		await process_frame
	_check(finishes == 1 and skips == 0, "Natural playback finishes once while game paused")
	_check(visited.size() == 10, "Natural playback visits all ten images")
	_check(Time.get_ticks_msec() - start >= 68000, "Natural completion was not simulated by skip/seek")
	_check(cues.has(&"phone_ring_old") and cues.has(&"bus_air_brake"), "Phone and final bus audio cues ran")
	for audio in cutscene.get_node("ProceduralAudio").get_children():
		_check(not audio.playing, "Audio stops at completion")
	cutscene.skip()
	await create_timer(0.3).timeout
	_check(finishes == 1 and skips == 0, "Skip after finish cannot emit again")
	cutscene.queue_free()
	await process_frame
	cutscene = _create()
	cutscene.seek(27.3)
	cutscene.pause_playback()
	var still: float=cutscene._total_elapsed
	await create_timer(.25).timeout
	_check(is_equal_approx(cutscene._total_elapsed,still),"Pausa congela câmera e atuação")
	for audio in cutscene._procedural_audio.players:
		_check(audio.stream_paused,"Pausa congela todos os stems")
	cutscene.resume_playback()
	await create_timer(.15).timeout
	_check(cutscene._total_elapsed>still,"Retomar avança a mesma cena")
	cutscene.skip()
	cutscene.skip()
	_check(skips == 0, "Skip waits for actual fade")
	await create_timer(0.4).timeout
	_check(finishes == 1 and skips == 1, "Repeated skip completes exactly once")
	cutscene.queue_free()
	paused = false
	await process_frame
	print("OPENING_RUNTIME_V3: %d failures; reprodução natural 68s, pausa, voz, destino único e pulo" % failures.size())
	quit(0 if failures.is_empty() else 1)
