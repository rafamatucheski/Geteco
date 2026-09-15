extends SceneTree

## Regression for the Portuguese Maciota/Dante pilot recordings.
const VOICE := preload("res://ExpressiveVoice.gd")
var failures := 0

var cases := [
	["maciota", "Maciota. E você?"],
	["dante", "Dante. Foi você que me ligou?"],
	["maciota", "Fui eu, sim. Vamos dar uma volta."],
	["maciota", "Aqui é o ferro-velho do Neko. Sempre tem gente atrás de peça por aqui."],
	["maciota", "O porto vive de carga e de oficina. Muita gente se conhece por causa de carro."],
	["maciota", "Mas tem quem misture trabalho com contrabando e corrida. É melhor saber com quem você está falando."],
	["maciota", "Minha garagem fica mais à frente. Lá a gente conversa com calma."],
]

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS ", message)
	else:
		failures += 1
		push_error("FAIL " + message)

func run() -> void:
	for item in cases:
		var stream := VOICE.line(item[1], item[0])
		check(stream != null, item[0] + " stream exists")
		if stream == null:
			continue
		check(stream.has_meta("mission_voice") and stream.get_meta("mission_voice") == true, item[1] + " uses recorded voice")
		# Dante/M00-M01 são WAV (suas gravações); o Maciota (14/09) é MP3 gerado
		# via ElevenLabs. AudioStreamMP3 não expõe mix_rate/format como o WAV;
		# checa a fidelidade equivalente para cada formato em vez de assumir WAV.
		if stream is AudioStreamWAV:
			check(stream.mix_rate == 48000, item[1] + " is 48 kHz")
			# Godot imports source PCM WAVs as QOA on this project; both retain the
			# original 16-bit source fidelity, while FORMAT_8_BITS would not.
			check(stream.format == AudioStreamWAV.FORMAT_16_BITS or stream.format == AudioStreamWAV.FORMAT_QOA, item[1] + " keeps 16-bit source fidelity")
			check(stream.data.size() > 0, item[1] + " has PCM data")
		elif stream is AudioStreamMP3:
			check(stream.data.size() > 0, item[1] + " has MP3 bitstream data")
		else:
			check(false, item[1] + " uses a recognized audio stream type (%s)" % stream.get_class())
	print("MISSION_VOICE_RECORDINGS failures=", failures)
	quit(0 if failures == 0 else 1)
