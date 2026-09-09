extends RefCounted
## Non-verbal speech. One finite buffer per line, bounded cache, no per-frame synthesis.
const RATE := 22050
static var cache: Dictionary = {}

static func line(text: String, persona := "dante", duration := 0.0) -> AudioStreamWAV:
	var key := "%s|%s|%s" % [persona, duration, text]
	if cache.has(key):
		return cache[key]
	var units: Array[float] = []
	var voiced: Array[bool] = []
	for character in text.left(400):
		units.append(4.0 if character in ".!?;:" else (2.0 if character in ",—\n" else (0.65 if character == " " else 1.0)))
		voiced.append(not character in " .!?;:,—\n")
	var total := 0.0
	for unit in units: total += unit
	var seconds := clampf(duration if duration > 0 else total * 0.052, 0.3, 12.0)
	var samples := int(seconds * RATE)
	var pcm := PackedByteArray()
	pcm.resize(samples * 2)
	var envelope := PackedFloat32Array()
	envelope.resize(int(ceil(seconds * 100.0)) + 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var base := 148.0 if persona == "dante" else (106.0 if persona == "maciota" else 178.0)
	var cursor := 0
	for index in units.size():
		var end := mini(samples, cursor + int(samples * units[index] / maxf(total, 1.0)))
		var pitch := base * rng.randf_range(0.88, 1.12)
		var formant := rng.randf_range(2.3, 4.4)
		for i in range(cursor, end):
			if not voiced[index]: continue
			var age := float(i - cursor) / RATE
			var span := maxf(float(end - cursor) / RATE, 0.001)
			var amp := sin(PI * age / span)
			amp *= amp
			var fundamental := sin(TAU * pitch * age)
			var value := fundamental * 0.12 + sin(TAU * pitch * formant * age) * 0.04 + sin(TAU * pitch * 6.0 * age) * 0.012
			if persona == "caller":
				value = fundamental * 0.035 + sin(TAU * pitch * 3.0 * age) * 0.08
			pcm.encode_s16(i * 2, int(value * amp * 32767))
			envelope[mini(int(float(i) / RATE * 100), envelope.size() - 1)] = amp
		cursor = end
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = pcm
	stream.set_meta("speech_envelope", envelope)
	if cache.size() >= 32:
		cache.erase(cache.keys()[0])
	cache[key] = stream
	return stream

static func mouth(audio: AudioStreamPlayer) -> float:
	if not is_instance_valid(audio) or not audio.playing or audio.stream_paused:
		return 0.0
	var envelope: PackedFloat32Array = audio.stream.get_meta("speech_envelope", PackedFloat32Array())
	var index := int(audio.get_playback_position() * 100.0)
	return envelope[index] if index >= 0 and index < envelope.size() else 0.0
