extends RefCounted

## Resposta de motor compartilhada pelos dois controladores de veículo.
##
## O motor não é um loop único puxado no pitch: cada família tem TRÊS camadas
## sintetizadas em rotações nominais diferentes (marcha lenta, meio, alto giro)
## e o controlador faz o crossfade entre elas conforme o giro. Esticar uma
## amostra só de 0.5x a 2.4x é exatamente o que dava o som "computadorizado":
## um motor real não muda apenas de altura quando sobe de giro, ele muda de
## timbre — a batida vira zumbido, o escape ganha aspereza. Com três camadas
## nenhuma delas é esticada mais que ~1.9x, que é a faixa em que reamostragem
## ainda soa como o instrumento original.
##
## Cada camada é construída como um MOTOR, não como uma soma de senóides:
## trem de pulsos de combustão (um por cilindro, na ordem de ignição, com a
## irregularidade de tempo que dá o ronco de V8) passando por ressoadores de
## escapamento/carroceria, mais estalo de injeção para os diesel, chiado de
## admissão e assobio de turbina/câmbio. É a cadeia física do som real.

const RATE := 22050
## Amostras de guarda depois do fim do laço. O resampler do AudioStreamWAV
## interpola lendo ALÉM de loop_end; sem elas ele cai no padding de zeros e
## estala a cada volta (medido em tests/test_engine_loop_seam.gd).
const GUARD := 8

static var _streams: Dictionary = {}
static var _layer_sets: Dictionary = {}
static var _road_stream: AudioStreamWAV = null

var rpm := 0.0
var load_amount := 0.0
var gear := 1
var shift_remaining := 0.0
var shift_cooldown := 0.0
## Frequência de ignição realmente tocada (Hz). É o que o ouvido chama de
## "altura do motor"; os testes medem isto em vez de pitch_scale, porque com
## camadas o pitch_scale de um player sozinho não descreve mais o som.
var engine_hz := 0.0
## Rotação do virabrequim em RPM. Um ciclo de motor são duas voltas, daí o 120.
## Não é frequência de ignição: um V6 a 4000 rpm bate MAIS vezes por segundo que
## um quatro cilindros a 5000, então comparar famílias por engine_hz inverte a
## resposta. Quem diz "esse motor gira pouco" é este número.
var engine_rpm := 0.0

var _family := ""
var _stream_cache_key := ""
var _layer_players: Array = []
var _road_player: AudioStreamPlayer2D = null
var _assigned_stream: AudioStream = null
var _limiter_phase := 0.0
var _idle_phase := 0.0

const _VEHICLE_AUDIO_DIR := "res://audio/vehicle"
const _AUDIO_DIR := "res://audio"

# ---------------------------------------------------------------------------
# Caixa de câmbio por família
# ---------------------------------------------------------------------------
## Topo de cada marcha em fração da velocidade máxima de rua. Não é mais uma
## grade única: caminhão tem oito marchas curtas (a escada infinita é metade do
## que faz um caminhão soar como caminhão), o muscle tem quatro longas e
## preguiçosas, o esportivo seis. Isso também responde ao "chega no final muito
## rápido": com marcha longa no topo o carro passa segundos subindo no último
## engate em vez de estourar a escada inteira em um segundo e meio.
const _GEARBOX := {
	"street": [0.19, 0.34, 0.51, 0.71, 1.0],
	"sport": [0.15, 0.27, 0.41, 0.57, 0.77, 1.0],
	"muscle": [0.24, 0.45, 0.71, 1.0],
	"suv": [0.17, 0.31, 0.47, 0.65, 0.84, 1.0],
	"diesel": [0.16, 0.29, 0.44, 0.62, 0.82, 1.0],
	"truck": [0.11, 0.20, 0.31, 0.43, 0.57, 0.73, 0.90, 1.0],
	"bus": [0.14, 0.26, 0.40, 0.56, 0.76, 1.0],
	"fire_diesel": [0.12, 0.23, 0.36, 0.50, 0.66, 0.83, 1.0],
	"ambulance": [0.18, 0.33, 0.51, 0.72, 1.0],
	"police": [0.16, 0.29, 0.45, 0.63, 0.83, 1.0],
}
## Folga abaixo do ponto de troca antes de reduzir: evita subir e descer marcha
## em loop quando a velocidade fica cruzando o limiar.
const _DOWNSHIFT_MARGIN := 0.045

# ---------------------------------------------------------------------------
# Timbre por família
# ---------------------------------------------------------------------------
## cyl            eventos de combustão por ciclo de motor (4 tempos): 4 = quatro
##                cilindros, 6 = seis em linha/V6, 8 = V8.
## cycles         ciclos de motor por segundo de cada camada. Inteiro de
##                propósito: garante número exato de ciclos em 1 s de buffer, o
##                que fecha o laço sem emenda.
## idle/redline   ciclos/s na marcha lenta e no corte. A razão entre os dois é a
##                faixa de giro da família — o diesel gira pouco (~4x), o
##                esportivo gira muito (~8x), e é isso que faz o caminhão
##                parecer que "acaba" logo e o esportivo parecer que estica.
## decay          quão seco é o pulso de combustão em cada camada (múltiplos do
##                intervalo entre ignições).
## res            ressoadores [freq, Q, ganho]: escapamento, carroceria, caixa.
## knock          estalo de injeção diesel: [nível, freq metálica].
## intake         chiado de admissão: [nível, freq, Q].
## whine          assobio [múltiplo do ciclo, nível] — turbina/câmbio.
## drive          saturação por camada: alto giro distorce mais.
## sub            ronco de meio-tempo (ordem do ciclo), o "lope" do motor grande.
const _PROFILES := {
	"street": {
		"cyl": 4, "cycles": [7, 21, 44], "idle": 6.4, "redline": 50.0,
		"decay": [4.6, 3.6, 2.9], "sub": 0.14,
		"res": [[112.0, 5.5, 1.0], [286.0, 4.0, 0.42], [860.0, 3.0, 0.12]],
		"knock": [0.0, 2200.0], "intake": [0.085, 1500.0, 1.1],
		"whine": [0.0, 0.0], "drive": [1.1, 1.6, 2.4],
	},
	"sport": {
		"cyl": 6, "cycles": [8, 26, 56], "idle": 7.4, "redline": 62.0,
		"decay": [4.0, 3.0, 2.2], "sub": 0.10,
		"res": [[178.0, 5.0, 0.85], [520.0, 4.5, 0.55], [1650.0, 3.5, 0.26]],
		"knock": [0.0, 2600.0], "intake": [0.14, 2400.0, 0.9],
		"whine": [46.0, 0.055], "drive": [1.3, 2.1, 3.4],
	},
	"muscle": {
		"cyl": 8, "cycles": [6, 19, 42], "idle": 5.6, "redline": 45.0,
		"decay": [3.4, 2.8, 2.2], "sub": 0.30,
		"res": [[76.0, 7.0, 1.15], [168.0, 5.0, 0.62], [430.0, 3.5, 0.22]],
		"knock": [0.0, 1800.0], "intake": [0.075, 900.0, 1.0],
		"whine": [0.0, 0.0], "drive": [1.5, 2.0, 2.8],
		# V8 de virabrequim cruzado: um banco de escape recebe ignições
		# desiguais (180-90-180-270 graus). É a irregularidade — não o número de
		# cilindros — que produz o borbulhar característico.
		"pattern_offset": [0.0, 0.11, -0.05, 0.07, 0.0, 0.13, -0.06, 0.06],
		"pattern_amp": [1.0, 0.76, 0.97, 0.82, 1.0, 0.72, 0.95, 0.80],
	},
	"suv": {
		"cyl": 6, "cycles": [6, 18, 38], "idle": 5.6, "redline": 42.0,
		"decay": [3.8, 3.0, 2.5], "sub": 0.24,
		# Caixa grande e fechada: o estouro fica preso na carroceria (Q alto em
		# 92 Hz) e quase nada passa de 700 Hz. É o "bum" abafado de utilitário.
		"res": [[92.0, 7.0, 1.2], [212.0, 4.5, 0.5], [640.0, 2.5, 0.10]],
		"knock": [0.0, 1600.0], "intake": [0.06, 780.0, 1.2],
		"whine": [0.0, 0.0], "drive": [1.15, 1.5, 2.0],
		"pattern_amp": [1.0, 0.94, 1.03, 0.96, 1.0, 0.92],
	},
	"diesel": {
		"cyl": 4, "cycles": [5, 14, 26], "idle": 5.0, "redline": 28.0,
		"decay": [5.5, 4.6, 4.0], "sub": 0.18,
		"res": [[96.0, 6.0, 0.95], [430.0, 4.5, 0.45], [2100.0, 5.5, 0.24]],
		"knock": [0.38, 2350.0], "intake": [0.10, 1900.0, 1.4],
		"whine": [30.0, 0.03], "drive": [1.2, 1.6, 2.1],
		"pattern_amp": [1.0, 0.88, 1.06, 0.91],
	},
	"truck": {
		"cyl": 6, "cycles": [4, 9, 17], "idle": 3.6, "redline": 19.0,
		"decay": [5.0, 5.0, 3.6], "sub": 0.44,
		# Escapamento vertical longo e cabine alta: fundamental muito baixa,
		# corpo em 150 Hz e a batida de injeção brilhando em 1.9 kHz. Os 62 Hz do
		# escapamento ficam DESLOCADOS da ignição de qualquer camada de propósito:
		# quando a ressonância cai em cima da taxa de ignição ela acumula volta a
		# volta e o diesel vira um zumbido liso (batida medida caiu a 0.04).
		"res": [[62.0, 7.0, 1.35], [150.0, 5.0, 0.62], [1900.0, 6.0, 0.30]],
		"knock": [0.55, 1950.0], "intake": [0.13, 1250.0, 1.3],
		"whine": [26.0, 0.075], "drive": [1.2, 1.5, 1.9],
		"pattern_amp": [1.0, 0.9, 1.08, 0.93, 1.04, 0.88],
	},
	"bus": {
		"cyl": 6, "cycles": [4, 9, 16], "idle": 3.4, "redline": 18.0,
		"decay": [5.8, 5.0, 4.4], "sub": 0.40,
		# Motor traseiro dentro de uma caixa metálica de doze metros: Q muito
		# alto embaixo (o chão vibra) e um assobio de câmbio automático quase
		# constante, que é o que separa ônibus de caminhão para o ouvido.
		"res": [[46.0, 8.0, 1.4], [128.0, 6.0, 0.7], [300.0, 5.0, 0.34]],
		"knock": [0.30, 1500.0], "intake": [0.11, 820.0, 1.6],
		"whine": [21.0, 0.115], "drive": [1.1, 1.35, 1.7],
		"pattern_amp": [1.0, 0.93, 1.05, 0.95, 1.02, 0.9],
	},
	"fire_diesel": {
		"cyl": 6, "cycles": [4, 10, 19], "idle": 3.8, "redline": 21.0,
		"decay": [4.6, 3.9, 3.4], "sub": 0.46,
		"res": [[50.0, 7.0, 1.4], [162.0, 5.0, 0.68], [1750.0, 5.5, 0.32]],
		"knock": [0.50, 1850.0], "intake": [0.15, 1400.0, 1.2],
		"whine": [24.0, 0.06], "drive": [1.25, 1.6, 2.1],
		"pattern_amp": [1.0, 0.91, 1.07, 0.94, 1.03, 0.89],
	},
	"ambulance": {
		"cyl": 4, "cycles": [5, 16, 30], "idle": 5.2, "redline": 33.0,
		"decay": [5.0, 4.2, 3.5], "sub": 0.20,
		"res": [[104.0, 6.0, 1.0], [400.0, 4.5, 0.44], [1950.0, 5.0, 0.20]],
		"knock": [0.22, 2150.0], "intake": [0.11, 1750.0, 1.3],
		"whine": [32.0, 0.035], "drive": [1.2, 1.6, 2.2],
		"pattern_amp": [1.0, 0.9, 1.05, 0.93],
	},
	"police": {
		"cyl": 8, "cycles": [7, 22, 48], "idle": 6.5, "redline": 52.0,
		"decay": [3.6, 2.9, 2.3], "sub": 0.24,
		"res": [[98.0, 6.0, 1.05], [244.0, 4.5, 0.58], [820.0, 3.5, 0.22]],
		"knock": [0.0, 1900.0], "intake": [0.10, 1200.0, 1.0],
		"whine": [0.0, 0.0], "drive": [1.35, 1.9, 2.7],
		"pattern_offset": [0.0, 0.08, -0.03, 0.05, 0.0, 0.09, -0.04, 0.04],
		"pattern_amp": [1.0, 0.84, 0.98, 0.88, 1.0, 0.82, 0.97, 0.86],
	},
}
## Duração do corte de torque na troca e o quanto de força sobra durante ela.
## Caminhão e ônibus trocam devagar e com corte longo; esportivo quase não corta.
const _SHIFT := {
	"street": [0.16, 0.30], "sport": [0.13, 0.28], "muscle": [0.20, 0.32],
	"suv": [0.20, 0.32], "diesel": [0.24, 0.36], "truck": [0.30, 0.40],
	"bus": [0.34, 0.42], "fire_diesel": [0.30, 0.40], "ambulance": [0.22, 0.34],
	"police": [0.14, 0.28],
}

# ---------------------------------------------------------------------------
# Física de tração (compartilhada com os controladores)
# ---------------------------------------------------------------------------
static func road_top_speed(authored_speed: float) -> float:
	return authored_speed * 0.8

func _gear_tops() -> Array:
	if _family.is_empty():
		return _GEARBOX.street
	return _GEARBOX.get(_family, _GEARBOX.street)

func _gear_top(gear_index: int) -> float:
	var tops := _gear_tops()
	return float(tops[clampi(gear_index, 1, tops.size()) - 1])

func _gear_bottom(gear_index: int) -> float:
	if gear_index <= 1:
		return 0.0
	var tops := _gear_tops()
	return float(tops[clampi(gear_index, 2, tops.size()) - 2])

func _shift_spec() -> Array:
	if _family.is_empty():
		return _SHIFT.street
	return _SHIFT.get(_family, _SHIFT.street)

## Curva de tração. A largada é idêntica à anterior (0-25% da velocidade de rua
## no mesmo tempo) mas o topo cai muito mais: o antigo `lerp(1, 0.45)` ainda
## entregava 45% da força na velocidade máxima e o carro percorria a escada de
## marchas inteira em 1.8 s. Com queda quadrática o último terço leva o dobro do
## tempo, que é o "chega no final muito rápido" do relato.
func drive_force(speed: float, top_speed: float) -> float:
	var ratio := clampf(speed / maxf(road_top_speed(top_speed), 1.0), 0.0, 1.0)
	var pull := 0.35 * (1.0 - ratio * ratio) * (1.0 - 0.45 * ratio) + 0.012
	if shift_remaining > 0.0:
		pull *= float(_shift_spec()[1])
	return pull

# ---------------------------------------------------------------------------
# Seleção de família e de stream
# ---------------------------------------------------------------------------
static func _normalize_family(value: String) -> String:
	var family := String(value).strip_edges().to_lower()
	return "street" if family.is_empty() else family

static func _profile(family: String) -> Dictionary:
	return _PROFILES.get(_normalize_family(family), _PROFILES.street)

static func _cache_key(vehicle_id: String, family: String) -> String:
	var normalized_family := _normalize_family(family)
	if not vehicle_id.is_empty():
		return "%s:%s" % [vehicle_id, normalized_family]
	return "#:%s" % normalized_family

static func family_for_vehicle(vehicle_id: String) -> String:
	var spec := VehicleCatalog.get_vehicle_spec(vehicle_id)
	var roof := String(spec.get("roof_prop", ""))
	var mass := float(spec.get("mass", 1.0))
	var pitch := float(spec.get("engine_pitch", 1.0))
	var speed := float(spec.get("max_speed", 400.0))
	if vehicle_id == "route_city": return "bus"
	if roof == "fire_lightbar": return "fire_diesel"
	if roof == "ambulance_lightbar": return "ambulance"
	if roof == "police_lightbar": return "police"
	if mass >= 2.4: return "truck"
	# Furgão é diesel de quatro cilindros, chacoalhando; separado do utilitário
	# grande, que é V6/V8 a gasolina e soa abafado em vez de estalado.
	if vehicle_id.contains("van"): return "diesel"
	if mass >= 1.45: return "suv"
	if pitch >= 1.15: return "sport"
	if pitch >= 1.08 and speed >= 540.0: return "sport"
	if pitch <= 0.90 and mass >= 1.15: return "muscle"
	return "street"

static func _candidate_stream_paths(vehicle_id: String, family: String) -> Array:
	var normalized_family := _normalize_family(family)
	var candidates: Array = []
	if not vehicle_id.is_empty():
		for ext in ["wav", "ogg", "mp3"]:
			candidates.append("%s/%s_%s.%s" % [_VEHICLE_AUDIO_DIR, vehicle_id, normalized_family, ext])
		for ext in ["wav", "ogg", "mp3"]:
			candidates.append("%s/%s.%s" % [_VEHICLE_AUDIO_DIR, vehicle_id, ext])
		for ext in ["wav", "ogg", "mp3"]:
			candidates.append("%s/%s_%s.%s" % [_AUDIO_DIR, vehicle_id, normalized_family, ext])
		for ext in ["wav", "ogg", "mp3"]:
			candidates.append("%s/%s.%s" % [_AUDIO_DIR, vehicle_id, ext])
	for ext in ["wav", "ogg", "mp3"]:
		candidates.append("%s/engine_%s.%s" % [_AUDIO_DIR, normalized_family, ext])
	return candidates

static func _load_stream_from_candidates(vehicle_id: String, family: String) -> AudioStream:
	for path in _candidate_stream_paths(vehicle_id, family):
		if ResourceLoader.exists(path):
			var stream := load(path)
			if stream is AudioStream:
				return stream
	return null

## Conjunto de camadas (marcha lenta, meio, alto giro) de uma família. Se
## existir gravação autoral para o veículo ela vence e o conjunto tem uma camada
## só — o controlador cai no modo antigo de pitch único, porque uma gravação foi
## feita em uma rotação e não dá para inventar as outras a partir dela.
static func get_layer_streams(family: String, vehicle_id: String = "") -> Array:
	var normalized_family := _normalize_family(family)
	var key := _cache_key(vehicle_id, normalized_family)
	if _layer_sets.has(key):
		return _layer_sets[key]
	var authored := _load_stream_from_candidates(vehicle_id, normalized_family)
	if authored != null:
		var single: Array = [authored]
		_layer_sets[key] = single
		_streams[key] = authored
		return single
	var shared_key := _cache_key("", normalized_family)
	if not _layer_sets.has(shared_key):
		var built: Array = []
		for layer in 3:
			built.append(_generate_layer(normalized_family, layer))
		_layer_sets[shared_key] = built
		_streams[shared_key] = built[0]
	_layer_sets[key] = _layer_sets[shared_key]
	_streams[key] = _streams[shared_key]
	return _layer_sets[key]

static func get_stream(family: String, vehicle_id: String = "") -> AudioStream:
	return get_layer_streams(family, vehicle_id)[0]

## Constrói as camadas antes de o carro sair andando. Sem isso a síntese das
## três camadas cai no primeiro quadro de direção e vira engasgo.
static func prewarm(vehicle_id: String) -> void:
	get_layer_streams(family_for_vehicle(vehicle_id), vehicle_id)
	get_road_stream()

# ---------------------------------------------------------------------------
# Síntese
# ---------------------------------------------------------------------------
## Ressoador de dois pólos aplicado em círculo. As duas voltas levam o filtro ao
## regime permanente antes de gravar a saída: como a entrada é periódica em 1 s,
## a saída sai exatamente periódica e a emenda do laço não estala.
static func _resonate(src: PackedFloat32Array, freq: float, q: float, gain: float, out: PackedFloat32Array) -> void:
	var n := src.size()
	var w := TAU * freq / float(RATE)
	if w <= 0.0 or w >= PI:
		return
	var r: float = exp(-w / (2.0 * maxf(q, 0.5)))
	var a1 := -2.0 * r * cos(w)
	var a2 := r * r
	# (1 - r) deixa o ganho de pico próximo de 1 qualquer que seja o Q: assim o
	# campo `gain` do perfil é o nível relativo real do ressoador, e um Q alto
	# alonga a cauda sem também levantar o volume.
	var b0 := (1.0 - r) * gain
	var y1 := 0.0
	var y2 := 0.0
	for round_index in 2:
		var write := round_index == 1
		for i in n:
			var y := b0 * src[i] - a1 * y1 - a2 * y2
			y2 = y1
			y1 = y
			if write:
				out[i] += y

## Ruído periódico por construção: um bloco de ruído branco repetido é um sinal
## periódico legítimo, e filtrá-lo em círculo mantém essa periodicidade. É o que
## permite ter chiado de admissão dentro de um laço sem clique na volta.
static func _circular_noise(n: int, freq: float, q: float, seed_value: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = rng.randf_range(-1.0, 1.0)
	var out := PackedFloat32Array()
	out.resize(n)
	_resonate(raw, freq, q, 1.0, out)
	return out

## Passa-alta de um pólo, também circular. Abaixo de ~28 Hz não há audição, só
## excursão de amplitude: sem tirar isso o ronco de meio-tempo das camadas de
## marcha lenta (4-7 Hz) consumia quase toda a margem da normalização e o motor
## saía fino depois de normalizado.
static func _highpass(buf: PackedFloat32Array, freq: float) -> void:
	var n := buf.size()
	var a: float = exp(-TAU * freq / float(RATE))
	var previous_in := buf[n - 1]
	var previous_out := 0.0
	for round_index in 2:
		var write := round_index == 1
		for i in n:
			var sample := buf[i]
			var y := a * (previous_out + sample - previous_in)
			previous_in = sample
			previous_out = y
			if write:
				buf[i] = y

static func _generate_layer(family: String, layer: int) -> AudioStreamWAV:
	var profile := _profile(family)
	var cyl := int(profile.cyl)
	var cycles := int(profile.cycles[layer])
	var cycle_len := float(RATE) / float(cycles)
	var fire_len := cycle_len / float(cyl)
	var pattern_offset: Array = profile.get("pattern_offset", [])
	var pattern_amp: Array = profile.get("pattern_amp", [])

	# --- trem de combustão -------------------------------------------------
	var pulses := PackedFloat32Array()
	pulses.resize(RATE)
	var envelope := PackedFloat32Array()
	envelope.resize(RATE)
	var decay_rate := float(profile.decay[layer]) / fire_len
	var attack: float = maxf(fire_len * 0.05, 2.5)
	var span := int(fire_len * 2.6) + 4
	var knock_level := float(profile.knock[0])
	var knock_w := TAU * float(profile.knock[1]) / float(RATE)
	var knock_decay := 1.0 / maxf(fire_len * 0.075, 2.0)
	for event in cycles * cyl:
		var slot := event % cyl
		var offset: float = float(pattern_offset[slot]) if slot < pattern_offset.size() else 0.0
		var amp: float = float(pattern_amp[slot]) if slot < pattern_amp.size() else 1.0
		var start := (float(event) + offset) * fire_len
		var base := int(floor(start))
		var frac := start - float(base)
		for n in span:
			var x := float(n) - frac
			if x < 0.0:
				continue
			var index := posmod(base + n, RATE)
			var rise := 1.0 - exp(-x / attack)
			# Dois exponenciais: o rápido tira o DC e dá o "tapa" do pulso, o
			# lento é a cauda de pressão no escapamento.
			var body: float = exp(-decay_rate * x) - 0.62 * exp(-decay_rate * 2.8 * x)
			pulses[index] += amp * rise * body
			envelope[index] += amp * rise * exp(-decay_rate * x)
			if knock_level > 0.0:
				pulses[index] += amp * knock_level * exp(-knock_decay * x) * sin(knock_w * x)

	# --- corpo: escapamento, carroceria, caixa -----------------------------
	var voiced := PackedFloat32Array()
	voiced.resize(RATE)
	for res_spec in profile.res:
		_resonate(pulses, float(res_spec[0]), float(res_spec[1]), float(res_spec[2]), voiced)
	# Um pouco do pulso cru mantém a definição da batida que o ressoador borra.
	for i in RATE:
		voiced[i] += pulses[i] * 0.28

	# --- ronco de ciclo, admissão e assobio --------------------------------
	var sub := float(profile.sub)
	var intake_level := float(profile.intake[0]) * (0.55 + 0.45 * float(layer))
	var intake := _circular_noise(RATE, float(profile.intake[1]), float(profile.intake[2]), hash(family) + layer * 7919)
	var whine_mult := float(profile.whine[0])
	var whine_level := float(profile.whine[1]) * (0.5 + 0.5 * float(layer))
	var whine_w := TAU * whine_mult * float(cycles) / float(RATE)
	# O ronco fica na ordem do virabrequim (duas voltas por ciclo) com um traço
	# da ordem do ciclo. É a mesma escada de sub-harmônicos que um motor grande
	# produz de verdade; o que cair abaixo da audição some no passa-alta.
	var sub_w := TAU * float(cycles * 2) / float(RATE)
	var crank_w := TAU * float(cycles) / float(RATE)
	var env_peak := 0.0001
	for i in RATE:
		env_peak = maxf(env_peak, envelope[i])
	for i in RATE:
		var t := float(i)
		var value := voiced[i]
		value += sub * (sin(sub_w * t) * 0.72 + sin(crank_w * t) * 0.28)
		# Turbulência de admissão é modulada pela própria ignição: ruído solto e
		# constante soa como chiado de rádio, não como motor.
		value += intake[i] * intake_level * (0.4 + 0.6 * envelope[i] / env_peak)
		if whine_level > 0.0:
			value += whine_level * (sin(whine_w * t) + 0.35 * sin(whine_w * 2.0 * t))
		voiced[i] = value

	# --- saturação e normalização ------------------------------------------
	_highpass(voiced, 28.0)
	# Normalizar ANTES da saturação: sem isso a soma dos ressoadores chegava ao
	# tanh com amplitude de uma dezena e TODAS as famílias viravam onda quadrada
	# — foi o que a medição pegou como "batida = 0.00". Com a entrada em ±1 o
	# campo `drive` volta a significar quanto o escapamento aspera, e a divisão
	# por tanh(drive) mantém o nível para a normalização final comparar timbres.
	var raw_peak := 0.0001
	for i in RATE:
		raw_peak = maxf(raw_peak, absf(voiced[i]))
	var drive := float(profile.drive[layer])
	var drive_norm: float = tanh(drive)
	var peak := 0.0001
	for i in RATE:
		var value: float = tanh(voiced[i] / raw_peak * drive) / drive_norm
		voiced[i] = value
		peak = maxf(peak, absf(value))
	var scale := 0.74 / peak

	var data := PackedByteArray()
	data.resize((RATE + GUARD) * 2)
	for i in RATE:
		data.encode_s16(i * 2, int(clampf(voiced[i] * scale, -0.999, 0.999) * 32767.0))
	# A guarda repete o começo do laço: é literalmente o que a interpolação da
	# emenda precisa ler, e vale mesmo para as camadas com ruído.
	for i in GUARD:
		data.encode_s16((RATE + i) * 2, data.decode_s16(i * 2))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = RATE
	stream.data = data
	return stream

## Rolagem de pneu e vento. Existe para dar referência de velocidade ABSOLUTA:
## num carro real a quinta marcha a 4000 rpm não soa como a primeira a 4000 rpm
## por causa deste ruído, não porque o motor mudou de altura. Sem ele, marchas
## fisicamente corretas soam todas iguais.
static func get_road_stream() -> AudioStreamWAV:
	if _road_stream != null:
		return _road_stream
	var roar := _circular_noise(RATE, 240.0, 1.1, 20260909)
	var hiss := _circular_noise(RATE, 1500.0, 0.8, 31415926)
	var body := _circular_noise(RATE, 78.0, 2.2, 27182818)
	var peak := 0.0001
	var mixed := PackedFloat32Array()
	mixed.resize(RATE)
	for i in RATE:
		var value := roar[i] + hiss[i] * 0.42 + body[i] * 0.8
		mixed[i] = value
		peak = maxf(peak, absf(value))
	var scale := 0.7 / peak
	var data := PackedByteArray()
	data.resize((RATE + GUARD) * 2)
	for i in RATE:
		data.encode_s16(i * 2, int(clampf(mixed[i] * scale, -0.999, 0.999) * 32767.0))
	for i in GUARD:
		data.encode_s16((RATE + i) * 2, data.decode_s16(i * 2))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = RATE
	stream.data = data
	_road_stream = stream
	return stream

# ---------------------------------------------------------------------------
# Reprodução
# ---------------------------------------------------------------------------
func _spawn_sibling(audio: AudioStreamPlayer2D) -> AudioStreamPlayer2D:
	var player := AudioStreamPlayer2D.new()
	player.bus = audio.bus
	player.max_distance = audio.max_distance
	player.attenuation = audio.attenuation
	player.panning_strength = audio.panning_strength
	player.volume_db = -60.0
	var parent := audio.get_parent()
	if parent != null:
		parent.add_child(player)
	else:
		audio.add_child(player)
	return player

func _sync_layer_players(audio: AudioStreamPlayer2D, layers: Array) -> void:
	while _layer_players.size() < maxi(layers.size() - 1, 0):
		_layer_players.append(_spawn_sibling(audio))
	for i in _layer_players.size():
		var player: AudioStreamPlayer2D = _layer_players[i]
		if not is_instance_valid(player):
			continue
		if i + 1 < layers.size():
			if player.stream != layers[i + 1]:
				player.stream = layers[i + 1]
		elif player.stream != null:
			player.stop()
			player.stream = null

## Liga o controlador ao player do veículo já com a família certa. Os
## controladores chamavam `get_stream("street", id)` na criação e na troca de
## carro; com camadas isso plantava o timbre errado no player principal e o
## crossfade só se corrigia no primeiro quadro de direção.
func bind(audio: AudioStreamPlayer2D, vehicle_id: String) -> void:
	if audio == null:
		return
	var family := family_for_vehicle(vehicle_id)
	var layers: Array = get_layer_streams(family, vehicle_id)
	_family = family
	_stream_cache_key = _cache_key(vehicle_id, family)
	_assigned_stream = layers[0]
	audio.stream = layers[0]
	_sync_layer_players(audio, layers)
	rpm = 0.0
	gear = 1
	get_road_stream()

## Os controladores param o motor pelo player deles; as camadas extras são
## irmãs e não sabem disso sozinhas.
func stop() -> void:
	for player in _layer_players:
		if is_instance_valid(player):
			player.stop()
	if is_instance_valid(_road_player):
		_road_player.stop()

func update(audio: AudioStreamPlayer2D, speed: float, top_speed: float, throttle: float, delta: float, vehicle_id: String, boosting: bool = false) -> void:
	if audio == null:
		return
	var spec := VehicleCatalog.get_vehicle_spec(vehicle_id)
	var family := family_for_vehicle(vehicle_id)
	var key := _cache_key(vehicle_id, family)
	var layers: Array = get_layer_streams(family, vehicle_id)
	if key != _stream_cache_key:
		_stream_cache_key = key
		_family = family
		audio.stream = layers[0]
		_assigned_stream = layers[0]
		rpm = 0.0
		gear = 1
	_sync_layer_players(audio, layers)
	# Carros com gravação exclusiva (Monaliza) trocam o stream por fora. Nesse
	# caso não há camadas para cruzar: modula só o player do dono.
	var authored := layers.size() < 2 or audio.stream != _assigned_stream

	var profile := _profile(_family)
	var tops := _gear_tops()
	var step: float = maxf(delta, 0.0)
	var ratio := clampf(speed / maxf(top_speed, 1.0), 0.0, 1.0)

	shift_remaining = maxf(0.0, shift_remaining - step)
	shift_cooldown = maxf(0.0, shift_cooldown - step)
	var previous_gear := gear
	if shift_cooldown <= 0.0 and gear < tops.size() and ratio > _gear_top(gear):
		gear += 1
	elif shift_cooldown <= 0.0 and gear > 1 and ratio < _gear_bottom(gear) - _DOWNSHIFT_MARGIN:
		gear -= 1
	if gear != previous_gear:
		shift_remaining = float(_shift_spec()[0])
		# A histerese de _DOWNSHIFT_MARGIN é o que impede chatter; o cooldown só
		# precisa cobrir o corte de torque mais uma folga curta.
		shift_cooldown = shift_remaining + 0.16

	var blend := 1.0 - exp(-step * 9.0)
	load_amount = lerpf(load_amount, clampf(absf(throttle), 0.0, 1.0), blend)

	# Giro do motor é imposto pela roda através da marcha: no topo de qualquer
	# marcha o motor está no corte, e ao engatar a próxima ele cai para a razão
	# entre as duas. Essa serra é o som de trocar marcha; antes o giro era uma
	# rampa somada à velocidade e por isso todas as marchas soavam parecidas.
	var idle_norm := float(profile.idle) / float(profile.redline)
	# As marchas baixas trocam ANTES do corte e as altas vão até ele. É o que um
	# câmbio real faz (e o que o motorista faz de propósito), e é o que dá o
	# degrau: cada marcha termina mais aguda que a anterior sem que nenhuma passe
	# do corte. Antes isso vinha de um termo somado por velocidade, que jogava o
	# esportivo a 8800 rpm no fim da reta.
	var top_fraction: float = lerpf(0.86, 1.0, float(gear - 1) / maxf(float(tops.size() - 1), 1.0))
	var wheel_rpm := clampf(ratio / maxf(_gear_top(gear), 0.01) * top_fraction, 0.0, 1.0)
	var target: float = maxf(idle_norm, wheel_rpm)
	if ratio < 0.03:
		# Parado: o acelerador sobe o giro sem mover o carro.
		target = maxf(target, idle_norm + load_amount * (1.0 - idle_norm) * 0.62)
	if boosting:
		target = minf(1.0, target + 0.05)
	if wheel_rpm >= 0.995 and load_amount > 0.6:
		# Corte de giro: o limitador bate e solta, não segura uma nota fixa.
		_limiter_phase += step * 27.0
		target -= 0.045 * maxf(0.0, sin(_limiter_phase))
	_idle_phase += step * 6.7
	if target <= idle_norm + 0.03:
		# Marcha lenta de motor a combustão nunca é uma nota fixa: oscila poucos
		# por cento em torno do alvo. A oscilação é relativa à própria marcha
		# lenta — em valor absoluto de giro ela ficaria enorme para um diesel,
		# que trabalha numa fração bem mais alta do corte.
		target += idle_norm * (sin(_idle_phase) * 0.018 + sin(_idle_phase * 2.7) * 0.010)
	# Engatado, o giro segue a roda quase sem atraso; em ponto morto o motor tem
	# inércia própria — sobe rápido no acelerador e desce devagar.
	var response := 18.0 if ratio > 0.03 and shift_remaining <= 0.0 else (11.0 if target > rpm else 5.5)
	rpm = lerpf(rpm, target, 1.0 - exp(-step * response))

	# Variação por veículo, com expoente baixo: `engine_pitch` do catálogo dá
	# personalidade dentro da família sem desfazer o que a família estabeleceu.
	var vehicle_tint: float = pow(maxf(float(spec.get("engine_pitch", 1.0)), 0.3), 0.35)
	# `rpm` é fração do corte, então a rotação é proporcional a ele — não um lerp
	# entre marcha lenta e corte, que deixaria a marcha lenta girando ao dobro.
	# Nada aqui pode ultrapassar o corte: a sensação de velocidade absoluta vem
	# da camada de rolagem, não de esticar o motor acima do que ele aguenta.
	var cycles: float = float(profile.redline) * clampf(rpm, 0.0, 1.0) * vehicle_tint
	engine_hz = cycles * float(profile.cyl)
	engine_rpm = cycles * 120.0

	var master := -23.0 + load_amount * 7.0 + rpm * 6.5 + ratio * 1.5
	if shift_remaining > 0.0:
		master -= 4.0

	if authored:
		audio.pitch_scale = clampf((0.66 + rpm * 0.62 + ratio * 0.62) * float(spec.get("engine_pitch", 1.0)), 0.5, 2.4)
		audio.volume_db = master
		if not audio.playing:
			audio.play()
		for player in _layer_players:
			if is_instance_valid(player):
				player.stop()
		_update_road(audio, ratio)
		return

	# Crossfade entre as camadas em espaço logarítmico de rotação. Fora da
	# vizinhança da sua rotação nominal a camada some, então nenhuma amostra é
	# esticada além de ~1.9x — a origem do som "computadorizado".
	var nominal: Array = profile.cycles
	# Sem acelerador o motor fica mais surdo: puxar o timbre para baixo imita a
	# perda de pressão no escapamento sem precisar de uma quarta camada.
	var timbre := cycles / maxf(vehicle_tint, 0.3) * (0.80 + 0.20 * load_amount)
	# Uma camada some por completo a 2x da sua rotação nominal: é o limite em que
	# reamostragem ainda soa como o instrumento e não como sintetizador.
	var spread := log(2.0)
	var weights := PackedFloat32Array()
	weights.resize(nominal.size())
	var total := 0.0
	for i in nominal.size():
		var distance := log(maxf(timbre, 0.5) / float(nominal[i])) / spread
		if (i == 0 and distance < 0.0) or (i == nominal.size() - 1 and distance > 0.0):
			distance = 0.0
		var weight: float = clampf(1.0 - absf(distance), 0.0, 1.0)
		weights[i] = weight
		total += weight
	if total <= 0.0:
		weights[0] = 1.0
		total = 1.0

	for i in nominal.size():
		var player: AudioStreamPlayer2D = null
		if i == 0:
			player = audio
		elif i - 1 < _layer_players.size():
			player = _layer_players[i - 1]
		if player == null or not is_instance_valid(player):
			continue
		player.pitch_scale = clampf(cycles / float(nominal[i]), 0.35, 3.0)
		var share := weights[i] / total
		if share <= 0.002:
			if player.playing:
				player.stop()
			continue
		player.volume_db = master + linear_to_db(share)
		if not player.playing:
			player.play()
	_update_road(audio, ratio)

func _update_road(audio: AudioStreamPlayer2D, ratio: float) -> void:
	if ratio < 0.04:
		if is_instance_valid(_road_player) and _road_player.playing:
			_road_player.stop()
		return
	if not is_instance_valid(_road_player):
		_road_player = _spawn_sibling(audio)
		_road_player.stream = get_road_stream()
	var heavy: float = 1.0 if _family in ["truck", "bus", "fire_diesel"] else 0.0
	_road_player.pitch_scale = clampf((0.72 + ratio * 0.85) * (1.0 - heavy * 0.22), 0.4, 2.0)
	_road_player.volume_db = -42.0 + ratio * 21.0 + heavy * 3.0
	if not _road_player.playing:
		_road_player.play()
