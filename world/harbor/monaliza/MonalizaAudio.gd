extends RefCounted
## Original fallback PCM; optional isolated Claude WAVs replace these on load.
static var cache := {}
static func stream(kind: String) -> AudioStream:
	if cache.has(kind): return cache[kind]
	var path := "res://audio/monaliza_review/"+kind+".wav"
	if FileAccess.file_exists(path):
		var wav := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
		if wav != null:
			# WAV exports do not retain Godot loop metadata.
			if kind in ["engine","turbo_spool"]:
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_begin = 0
				wav.loop_end = int(wav.get_length()*wav.mix_rate)
			cache[kind] = wav
			return wav
	var rate := 22050
	var duration := 1.0 if kind != "turbo_release" else 0.55
	var count := int(rate*duration)
	var bytes := PackedByteArray()
	bytes.resize(count*2)
	var random := RandomNumberGenerator.new()
	random.seed = 815
	var smooth_noise := 0.0
	for i in count:
		var t := float(i)/rate
		var sample := 0.0
		if kind == "engine":
			sample = (sin(TAU*62*t)+0.4*sin(TAU*124*t)+0.18*sin(TAU*248*t))*0.24
		elif kind == "turbo_spool":
			sample = (sin(TAU*1100*t)+0.25*sin(TAU*2200*t))*0.16
		else:
			smooth_noise = lerpf(smooth_noise,random.randf_range(-1,1),0.65)
			var envelope := minf(t/0.02,1)*pow(1-t/duration,2)
			sample = (smooth_noise*0.8+sin(TAU*(1400*t-700*t*t))*0.15)*envelope*0.7
		bytes.encode_s16(i*2,int(clampf(sample,-0.95,0.95)*32767))
	var result := AudioStreamWAV.new()
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.mix_rate = rate
	result.data = bytes
	if kind in ["engine","turbo_spool"]:
		result.loop_mode = AudioStreamWAV.LOOP_FORWARD
		result.loop_end = count
	cache[kind] = result
	return result
