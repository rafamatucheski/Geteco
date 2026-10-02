extends SceneTree
const TIRES := preload("res://gameplay/vehicle_effects/VehicleTireEffects.gd")
class Car extends CharacterBody3D:
	var archetype := ""
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func run() -> void:
	var snapshots := {}
	for kind in TIRES.SKID_SOURCES:
		var source: AudioStreamWAV = TIRES.SKID_SOURCES[kind]
		snapshots[kind] = {"data":source.data, "mode":source.loop_mode, "end":source.loop_end}
	TIRES.prewarm_skid_audio()
	var cache := TIRES._skid_streams.duplicate()
	TIRES.prewarm_skid_audio()
	check(cache == TIRES._skid_streams,"repeat warmup preserves the five loop resources")
	for kind in cache:
		var source: AudioStreamWAV = TIRES.SKID_SOURCES[kind]
		var stream: AudioStreamWAV = cache[kind]
		check(stream.data == snapshots[kind].data and stream.get_length()>0,"original waveform preserved: "+kind)
		check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end == maxi(1,roundi(stream.get_length()*stream.mix_rate)-8),"original loop boundary preserved: "+kind)
		check(source.loop_mode == snapshots[kind].mode and source.loop_end == snapshots[kind].end,"source resource remains unmodified: "+kind)
	var car := Car.new()
	root.add_child(car)
	var first := TIRES.new()
	first.configure(car)
	car.add_child(first)
	first._update_skid_audio(true,16.25,11.25)
	var second := TIRES.new()
	second.configure(car)
	car.add_child(second)
	second._update_skid_audio(true,1.0,1.0)
	check(first.skid_audio.stream == cache.street and second.skid_audio.stream == cache.street,"vehicles use already prepared audio")
	check(first.skid_audio != second.skid_audio and first.skid_audio.volume_db != second.skid_audio.volume_db and first.skid_audio.pitch_scale != second.skid_audio.pitch_scale,"shared waveform keeps independent voices, gain and pitch")
	first._update_skid_audio(false,0,0)
	check(not first.skid_audio.playing,"silence still stops the voice")
	car.free()
	await process_frame
	print("VEHICLE_SKID_AUDIO checks=%d failures=%d" % [checks,failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
