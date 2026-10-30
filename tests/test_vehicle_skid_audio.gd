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
	# 30/10: volume_db carrega o envelope de ataque; o ganho pedido por voz fica em skid_target_db.
	check(first.skid_audio != second.skid_audio and first.skid_target_db != second.skid_target_db and first.skid_audio.pitch_scale != second.skid_audio.pitch_scale,"shared waveform keeps independent voices, gain and pitch")
	check(first.skid_audio.get_child_count() == 3 and first._skid_body.stream == TIRES._skid_layer_streams.body and first._skid_hiss.stream == TIRES._skid_layer_streams.hiss,"rubber body, scrub hiss and release tail hang under the one voice")
	check(first._skid_body.playing and first._skid_hiss.playing,"layers start with the squeal")
	first._update_skid_audio(false,0,0)
	check(not first.skid_audio.playing,"silence still stops the voice")
	# A cauda de 120 ms vive no _process, que nunca roda sem physics_tick recente: corta sozinha.
	for i in 30: await process_frame
	check(not first._skid_tail.playing and not first._skid_body.playing and not first._skid_hiss.playing,"release tail and layers fall silent")
	car.free()
	await process_frame
	print("VEHICLE_SKID_AUDIO checks=%d failures=%d" % [checks,failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
