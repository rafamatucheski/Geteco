extends SceneTree
const BANKS := preload("res://audio/EngineBankCache.gd")
const PROFILE := preload("res://audio/VehicleEngineProfile.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
class AudioCar extends CharacterBody3D:
	var archetype := "union_sedan"
	var speed := 0.0
class Foreground extends "res://audio/WorldAudio.gd":
	func _ready() -> void:
		set_process(false)
		for i in 7:
			var voice := AudioStreamPlayer.new()
			add_child(voice)
			layers.append(voice)
		road_audio = AudioStreamPlayer.new()
		shift_audio = AudioStreamPlayer.new()
		air_brake_audio = AudioStreamPlayer.new()
		for voice in [road_audio, shift_audio, air_brake_audio]: add_child(voice)
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	await BANKS.prewarm(self)
	var host := Node3D.new()
	root.add_child(host)
	var car := AudioCar.new()
	host.add_child(car)
	var first := Foreground.new()
	var second := Foreground.new()
	host.add_child(first)
	host.add_child(second)
	var selected: Dictionary = {}
	for archetype in FLEET.all():
		var family := PROFILE.bank_family(archetype)
		if family in ["street", "police", "electric", "tank"] and not selected.has(family): selected[family] = archetype
	check(selected.size() == 4, "real catalogue supplies street, police, electric and tank cases")
	for family: String in selected:
		car.archetype = selected[family]
		var bank := BANKS.bank(family)
		check(bank.size() == 7, "prepared real bank has seven bands: " + family)
		first._sync_engine_family(car)
		second._sync_engine_family(car)
		check(first.family == family and second.family == family, "foreground preserves real family selection: " + family)
		for i in 7:
			var stream: AudioStreamWAV = first.layers[i].stream
			check(is_same(stream, bank[i]) and is_same(second.layers[i].stream, bank[i]), "both foregrounds reuse prepared band %s/%d" % [family, i])
			check(stream.get_length() > 0 and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "prepared band remains reproducible and looping %s/%d" % [family, i])
			if family != "tank":
				var source: AudioStreamWAV = load("res://audio/acoustic/engine_%s_%d.wav" % [family, i])
				check(stream.get_data() == source.get_data() and stream.mix_rate == source.mix_rate and stream.stereo == source.stereo and stream.format == source.format, "authored PCM and format preserved %s/%d" % [family, i])
				check(stream.loop_end == maxi(1, roundi(stream.get_length() * stream.mix_rate) - 8), "existing loop boundary preserved %s/%d" % [family, i])
		first.layers[0].pitch_scale = .8
		second.layers[0].pitch_scale = 1.2
		first.layers[0].volume_db = -18
		second.layers[0].volume_db = -6
		check(is_equal_approx(first.layers[0].pitch_scale, .8) and is_equal_approx(second.layers[0].pitch_scale, 1.2) and is_equal_approx(first.layers[0].volume_db, -18) and is_equal_approx(second.layers[0].volume_db, -6), "shared resources preserve independent voice controls: " + family)
		first._sync_engine_family(car)
		check(is_same(first.layers[0].stream, bank[0]), "repeated selection preserves prepared stream: " + family)
	host.free()
	await process_frame
	await create_timer(.1).timeout
	print("FOREGROUND_ENGINE_CACHE checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
