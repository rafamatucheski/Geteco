extends "res://tests/test_medical_choreography_continuity.gd"
var audio_errors: Dictionary = {}
var saw_outbound_siren := false
var saw_transport_siren := false
var saw_hospital_silence := false
var checked_waveform := false

func run() -> void:
	physics_frame.connect(_observe_response_audio)
	await super.run()

func _observe_response_audio() -> void:
	for unit in get_nodes_in_group("emergency_vehicle"):
		if unit.type != 1 or not unit.visible: continue
		var sequence: Node = unit.get_meta("medical_sequence") if unit.has_meta("medical_sequence") else null
		if not checked_waveform:
			checked_waveform = true
			var stream: AudioStreamWAV = unit.siren_audio.stream
			check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "The siren is a continuous audio loop")
			check(unit.siren_audio.volume_db >= -12.0 and unit.siren_audio.max_distance >= 1000.0, "Response sirens remain audible across the visible street")
			var energy := 0.0
			var peak := 0.0
			for sample in stream.data.size() / 2:
				var value := float(stream.data.decode_s16(sample * 2)) / 32768.0
				energy += value * value
				peak = maxf(peak, absf(value))
			var rms := sqrt(energy / float(stream.data.size() / 2))
			check(rms > .1 and peak < .99, "The siren waveform contains audible signal with clipping headroom")
			print("AMBULANCE_SIREN source_rms_db=",linear_to_db(rms)," nominal_rms_db=",linear_to_db(rms)+unit.siren_audio.volume_db," gain_db=",unit.siren_audio.volume_db," range=",unit.siren_audio.max_distance)
		if not is_instance_valid(sequence):
			if is_instance_valid(unit.target) and not unit.is_acting and not unit.is_returning_to_base and unit.siren_audio.playing:
				saw_outbound_siren = true
			continue
		if sequence.phase_time < .2: continue
		if sequence.phase == "transport" and unit.is_returning_to_base:
			saw_transport_siren = true
			if not unit.siren_audio.playing or not unit.lights.visible:
				audio_errors["Loaded hospital transport keeps the siren and warning lights on"] = true
		elif unit.is_acting:
			if unit.siren_audio.playing:
				audio_errors["The siren stops while the crew treats or unloads the patient"] = true
			if sequence.hospital_delivery: saw_hospital_silence = true

func check(ok: bool, label: String) -> void:
	if label.begins_with("Parked ambulance survives"):
		super.check(saw_outbound_siren, "The dispatched ambulance sounds its siren en route to the patient")
		super.check(saw_transport_siren, "The real return route exercised loaded ambulance audio")
		super.check(saw_hospital_silence, "Hospital admission silences the siren while the crew works")
		for issue in audio_errors: super.check(false, str(issue))
		for unit in get_nodes_in_group("emergency_vehicle"):
			if unit.get_meta("hospital_available", false):
				super.check(not unit.siren_audio.playing and not unit.lights.visible, "A parked ambulance has no siren or flashing warning lights")
		print("AMBULANCE_AUDIO lifecycle_errors=",audio_errors.size())
	super.check(ok, label)
