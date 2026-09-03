class_name CoastalWaveAudio
extends AudioStreamPlayer2D

## Infinite procedural surf. AudioStreamGenerator avoids adding a large WAV
## asset and keeps the coast self-contained.

const MIX_RATE := 22050.0

var _playback: AudioStreamGeneratorPlayback
var _sample_clock := 0.0
var _noise_state: int = 0x13579B
var _low_noise := 0.0


func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = 0.45
	stream = generator
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback
	_fill_buffer()


func _process(_delta: float) -> void:
	_fill_buffer()


func _fill_buffer() -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	for _frame in frames:
		_noise_state = int((_noise_state * 1103515245 + 12345) & 0x7fffffff)
		var white := (float(_noise_state) / 1073741824.0) - 1.0
		_low_noise = lerpf(_low_noise, white, 0.012)
		var swell := 0.54 + 0.46 * sin(TAU * 0.105 * _sample_clock)
		var foam := white * (0.018 + 0.035 * swell)
		var surf := _low_noise * (0.20 + 0.15 * swell)
		var distant_break := sin(TAU * 0.34 * _sample_clock) * 0.012 * swell
		var sample := clampf(surf + foam + distant_break, -0.38, 0.38)
		_playback.push_frame(Vector2(sample, sample * 0.96))
		_sample_clock += 1.0 / MIX_RATE
