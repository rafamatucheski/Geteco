extends "res://tests/measure/measure_performance_plan.gd"
## Same rendered production scene and live load in both modes. Exercise the real
## speech presentation every seven seconds, alternating both language banks.
## GETECO_DIRECTED_VOICES=0 selects the preserved legacy path for comparison.
const LINE_KEYS := [
	"2f74ccc16ed52b718b42204c49235f59574f5f599fab5aca4763f109dce41430",
	"a0f159168a801dab0e029c9259fde373c44d1123fcb8aa78ab0bd27a6abf3f40",
	"5867edd5fce8669aa10a47373679c649ddcf4fc6f8e8ef92b4bb534d196587bf",
]
var _voice_rows: Array[Dictionary] = []
var _voice_events: Array[Dictionary] = []
var _next_voice_usec := 0
const BINDING := preload("res://audio/VoiceActorBinding.gd")

func run() -> void:
	scenario = "directed_voice"
	seconds = 42.0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogue/voice-line-direction.json"))
	if not data is Dictionary:
		push_error("VOICE_BENCHMARK_DIRECTION_MISSING")
		quit(9)
		return
	for key in LINE_KEYS:
		for row: Dictionary in data.get("lines", []):
			if row.get("key", "") == key:
				_voice_rows.append(row)
				break
	if _voice_rows.size() != LINE_KEYS.size():
		push_error("VOICE_BENCHMARK_CASE_MISSING")
		quit(9)
		return
	await super.run()

func apply_load(now: int) -> void:
	if now < _next_voice_usec: return
	_next_voice_usec = now + 7000000
	var index := _voice_events.size()
	var row: Dictionary = _voice_rows[index % _voice_rows.size()]
	var language := "pt_BR" if (index / _voice_rows.size()) % 2 == 0 else "en"
	var settings := root.get_node("V2Settings")
	settings.voice_language = language
	settings.text_language = language
	var began := Time.get_ticks_usec()
	world.session.show_speech(str(row.speaker).capitalize(), row.source, 6.8, true, row.speaker)
	var elapsed := Time.get_ticks_usec() - began
	var player: AudioStreamPlayer = world.session.speech_voice
	var stream := player.stream
	_voice_events.append({"source_key":row.key, "language":language,
		"dispatch_usec":elapsed, "playing":player.playing,
		"path":stream.resource_path if stream != null else "",
		"duration":stream.get_length() if stream != null else 0.0,
		"recording_language":stream.get_meta("voice_language", "") if stream != null else "",
		"notice":world.session.notice.text,
		"directed_mode":OS.get_environment("GETECO_DIRECTED_VOICES") != "0",
		"crowd":_exercise_crowd()})

func _exercise_crowd() -> Array[Dictionary]:
	# Exercise the production presenter with live local pedestrians, without
	# teleporting them, disabling their AI or inventing fixture-only bodies.
	var nearby: Array[Node3D] = []
	for candidate in world.people:
		if not is_instance_valid(candidate) or not candidate is Node3D: continue
		if candidate.global_position.distance_to(world.player.global_position) <= 35.0:
			nearby.append(candidate)
	nearby.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_squared_to(world.player.global_position) < b.global_position.distance_squared_to(world.player.global_position))
	var emitted: Array[Dictionary] = []
	for actor in nearby:
		var binding := BINDING.resolve(actor, "civilian_reaction")
		if binding.is_empty(): continue
		world.production.civilian_reactions.presenter.bubble(actor, "PARA COM ISSO!")
		var spatial := actor.get_node_or_null("ActorDialogueVoice") as AudioStreamPlayer3D
		emitted.append({"actor":BINDING.actor_id(actor), "gender":binding.gender,
			"character_id":binding.character_id,
			"playing":spatial != null and spatial.playing,
			"stream_character_id":spatial.stream.get_meta("character_id", "") if spatial != null and spatial.stream != null else ""})
		if emitted.size() == 3: break
	return emitted

func state() -> Dictionary:
	var row := super.state()
	row["voice_event_count"] = _voice_events.size()
	row["voice_events"] = _voice_events.duplicate(true)
	return row
