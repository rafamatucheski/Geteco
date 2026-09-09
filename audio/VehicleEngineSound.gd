extends RefCounted

## Shared engine response for both vehicle controllers. Streams are cached per
## engine family (or vehicle-id override when available); RPM follows throttle/load
## and simulated gears, not just speed.
static var _streams: Dictionary = {}
var rpm := 0.0
var load_amount := 0.0
var gear := 1
var shift_remaining := 0.0
var shift_cooldown := 0.0

## Topo de cada marcha em fração da velocidade máxima de rua. Substitui a grade
## uniforme de 0.19 por marcha: a primeira estica até 30% da máxima e a última
## cobre os 20% finais, então o giro sobe ao longo de muito mais velocidade em
## vez de estourar a poucos metros da largada.
const _GEAR_TOPS := [0.30, 0.48, 0.64, 0.80, 1.0]
## Folga abaixo do ponto de troca antes de reduzir: evita subir e descer marcha
## em loop quando a velocidade fica cruzando o limiar.
const _DOWNSHIFT_MARGIN := 0.05

static func road_top_speed(authored_speed: float) -> float:
	return authored_speed * 0.8

static func _gear_top(gear_index: int) -> float:
	return float(_GEAR_TOPS[clampi(gear_index, 1, _GEAR_TOPS.size()) - 1])

static func _gear_bottom(gear_index: int) -> float:
	if gear_index <= 1:
		return 0.0
	return float(_GEAR_TOPS[clampi(gear_index, 2, _GEAR_TOPS.size()) - 2])

func drive_force(speed: float, top_speed: float) -> float:
	var ratio := clampf(speed / maxf(road_top_speed(top_speed), 1.0), 0.0, 1.0)
	return 0.35 * lerpf(1.0, 0.45, ratio) * (0.3 if shift_remaining > 0.0 else 1.0)
var _stream_cache_key := ""

const _VEHICLE_AUDIO_DIR := "res://audio/vehicle"
const _AUDIO_DIR := "res://audio"

static func _cache_key(vehicle_id: String, family: String) -> String:
	var normalized_family := _normalize_family(family)
	if not vehicle_id.is_empty():
		return "%s:%s" % [vehicle_id, normalized_family]
	return "#:%s" % normalized_family

static func _normalize_family(value: String) -> String:
	var family := String(value).strip_edges().to_lower()
	if family.is_empty():
		return "street"
	return family

static func _candidate_stream_paths(vehicle_id: String, family: String) -> Array:
	var normalized_family := _normalize_family(family)
	var candidates: Array = []
	if not vehicle_id.is_empty():
		candidates.append("%s/%s_%s.wav" % [_VEHICLE_AUDIO_DIR, vehicle_id, normalized_family])
		candidates.append("%s/%s_%s.ogg" % [_VEHICLE_AUDIO_DIR, vehicle_id, normalized_family])
		candidates.append("%s/%s_%s.mp3" % [_VEHICLE_AUDIO_DIR, vehicle_id, normalized_family])
		candidates.append("%s/%s.wav" % [_VEHICLE_AUDIO_DIR, vehicle_id])
		candidates.append("%s/%s.ogg" % [_VEHICLE_AUDIO_DIR, vehicle_id])
		candidates.append("%s/%s.mp3" % [_VEHICLE_AUDIO_DIR, vehicle_id])
		candidates.append("%s/%s_%s.wav" % [_AUDIO_DIR, vehicle_id, normalized_family])
		candidates.append("%s/%s_%s.ogg" % [_AUDIO_DIR, vehicle_id, normalized_family])
		candidates.append("%s/%s_%s.mp3" % [_AUDIO_DIR, vehicle_id, normalized_family])
		candidates.append("%s/%s.wav" % [_AUDIO_DIR, vehicle_id])
		candidates.append("%s/%s.ogg" % [_AUDIO_DIR, vehicle_id])
		candidates.append("%s/%s.mp3" % [_AUDIO_DIR, vehicle_id])
	candidates.append("%s/engine_%s.wav" % [_AUDIO_DIR, normalized_family])
	candidates.append("%s/engine_%s.ogg" % [_AUDIO_DIR, normalized_family])
	candidates.append("%s/engine_%s.mp3" % [_AUDIO_DIR, normalized_family])
	return candidates

static func _load_stream_from_candidates(vehicle_id: String, family: String) -> AudioStream:
	for path in _candidate_stream_paths(vehicle_id, family):
		if ResourceLoader.exists(path):
			var stream := load(path)
			if stream is AudioStream:
				return stream
	return null

static func get_stream(family: String, vehicle_id: String = "") -> AudioStream:
	var normalized_family := _normalize_family(family)
	var key := _cache_key(vehicle_id, normalized_family)
	if _streams.has(key):
		return _streams[key]
	var stream := _load_stream_from_candidates(vehicle_id, normalized_family)
	if stream != null:
		_streams[key] = stream
		return stream
	var fallback_key := _cache_key("", normalized_family)
	if _streams.has(fallback_key):
		var fallback_stream = _streams[fallback_key]
		_streams[key] = fallback_stream
		return fallback_stream
	var fallback := _generate_engine_stream(normalized_family)
	_streams[fallback_key] = fallback
	_streams[key] = fallback
	return fallback

static func family_for_vehicle(vehicle_id: String) -> String:
	var spec := VehicleCatalog.get_vehicle_spec(vehicle_id)
	var roof := String(spec.get("roof_prop", ""))
	if vehicle_id == "route_city": return "bus"
	if roof == "fire_lightbar": return "fire_diesel"
	if roof == "ambulance_lightbar": return "ambulance"
	if roof == "police_lightbar": return "police"
	if float(spec.get("mass", 1.0)) >= 2.4: return "truck"
	if float(spec.get("mass", 1.0)) >= 1.5: return "diesel"
	return "sport" if float(spec.get("engine_pitch", 1.0)) >= 1.15 else "street"

func update(audio: AudioStreamPlayer2D, speed: float, top_speed: float, throttle: float, delta: float, vehicle_id: String, boosting: bool = false) -> void:
	if audio == null:
		return
	var spec := VehicleCatalog.get_vehicle_spec(vehicle_id)
	var pitch := float(spec.get("engine_pitch", 1.0))
	var family := family_for_vehicle(vehicle_id)
	var family_key := _cache_key(vehicle_id, family)
	if family_key != _stream_cache_key:
		_stream_cache_key = family_key
		audio.stream = get_stream(family, vehicle_id)
		rpm = 0.0
		gear = 1
	var ratio := clampf(speed / maxf(top_speed, 1.0), 0.0, 1.0)
	shift_remaining = maxf(0.0, shift_remaining - delta)
	shift_cooldown = maxf(0.0, shift_cooldown - delta)
	var previous_gear := gear
	# Hysteresis prevents gear chatter when cruising near a shift threshold.
	if shift_cooldown <= 0.0 and gear < _GEAR_TOPS.size() and ratio > _gear_top(gear):
		gear += 1
	elif shift_cooldown <= 0.0 and gear > 1 and ratio < _gear_bottom(gear) - _DOWNSHIFT_MARGIN:
		gear -= 1
	if gear != previous_gear:
		shift_remaining = 0.24 if family in ["bus", "truck", "diesel", "fire_diesel"] else 0.16
		# 0.65s travava a caixa: com a grade nova o carro atravessa uma marcha do
		# meio em ~0.55s, então as marchas altas só entravam depois da velocidade
		# já ter passado do ponto de troca. A histerese de _DOWNSHIFT_MARGIN é o
		# que impede chatter; o cooldown só precisa cobrir o corte de torque.
		shift_cooldown = 0.32
	var blend := 1.0 - exp(-maxf(delta, 0.0) * 9.0)
	load_amount = lerpf(load_amount, clampf(absf(throttle), 0.0, 1.0), blend)
	var gear_bottom := _gear_bottom(gear)
	var gear_span := maxf(_gear_top(gear) - gear_bottom, 0.01)
	var in_gear := clampf((ratio - gear_bottom) / gear_span, 0.0, 1.0)
	var target_rpm := 0.12 + in_gear * 0.52 + load_amount * 0.22
	if shift_remaining > 0.0:
		target_rpm *= 0.55
	if boosting:
		target_rpm += 0.12
	rpm = lerpf(rpm, target_rpm, 1.0 - exp(-maxf(delta, 0.0) * (7.0 if target_rpm > rpm else 12.0)))
	# O pitch soma o giro da marcha com a velocidade absoluta. Só o giro fazia o
	# topo da primeira marcha soar a 97% do pitch máximo -- o motor "estourava"
	# logo na largada e as marchas seguintes repetiam o mesmo som. Com o termo de
	# velocidade, cada marcha termina mais aguda que a anterior (1.38, 1.49, 1.59,
	# 1.69, 1.81) e o pitch máximo antigo só é alcançado na velocidade máxima.
	audio.pitch_scale = clampf((0.66 + rpm * 0.62 + ratio * 0.62) * pitch, 0.5, 2.4)
	audio.volume_db = -22.0 + load_amount * 7.5 + rpm * 2.6 + ratio * 1.8
	if shift_remaining > 0.0:
		audio.volume_db -= 3.5
	if not audio.playing:
		audio.play()

static func _generate_engine_stream(family: String) -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	data.resize(rate * 2)
	# Integer cycle counts (including the half-frequency rumble) close the loop.
	var profiles := {
		"street": [58.0, 1.45, 0.16, 936.0, 0.035],
		"sport": [78.0, 1.20, 0.12, 1248.0, 0.04],
		"diesel": [42.0, 1.55, 0.30, 756.0, 0.05],
		"bus": [36.0, 1.85, 0.42, 432.0, 0.025],
		"truck": [46.0, 1.25, 0.38, 828.0, 0.065],
		"fire_diesel": [40.0, 1.35, 0.45, 640.0, 0.055],
		"ambulance": [62.0, 1.55, 0.24, 992.0, 0.045],
		"police": [66.0, 1.30, 0.22, 1056.0, 0.04],
	}
	var profile: Array = profiles.get(family, profiles.street)
	var fundamental: float = profile[0]
	# O resampler do AudioStreamWAV interpola lendo amostras ALÉM do fim do laço.
	# Sem essas amostras de guarda ele caía no padding de zeros do buffer e gerava
	# um estalo a cada volta do laço -- ~1.8 estalos por segundo na velocidade
	# máxima, o "tic, tic, tic" reportado. Medido em tests/test_engine_loop_seam.gd:
	# degrau de 0.22 no áudio mixado contra 0.046 de degrau natural do waveform.
	# O waveform é periódico em 1s, então continuar a mesma fórmula por algumas
	# amostras extras reproduz exatamente o início do laço.
	var guard := 8
	data.resize((rate + guard) * 2)
	for i in rate + guard:
		var t := float(i) / rate
		var phase := TAU * fundamental * t
		var combustion := 0.0
		for harmonic in range(1, 9):
			combustion += sin(phase * harmonic + float(harmonic % 3) * 0.18) / pow(float(harmonic), float(profile[1]))
		var rumble := sin(phase * 0.5) * float(profile[2])
		var mechanical := sin(TAU * float(profile[3]) * t) * sin(phase) * float(profile[4])
		var flutter := 0.94 + 0.06 * sin(TAU * 6.0 * t)
		var sample := tanh((combustion + rumble + mechanical) * 1.25) * 0.48 * flutter
		data.encode_s16(i * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	# Volta em `rate`: as amostras de guarda depois disso existem só para a
	# interpolação da emenda, não fazem parte do trecho tocado.
	stream.loop_end = rate
	stream.data = data
	return stream
