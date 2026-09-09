extends SceneTree
## Exporta WAVs "antes/depois" para audição manual das mudanças em
## ProceduralAudio.gd (sirene, alarme, conquista), mais os 3 sons novos de
## BearAudio.gd.
##
## Rodar (headless) com:
##   "D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" ^
##     --headless --path "D:/geteco/game" --script res://audio/review_0908/capture_audio_comparison.gd
##
## Os arquivos "*_before.wav" replicam byte-a-byte o algoritmo que existia
## em ProceduralAudio.gd antes desta revisão -- servem só para audição
## comparativa, não fazem parte do jogo e não são referenciados por nenhum
## consumidor.

const BEAR := preload("res://audio/review_0908/BearAudio.gd")
const SAMPLE_RATE := 22050
const OUT_DIR := "D:/geteco/game/audio/review_0908/"

func _initialize() -> void:
	call_deferred("run")

func _make_wav(data: PackedByteArray, loop: bool, num_samples: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = num_samples
	stream.data = data
	return stream

# --- Réplicas do algoritmo ANTERIOR (só para audição comparativa) ---------

func _siren_before() -> AudioStreamWAV:
	var duration := 1.2
	var num_samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(SAMPLE_RATE)
		var freq := 650.0 + (sin(2.0 * PI * (1.0 / duration) * t) + 1.0) * 0.5 * 500.0
		var sample := sin(2.0 * PI * freq * t) * 0.35
		data.encode_s16(i * 2, clampi(int(sample * 32767.0), -32768, 32767))
	return _make_wav(data, true, num_samples)

func _alarm_before() -> AudioStreamWAV:
	var duration := 0.75
	var num_samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(SAMPLE_RATE)
		var phase := int(t * 6.0) % 2
		var freq := 880.0 if phase == 0 else 1380.0
		var sample := sin(2.0 * PI * freq * t) * 0.40
		sample += sin(4.0 * PI * freq * t) * 0.15
		data.encode_s16(i * 2, clampi(int(sample * 32767.0), -32768, 32767))
	return _make_wav(data, true, num_samples)

func _achievement_before() -> AudioStreamWAV:
	var duration := 2.4
	var num_samples := int(SAMPLE_RATE * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / float(SAMPLE_RATE)
		var freq := 261.63
		if t >= 0.35 and t < 0.70: freq = 329.63
		elif t >= 0.70 and t < 1.05: freq = 392.00
		elif t >= 1.05: freq = 523.25
		var env := exp(-fmod(t, 0.35) * 4.0) if t < 1.05 else exp(-(t - 1.05) * 1.5)
		var brass := (sin(2.0 * PI * freq * t) + 0.5 * sin(4.0 * PI * freq * t) + 0.25 * sin(6.0 * PI * freq * t)) * 0.35 * env
		var bass := sin(2.0 * PI * (freq * 0.5) * t) * 0.25 * env
		data.encode_s16(i * 2, clampi(int((brass + bass) * 32767.0), -32768, 32767))
	return _make_wav(data, false, num_samples)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var results := {}

	results["siren_before.wav"] = _siren_before().save_to_wav(OUT_DIR + "siren_before.wav")
	results["siren_after.wav"] = (ProceduralAudio.get_siren_stream() as AudioStreamWAV).save_to_wav(OUT_DIR + "siren_after.wav")

	results["police_alarm_before.wav"] = _alarm_before().save_to_wav(OUT_DIR + "police_alarm_before.wav")
	results["police_alarm_after.wav"] = (ProceduralAudio.get_police_alarm_stream() as AudioStreamWAV).save_to_wav(OUT_DIR + "police_alarm_after.wav")

	results["achievement_before.wav"] = _achievement_before().save_to_wav(OUT_DIR + "achievement_before.wav")
	results["achievement_after.wav"] = (ProceduralAudio.get_mission_passed_stream() as AudioStreamWAV).save_to_wav(OUT_DIR + "achievement_after.wav")

	results["bear_breathing.wav"] = (BEAR.get_breathing_stream() as AudioStreamWAV).save_to_wav(OUT_DIR + "bear_breathing.wav")
	results["bear_grunt_alert.wav"] = (BEAR.get_grunt_alert_stream() as AudioStreamWAV).save_to_wav(OUT_DIR + "bear_grunt_alert.wav")
	results["bear_charge.wav"] = (BEAR.get_charge_stream() as AudioStreamWAV).save_to_wav(OUT_DIR + "bear_charge.wav")

	var all_ok := true
	for file_name in results.keys():
		var err = results[file_name]
		print("SAVE ", file_name, " -> ", err, (" (OK)" if err == OK else " (FAIL)"))
		all_ok = all_ok and err == OK

	print("AUDIO_COMPARISON_CAPTURE all_ok=", all_ok)
	quit(0 if all_ok else 1)
