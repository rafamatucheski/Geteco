extends SceneTree
const AMBIENCE := preload("res://audio/desert_ambience/DesertAmbience.gd")
class AudioWorld extends Node:
	var player := Node3D.new()
	var session := {"state":{"region_id":"harbor", "place_id":""}, "dialogue_open":false, "modal":false, "weather":{"time_of_day":0.45}}
var failures: Array[String] = []
func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var world := AudioWorld.new()
	root.add_child(world)
	world.add_child(world.player)
	var mix := AMBIENCE.new()
	mix.world = world
	world.add_child(mix)
	mix.set_process(false)
	mix._process(1.0)
	check(mix.bank.is_empty() and not mix.wind.playing, "Other regions must not load/play desert sounds")
	world.session.state.region_id = "desert"
	world.player.position = Vector3(-140, 0, -940)
	for i in 60: mix._process(0.1)
	check(mix.wind.playing and mix.gain > 0.9, "Desert exterior must have wind")
	check(mix.wind.stream is AudioStreamOggVorbis and mix.wind.stream.loop, "Wind must loop without a restart gap")
	for kind in mix.bank:
		for stream in mix.bank[kind]: check(stream != null and stream.get_length() > 0.0, "Missing audio: " + kind)
	mix.rng.seed = 123
	var seen: Dictionary = {}
	for i in 20:
		var previous: String = mix.last_kind
		mix._play_detail()
		check(mix.last_kind != previous, "Avoid consecutive identical cues")
		check(mix.detail_clock >= 24.0 and mix.detail_clock <= 52.0, "Sparse randomized intervals")
		check(mix.last_kind != "dog", "No nocturnal calls during day")
		seen[mix.last_kind] = true
	check(seen.has("scrap") and seen.has("birds") and seen.has("gust"), "Day palette near structures")
	world.player.position = Vector3(-800, 0, -1100)
	world.session.weather.time_of_day = 0.9
	for i in 10:
		mix._play_detail()
		check(mix.last_kind in ["gust", "dog"], "Open desert at night must not play birds/metal")
	world.session.state.place_id = "desert_bank"
	for i in 60: mix._process(0.1)
	check(not mix.detail.playing and mix.gain < 0.13, "Interiors muffle wind and stop outdoor detail")
	world.session.state.place_id = ""
	world.session.dialogue_open = true
	for i in 60: mix._process(0.1)
	check(not mix.detail.playing and mix.gain < 0.36, "Dialogue ducks wind and suppresses detail")
	world.session.dialogue_open = false
	world.session.state.region_id = "mountain"
	for i in 100: mix._process(0.1)
	check(not mix.wind.playing and not mix.detail.playing, "Leaving desert stops both channels")
	check(mix.get_child_count() == 2, "Bounded two-channel budget")
	world.free()
	for failure in failures: push_error(failure)
	print("DESERT_AMBIENCE ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
