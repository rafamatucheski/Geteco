extends RefCounted
## Original, locally synthesized feline calls and a soft adoption confirmation.
## Streams are shared and created once; callers use positional AudioStreamPlayer3D.

const RATE := 22050
static var _meows: Dictionary = {}
static var _collect: AudioStreamWAV


static func make_meow(index: int = 0) -> AudioStreamWAV:
	var variant := posmod(index, 4)
	if _meows.has(variant):
		return _meows[variant]
	var duration := 0.58 + float(variant) * 0.042
	var count := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 87212 + variant
	var noise := 0.0
	for n in range(count):
		var time := float(n) / RATE
		var progress := time / duration
		# Rising "mi" then a rounded falling "aow", including small vocal vibrato.
		var pitch := (510.0 + float(variant) * 29.0) * (0.79 + 0.38 * sin(progress * PI))
		pitch *= 1.0 + 0.014 * sin(time * 43.0)
		phase += TAU * pitch / RATE
		var attack := smoothstep(0.0, 0.065, time)
		var release := pow(maxf(0.0, 1.0 - progress), 0.52) * smoothstep(0.0, 0.12, duration - time)
		var mouth := smoothstep(0.10, 0.37, progress) * (1.0 - smoothstep(0.62, 0.98, progress))
		var vowel := sin(phase) * 0.47 + sin(phase * 2.0 + 0.3) * 0.17
		vowel += sin(phase * 3.0) * (0.055 + mouth * 0.19)
		vowel += sin(phase * 4.0 + 0.16) * (0.025 + mouth * 0.09)
		noise = lerpf(noise, rng.randf_range(-1.0, 1.0), 0.22)
		var sample := tanh((vowel + noise * 0.025) * 1.1) * attack * release * 0.65
		data.encode_s16(n * 2, clampi(int(sample * 32767.0), -32768, 32767))
	var stream := _stream(data)
	_meows[variant] = stream
	return stream


static func make_collect() -> AudioStreamWAV:
	if _collect != null:
		return _collect
	var duration := 0.46
	var count := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for n in range(count):
		var time := float(n) / RATE
		var sample := 0.0
		for note in range(3):
			var t := time - float(note) * 0.083
			if t < 0.0:
				continue
			var frequency := [659.25, 830.61, 987.77][note] as float
			var envelope := (1.0 - exp(-t * 180.0)) * exp(-t * 13.0)
			sample += (sin(TAU * frequency * t) + sin(TAU * frequency * 2.01 * t) * 0.13) * envelope * 0.20
		data.encode_s16(n * 2, clampi(int(sample * 32767.0), -32768, 32767))
	_collect = _stream(data)
	return _collect


static func _stream(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream
