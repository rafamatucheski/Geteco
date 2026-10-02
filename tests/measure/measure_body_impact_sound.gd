extends "res://tests/measure/measure_body_impacts.gd"
## Same real Main scene / vehicle sweeps as the body benchmark, with two audio
## recordings. Recording overhead makes this diagnostic unsuitable as an FPS run.
const BODY_AUDIO := preload("res://audio/VehicleCrashAudio.gd")
var master_record: AudioEffectRecord
var contact_record: AudioEffectRecord
var contact_pool: Node3D
var recording_started := 0
var heard: Array[Dictionary] = []
var last_voice: Dictionary = {}

func run() -> void:
	await super.run()
	if not is_instance_valid(world) or not world.session.ready_for_play: return
	contact_pool = BODY_AUDIO.pool(world.driving.car)
	if contact_pool == null:
		push_error("Body audio capture could not locate the shared contact pool")
		quit(1)
		return
	master_record = AudioEffectRecord.new()
	master_record.format = AudioStreamWAV.FORMAT_16_BITS
	contact_record = AudioEffectRecord.new()
	contact_record.format = AudioStreamWAV.FORMAT_16_BITS
	# Append after existing effects: the contact recording includes its limiter,
	# and Master includes the actual engine/city/SFX mix without muting anything.
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), master_record)
	AudioServer.add_bus_effect(AudioServer.get_bus_index(contact_pool.bus_name), contact_record)
	master_record.set_recording_active(true)
	contact_record.set_recording_active(true)
	recording_started = Time.get_ticks_usec()

func _process(delta: float) -> bool:
	if recording_started != 0 and is_instance_valid(contact_pool):
		for index in contact_pool.voices.size():
			var voice: AudioStreamPlayer3D = contact_pool.voices[index]
			var path := voice.stream.resource_path if voice.playing and voice.stream != null else ""
			if path != str(last_voice.get(index, "")) and path.contains("/body_impacts/"):
				heard.append({"seconds":float(Time.get_ticks_usec()-recording_started)/1000000.0,
					"clip":path,"gain_db":voice.volume_db,"point":str(voice.global_position),
					"victim_flying":is_instance_valid(victim) and victim.has_meta("street_flying"),
					"dismount_active":world.driving.is_body_transition_active()})
			last_voice[index] = path
	return super._process(delta)

func finish() -> void:
	var output_dir := evidence_dir if not evidence_dir.is_empty() else "res://evidence"
	if master_record == null or contact_record == null:
		push_error("Body audio capture did not start")
		quit(1)
		return
	master_record.set_recording_active(false)
	contact_record.set_recording_active(false)
	recording_started = 0
	var master_path := output_dir.path_join(label+"-master.wav")
	var contact_path := output_dir.path_join(label+"-contacts.wav")
	var master_error := master_record.get_recording().save_to_wav(master_path)
	var contact_error := contact_record.get_recording().save_to_wav(contact_path)
	var hits := 0
	var landings := 0
	for event in heard:
		if str(event.clip).contains("body_hit_"): hits += 1
		if str(event.clip).contains("body_land_"): landings += 1
	var report := {"master":master_path,"contacts":contact_path,"events":heard,
		"hits":hits,"landings":landings,"launched":launched,"completed":completed,
		"master_muted":AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")),
		"master_db":AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")),
		"sfx_muted":AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")),
		"sfx_db":AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")),
		"notes":"Rendered Main scene with live directors and real vehicle sweeps. PCM files require level analysis/listening; emission counts alone do not prove audibility. Diagnostic recording overhead is included in any frame metrics."}
	var file := FileAccess.open(output_dir.path_join(label+"-audio.json"),FileAccess.WRITE)
	if file == null or master_error != OK or contact_error != OK:
		push_error("Failed to save body impact audio evidence")
		quit(1)
		return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("BODY_IMPACT_SOUND hits=",hits," landings=",landings," launched=",launched," completed=",completed)
	if hits == 0 or landings == 0 or launched == 0 or completed == 0:
		push_error("Body audio scenario did not cover an actual vehicle hit and completed landing")
		quit(1)
		return
	await super.finish()
