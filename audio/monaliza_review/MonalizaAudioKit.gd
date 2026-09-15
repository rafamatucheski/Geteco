class_name MonalizaAudioKit
extends RefCounted
## Original RB26-inspired inline-six. Live engine uses VehicleEngineSound layers.
const ENGINE := preload("res://audio/VehicleEngineSound.gd")
const SAMPLE_RATE := ENGINE.RATE
const ENGINE_DURATION := float(ENGINE.LOOP_SECONDS)
const TURBO_SPOOL_DURATION := 4.0
const TURBO_RELEASE_DURATION := 0.38
const TURBO_SHIFT_DURATION := 0.32
const IGNITION_DURATION := 1.3
const DEMO_DURATION := 8.0

static func generate_engine_stream() -> AudioStreamWAV:
	return ENGINE.get_layer_streams("monaliza", "monaliza")[0]

static func _to_wav(samples: PackedFloat32Array, loop: bool, peak: float) -> AudioStreamWAV:
	var n := samples.size()
	ENGINE._highpass(samples, 35.0)
	var measured := 0.0001
	for value in samples: measured = maxf(measured, absf(value))
	var data := PackedByteArray()
	data.resize((n + ENGINE.GUARD if loop else n) * 2)
	for i in n:
		var gain := peak / measured
		if not loop:
			# Both ends reach exact zero, including the pressure release tail.
			gain *= smoothstep(0.0, 0.015, float(i) / SAMPLE_RATE)
			gain *= smoothstep(0.0, 0.075, float(n - 1 - i) / SAMPLE_RATE)
		data.encode_s16(i * 2, int(clampf(samples[i] * gain, -0.95, 0.95) * 32767.0))
	if loop:
		for i in ENGINE.GUARD: data.encode_s16((n + i) * 2, data.decode_s16(i * 2))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = n
	return wav

static func generate_turbo_spool_stream() -> AudioStreamWAV:
	# Broad airflow replaces the old 1200/1215 Hz beating whistles.
	var n := int(SAMPLE_RATE * TURBO_SPOOL_DURATION)
	var air := ENGINE._circular_noise(n, 650.0, 0.55, 815)
	var body := ENGINE._circular_noise(n, 230.0, 0.7, 816)
	for i in n: air[i] = air[i] * 0.65 + body[i] * 0.35
	return _to_wav(air, true, 0.22)

static func generate_turbo_release_stream() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * TURBO_RELEASE_DURATION)
	var air := ENGINE._circular_noise(n, 820.0, 0.6, 817)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		air[i] *= smoothstep(0.0, 0.025, t) * exp(-t * 11.0)
	return _to_wav(air, false, 0.32)

static func generate_turbo_shift_stream() -> AudioStreamWAV:
	# Three short, decaying airflow pulses after engagement. Broad resonances
	# give the flutter body without bringing back the continuous turbo whistle.
	var n := int(SAMPLE_RATE * TURBO_SHIFT_DURATION)
	var air := ENGINE._circular_noise(n, 1350.0, 0.9, 819)
	var body := ENGINE._circular_noise(n, 520.0, 1.0, 820)
	var starts := [0.012, 0.095, 0.192]
	var widths := [0.054, 0.065, 0.082]
	var levels := [1.0, 0.62, 0.34]
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var envelope := 0.0
		for pulse in starts.size():
			var phase: float = (t - starts[pulse]) / widths[pulse]
			if phase > 0.0 and phase < 1.0:
				envelope += pow(sin(PI * phase), 2.0) * levels[pulse]
		var decay := t / TURBO_SHIFT_DURATION
		air[i] = (air[i] * (1.0 - decay * 0.55) + body[i] * (0.45 + decay * 0.45)) * envelope
	return _to_wav(air, false, 0.52)

static func _read_loop(wav: AudioStreamWAV, frame: float) -> float:
	var count := wav.loop_end if wav.loop_end > 0 else wav.data.size() / 2
	var index := int(frame) % count
	var a := float(wav.data.decode_s16(index * 2)) / 32768.0
	var b := float(wav.data.decode_s16(((index + 1) % count) * 2)) / 32768.0
	return lerpf(a, b, fposmod(frame, 1.0))

static func generate_ignition_stream() -> AudioStreamWAV:
	var n := int(SAMPLE_RATE * IGNITION_DURATION)
	var samples := ENGINE._circular_noise(n, 310.0, 0.8, 818)
	var idle := generate_engine_stream()
	var frame := 0.0
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var catch := smoothstep(0.35, 0.62, t)
		var crank := (sin(TAU * 135.0 * t) * 0.15 + samples[i] * 0.35)
		crank *= 0.5 + 0.5 * sin(TAU * 8.0 * t)
		frame += lerpf(1.7, 0.94, smoothstep(0.5, 1.1, t))
		samples[i] = crank * (1.0 - catch) + _read_loop(idle, frame) * catch * 0.55
	return _to_wav(samples, false, 0.45)

static func generate_demo_stream() -> AudioStreamWAV:
	# Offline audition; the live mixer capture is the integration evidence.
	var layers := ENGINE.get_layer_streams("monaliza", "monaliza")
	var profile: Dictionary = ENGINE._profile("monaliza")
	var nominal: Array = profile.cycles
	var positions := PackedFloat64Array()
	positions.resize(layers.size())
	var smooth_cycles := 7.5
	var ignition := generate_ignition_stream()
	var release := generate_turbo_release_stream()
	var samples := PackedFloat32Array()
	samples.resize(int(SAMPLE_RATE * DEMO_DURATION))
	for i in samples.size():
		var t := float(i) / SAMPLE_RATE
		var cycles := 7.5
		if t >= 1.0 and t < 5.8:
			cycles = lerpf(22.0, 62.0, fposmod((t - 1.0) / 1.6, 1.0))
		elif t >= 5.8: cycles = lerpf(60.0, 7.5, smoothstep(5.8, 7.6, t))
		smooth_cycles = lerpf(smooth_cycles, cycles, 1.0 - exp(-12.0 / SAMPLE_RATE))
		cycles = smooth_cycles
		var total := 0.0
		var value := 0.0
		for layer in layers.size():
			positions[layer] += cycles / float(nominal[layer])
			var distance := log(cycles / float(nominal[layer])) / log(float(profile.get("layer_spread", 2.0)))
			if layer == 0 and distance < 0.0: distance = 0.0
			var weight := maxf(0.0, 1.0 - absf(distance))
			value += _read_loop(layers[layer], positions[layer]) * weight
			total += weight
		value = value / maxf(total, 0.001) * smoothstep(0.5, 1.3, t) * 0.7
		if i < ignition.data.size() / 2:
			value += float(ignition.data.decode_s16(i * 2)) / 32768.0 * 0.6
		var release_i := i - int(5.8 * SAMPLE_RATE)
		if release_i >= 0 and release_i < release.data.size() / 2:
			value += float(release.data.decode_s16(release_i * 2)) / 32768.0 * 0.18
		samples[i] = value * (1.0 - smoothstep(7.5, 8.0, t))
	return _to_wav(samples, false, 0.65)
