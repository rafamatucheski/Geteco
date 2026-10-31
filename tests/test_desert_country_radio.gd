extends SceneTree
## Integração focada do receptor de produção com reprodução local real de OGG.
## Não precisa aqui de jogo/saves nem de mixers adicionais de motor/ambiente.

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
	receiver.rng.seed = 6102026
	world.driving.car = first
	receiver._update_radio(.1)
	var initial_station: int = receiver.radio_index
	check(initial_station >= -1 and initial_station < receiver.STATIONS.size(), "First entry chooses a valid station or off")
	check(first.get_meta("radio_index", -99) == initial_station, "First entry stores the choice on the vehicle")
	check(receiver.STATIONS[10] == "porto_cruise" and receiver.STATIONS.size() == 12, "Country appends after the eleven existing stations")
	world.session.state.region_id = "desert"
	receiver._update_radio(.1)
	check(receiver.radio_index == initial_station, "Crossing into desert preserves the randomly chosen station or off")
	receiver._set_station(receiver.COUNTRY_STATION)
	check(receiver.radio_index == receiver.COUNTRY_STATION and receiver.radio.playing, "Country can still be selected manually")
	check(receiver.radio.stream is AudioStreamOggVorbis and receiver.radio.stream.loop, "Country plays a compressed local looping stream")
	check(receiver.radio.stream.get_length() > 240.0, "Country programme contains minutes of music, not a short ambience loop")
	check(receiver.radio_notice.text == "FRONTEIRA COUNTRY", "Functional station announcement identifies country")
	check(first.get_meta("radio_index", -1) == receiver.COUNTRY_STATION, "Manual country choice stays with its car")

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
	check(second.has_meta("radio_index"), "A fresh desert vehicle also stores its random choice")
	receiver._set_station(receiver.COUNTRY_STATION)
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
	# Fixed, bounded sample exercises the production receiver, including actual OGG playback.
	for region in ["harbor", "desert"]:
		world.session.state.region_id = region
		var seen := {}
		for index in 128:
			var car := CharacterBody3D.new()
			world.add_child(car)
			world.driving.car = car
			receiver._update_radio(.1)
			var chosen: int = receiver.radio_index
			seen[chosen] = true
			check(chosen >= -1 and chosen < receiver.STATIONS.size(), "Random station stays within catalog")
			check(receiver.radio.playing == (chosen >= 0), "Random off is silent; a random station plays")
			if chosen >= 0:
				check(receiver.radio.stream.resource_path.ends_with(receiver.STATIONS[chosen]+".ogg"), "Playback matches the chosen station")
			receiver._update_radio(.1)
			check(receiver.radio_index == chosen, "Later frames do not reroll the station")
			world.driving.occupied = false
			receiver._update_radio(.1)
			world.driving.occupied = true
			receiver._update_radio(.1)
			check(receiver.radio_index == chosen and car.get_meta("radio_index", -99) == chosen, "Reentry preserves random stations and random off")
			world.driving.occupied = false
			receiver._update_radio(.1)
			world.driving.car = null
			world.driving.occupied = true
			car.free()
		check(seen.has(-1) and seen.size() == receiver.STATIONS.size()+1, "Bounded sample covers every station and off in "+region)
	world.free()
	for failure in failures: push_error(failure)
	print("DESERT_COUNTRY_RADIO ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
