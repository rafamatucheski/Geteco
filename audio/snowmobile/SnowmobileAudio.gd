extends RefCounted
## Esteira do snowmobile: um laço pronto (generate_snowmobile_audio.py) com pitch e volume pela velocidade.
## O motor de dois tempos é um banco comum de 7 faixas (`engine_snowmobile_*` em audio/acoustic), servido
## pelo EngineBankCache como qualquer família.
const TRACK_PATH := "res://audio/snowmobile/track.wav"
static var _track: AudioStreamWAV

static func track_stream() -> AudioStreamWAV:
	if _track != null: return _track
	var source: AudioStreamWAV
	if ResourceLoader.exists(TRACK_PATH, "AudioStreamWAV"):
		source = ResourceLoader.load(TRACK_PATH, "AudioStreamWAV") as AudioStreamWAV
	elif FileAccess.file_exists(TRACK_PATH):
		# Checkout recém-clonado antes da importação; o export usa o recurso acima.
		source = AudioStreamWAV.load_from_file(TRACK_PATH)
	if source == null:
		push_error("SnowmobileAudio: falta o som da esteira %s" % TRACK_PATH)
		return null
	_track = source.duplicate() as AudioStreamWAV
	_track.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_track.loop_begin = 0
	_track.loop_end = preload("res://audio/tank/TankAudio.gd").frame_count(_track)
	return _track

## Parado é silêncio, mesmo acelerando em ponto morto; igual em ré.
static func track_gain(speed: float) -> float:
	return smoothstep(0.15, 1.6, absf(speed)) * lerpf(0.4, 1.0, clampf(absf(speed) / 16.0, 0.0, 1.0))

static func track_pitch(speed: float) -> float:
	return clampf(0.45 + absf(speed) * 0.06, 0.45, 2.4)
