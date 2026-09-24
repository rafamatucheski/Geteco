extends RefCounted
## Exact V1 ProceduralAudio fallback oscillators; the source has no horn/siren asset.
static var horn: AudioStreamWAV
static var siren: AudioStreamWAV
static var alarm: AudioStreamWAV

static func horn_stream() -> AudioStreamWAV:
	if horn: return horn
	var data := PackedByteArray()
	data.resize(8820 * 2)
	for i in 8820:
		var t := float(i) / 22050.0
		var env := 1.0
		if t < .03: env = t / .03
		elif t > .35: env = (.4 - t) / .05
		var sample := (sin(TAU * 435 * t) * .5 + sin(TAU * 545 * t) * .5) * env * .4
		data.encode_s16(i * 2, clampi(int(sample * 32767), -32768, 32767))
	horn = _stream(data)
	return horn

static func siren_stream() -> AudioStreamWAV:
	if siren: return siren
	var data := PackedByteArray()
	data.resize(66150 * 2)
	var phase := 0.0
	for i in 66150:
		var t := float(i) / 22050.0
		var frequency := 650 + 500 * (.5 - .5 * cos(TAU * t / 3.0))
		var tone := sin(phase) + sin(phase * 2) * .10 + sin(phase * 3) * .04
		phase += TAU * frequency / 22050.0
		data.encode_s16(i * 2, clampi(int(tanh(tone * .75) * .55 * 32767), -32768, 32767))
	siren = _stream(data)
	siren.loop_mode = AudioStreamWAV.LOOP_FORWARD
	siren.loop_end = 66150
	return siren

## V1 `ProceduralAudio._generate_police_alarm_stream`: 880/1320 Hz alternando a
## cada 0,4 s. Os 0,8 s fecham ciclos inteiros das duas portadoras e o crossfade
## é um tanh de seno, então o laço não estala na emenda.
static func alarm_stream() -> AudioStreamWAV:
	if alarm: return alarm
	var samples := 17640
	var data := PackedByteArray()
	data.resize(samples * 2)
	var phase_a := 0.0
	var phase_b := 0.0
	for i in samples:
		var t := float(i) / 22050.0
		var tone_a := sin(phase_a) + sin(phase_a * 2) * .08
		var tone_b := sin(phase_b) + sin(phase_b * 2) * .08
		phase_a += TAU * 880 / 22050.0
		phase_b += TAU * 1320 / 22050.0
		var blend := .5 + .5 * tanh(12 * sin(TAU * t / .4))
		data.encode_s16(i * 2, clampi(int((tone_a * blend + tone_b * (1 - blend)) * .38 * 32767), -32768, 32767))
	alarm = _stream(data)
	alarm.loop_mode = AudioStreamWAV.LOOP_FORWARD
	alarm.loop_end = samples
	return alarm

static func _stream(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.data = data
	return stream
