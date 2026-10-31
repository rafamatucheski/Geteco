extends SceneTree
## Exercita o helper real da sala, a faixa importada e a posse do rádio sem
## iniciar o Main nem nenhum mixer de áudio de ambiente/motor não relacionado.
const MUSIC := preload("res://audio/workshop/DigoWorkshopMusic.gd")
class RadioWorld extends Node:
	var driving := {"occupied":true,"car":null}
	var session := {"dialogue_open":false,"modal":false,"rebinding_action":""}
class RadioOnly extends "res://audio/WorldAudio.gd":
	func _ready() -> void:
		radio = AudioStreamPlayer.new()
		add_child(radio)
	func _process(_delta: float) -> void: pass
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func run() -> void:
	var track := load(MUSIC.TRACK) as AudioStreamOggVorbis
	check(track!=null and absf(track.get_length()-34.285714)<.01,"Imported original twelve-bar loop has its complete duration")
	if track==null: quit(1); return
	var world := RadioWorld.new()
	root.add_child(world)
	var receiver := RadioOnly.new()
	receiver.world = world
	world.add_child(receiver)
	# Usa um veículo real do projeto para o contrato de motorista controlado do receptor.
	var vehicle := preload("res://scripts/Vehicle.gd").new()
	vehicle.archetype = "desert_coyote"
	root.add_child(vehicle)
	vehicle.set_physics_process(false)
	vehicle.controlled = true
	world.driving.car = vehicle
	receiver._update_radio(.1)
	receiver._set_station(2)
	receiver.radio.seek(11.0)
	await process_frame
	var station: int = receiver.radio_index
	var position: float = receiver.radio.get_playback_position()
	var music := MUSIC.new()
	root.add_child(music)
	music.sync(false,receiver)
	check(music.get_child_count()==0 and not receiver.radio.stream_paused,"Outside workshop creates no music voice or radio override")
	music.sync(true,receiver)
	var voice: AudioStreamPlayer = music._voice
	check(voice!=null and voice.playing and voice.stream.loop,"Workshop owns one active compressed looping music voice")
	check(voice.bus==(&"Music" if AudioServer.get_bus_index(&"Music")>=0 else &"Master"),"Room music respects the configured Music volume bus")
	check(receiver.radio.stream_paused and receiver.radio_index==station,"Room soundtrack pauses radio without changing its station")
	await create_timer(.15).timeout
	check(voice.volume_db>MUSIC.SILENCE_DB and voice.volume_db<MUSIC.LEVEL_DB,"Room soundtrack enters through a real gradual fade")
	for repeat in 3: music.sync(true,receiver)
	check(music._voice==voice and music.get_child_count()==1,"Repeated location updates do not restart or duplicate the track")
	var other := MUSIC.new()
	root.add_child(other)
	other.sync(true,receiver)
	check(not other._active and not other._voice.playing,"A second room helper cannot overlap the current music owner")
	other.free()
	receiver._update_radio(.1)
	check(receiver.radio.stream_paused,"Normal radio updates cannot resume music under the room soundtrack")
	music.sync(false,receiver)
	check(voice.playing and receiver.radio.stream_paused,"Exit fades room music before returning the radio")
	await create_timer(MUSIC.OUT_SECONDS+.15).timeout
	check(not voice.playing and not receiver.radio.stream_paused,"Exit completes the fade and releases radio ownership")
	check(receiver.radio_index==station and receiver.radio.get_playback_position()>=position-.05,"Radio returns with the same station and retained playback position")
	music.sync(true,receiver)
	music.sync(false,receiver)
	await create_timer(.1).timeout
	music.sync(true,receiver)
	await create_timer(.1).timeout
	check(music._voice==voice and voice.playing and receiver.radio.stream_paused,"Reentry reverses a pending fade without a duplicate or stale stop")
	music.free()
	check(not receiver.radio.stream_paused,"Free/load/menu cleanup immediately releases the radio override")
	var loaded := MUSIC.new()
	root.add_child(loaded)
	loaded.sync(true,receiver)
	check(loaded._active and loaded._voice.playing,"A restored session can acquire the room soundtrack after cleanup")
	loaded.shutdown()
	check(not loaded._voice.playing and not receiver.radio.stream_paused,"Explicit session shutdown stops the track and returns radio ownership")
	loaded.free(); world.free(); vehicle.free()
	print("DIGO_WORKSHOP_MUSIC checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
