extends SceneTree
## Focused integration of the production receiver with real local OGG playback.
## No gameplay/saves or additional engine/ambience mixers are needed here.

class RadioWorld extends Node:
	var driving := {"occupied": true, "car": null}
	var session := {"state": {"region_id": "harbor"}, "dialogue_open": false, "modal": false, "rebinding_action": ""}

class RadioOnly extends "res://audio/WorldAudio.gd":
	func _ready() -> void:
		radio = AudioStreamPlayer.new()
		radio.name = "VehicleRadio"
		add_child(radio)
	func _process(_delta: float) -> void:
		pass

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func run() -> void:
	var world := RadioWorld.new()
	root.add_child(world)
	var first := CharacterBody3D.new()
	var second := CharacterBody3D.new()
	world.add_child(first)
	world.add_child(second)
	var receiver := RadioOnly.new()
	receiver.world = world
	world.add_child(receiver)
	world.driving.car = first
	receiver._update_radio(.1)
	check(receiver.radio_index == 0 and receiver.radio.playing, "Harbor default and all legacy station indices remain compatible")
	check(receiver.STATIONS[10] == "porto_cruise" and receiver.STATIONS.size() == 12, "Country appends after the eleven existing stations")
	world.session.state.region_id = "desert"
	receiver._update_radio(.1)
	check(receiver.radio_index == receiver.COUNTRY_STATION and receiver.radio.playing, "Crossing into desert automatically tunes an untouched receiver")
	check(receiver.radio.stream is AudioStreamOggVorbis and receiver.radio.stream.loop, "Country plays a compressed local looping stream")
	check(receiver.radio.stream.get_length() > 240.0, "Country programme contains minutes of music, not a short ambience loop")
	check(receiver.radio_notice.text == "FRONTEIRA COUNTRY", "Functional station announcement identifies country")
	check(first.get_meta("radio_index", -1) == receiver.COUNTRY_STATION, "Automatic country choice stays with its car")

	receiver._set_station(2)
	world.session.state.region_id = "harbor"
	receiver._update_radio(.1)
	world.session.state.region_id = "desert"
	receiver._update_radio(.1)
	check(receiver.radio_index == 2, "Crossing never overwrites a manually chosen station")
	receiver._set_station(-1)
	world.session.state.region_id = "harbor"
	receiver._update_radio(.1)
	world.session.state.region_id = "desert"
	receiver._update_radio(.1)
	check(receiver.radio_index == -1 and not receiver.radio.playing, "Crossing respects radio off")
	receiver._cycle_radio(-1)
	check(receiver.radio_index == receiver.COUNTRY_STATION, "Previous from off selects the new final station")
	receiver._cycle_radio(1)
	check(receiver.radio_index == -1, "Next from country reaches off")

	world.driving.car = second
	receiver._update_radio(.1)
	check(receiver.radio_index == receiver.COUNTRY_STATION, "A fresh desert vehicle starts on country")
	receiver.radio.seek(37.0)
	await process_frame
	world.driving.occupied = false
	receiver._update_radio(.1)
	check(not receiver.radio.playing, "Exiting car stops radio")
	check(float(second.get_meta("radio_position", 0.0)) >= 36.5, "Exit retains this car's playback position")
	world.driving.occupied = true
	receiver._update_radio(.1)
	check(receiver.radio_index == receiver.COUNTRY_STATION and receiver.radio.get_playback_position() >= 36.5, "Reentering resumes that car's programme")
	world.session.dialogue_open = true
	receiver._update_radio(1.0)
	check(receiver.radio.volume_db < receiver.RADIO_VOLUME_DB - 10.0, "Dialogue ducks radio to preserve speech")
	world.session.dialogue_open = false
	receiver._update_radio(1.0)
	check(is_equal_approx(receiver.radio.volume_db, receiver.RADIO_VOLUME_DB), "Radio returns to its normal gain after dialogue")
	world.driving.car = first
	receiver._update_radio(.1)
	check(receiver.radio_index == -1 and not receiver.radio.playing, "Changing cars does not carry another vehicle's music along")
	receiver._set_station(999)
	check(receiver.radio_index == -1 and not receiver.radio.playing, "Invalid station safely switches off without indexing outside catalog")
	world.free()
	for failure in failures: push_error(failure)
	print("DESERT_COUNTRY_RADIO ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
