extends RefCounted
## Tomadas sintetizadas dos materiais de rua que não têm WAV no projeto (playtest 30/10: "sons
## diferentes dessas coisas também"). Antes saco de lixo e papelão tocavam a madeira, cadeira de
## plástico e lixeira de rodinha também, e lata/tambor tocava a batida de carro (`metal` do banco
## de colisão de veículos).
##
## Três materiais, três tomadas cada:
## - "bag": saco plástico cheio: baque fofo grave e o farfalhar do plástico (ruído agudo picotado);
## - "can": lata, tambor, latão: modos inarmônicos de casca fina que soam e morrem devagar;
## - "plastic": plástico duro oco (cadeira, lixeira de rodinha, caixa de peixe, pneu): toc curto.
##
## Mesmo padrão de RunOverSquish/TirePuncture: síntese numa thread do WorkerThreadPool pedida no
## carregamento (`prewarm`, StreetPhysics._ready) e retida pela sessão. O quadro do impacto só pega
## uma tomada pronta; VehicleCrashAudio toca no seu pool limitado de vozes.

const RATE := 22050
const TAKES := 3
const KINDS := ["bag", "can", "plastic"]

static var _takes: Dictionary = {}
static var _task := -1


static func prewarm() -> void:
	if not _takes.is_empty() or _task >= 0: return
	_task = WorkerThreadPool.add_task(_build_all, false, "Sons de objetos de rua")


## Tomada `index` do material `kind`. Sem prewarm (teste isolado) ou com a thread ainda rodando,
## espera ou sintetiza aqui; no jogo a síntese terminou muito antes do primeiro saco atropelado.
static func take(kind: String, index: int) -> AudioStreamWAV:
	if _takes.is_empty():
		if _task >= 0:
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
		if _takes.is_empty(): _build_all()
	var list: Array = _takes.get(kind, [])
	if list.is_empty(): return null
	return list[clampi(index, 0, list.size() - 1)]


static func _build_all() -> void:
	var built := {}
	for kind in KINDS:
		var list: Array[AudioStreamWAV] = []
		for index in TAKES:
			var take_seed := 5101 + KINDS.find(kind) * 977 + index * 131
			var pitch := 1.0 + (float(index) - 1.0) * .09
			match kind:
				"bag": list.append(_wav(_bag(take_seed, pitch)))
				"can": list.append(_wav(_can(take_seed, pitch)))
				_: list.append(_wav(_plastic(take_seed, pitch)))
		built[kind] = list
	_takes = built


## Saco cheio batendo: o baque é grave e abafado (o conteúdo amortece), e o plástico farfalha
## por ~0,3 s em estalinhos irregulares, sem tom; nada de agudo contínuo para não virar chiado.
static func _bag(take_seed: int, pitch: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = take_seed
	var frames := int(RATE * .42)
	var dt := 1.0 / RATE
	var out := PackedFloat32Array()
	out.resize(frames)
	var phase := 0.0
	var low := 0.0
	var hp_in := 0.0
	var hp_out := 0.0
	var band := 0.0
	var crinkle := 0.0
	for index in frames:
		var t := index * dt
		phase += TAU * pitch * (70.0 + 40.0 * exp(-t * 30.0)) * dt
		var thump := sin(phase) * exp(-t * 22.0) * minf(1.0, t / .003)
		var noise := rng.randf_range(-1.0, 1.0)
		# Corpo do baque: ruído passa-baixa ~500 Hz, curto.
		low += (noise - low) * (1.0 - exp(-TAU * 500.0 * dt))
		var body := low * exp(-t * 28.0) * 1.6
		# Farfalhar: passa-alta ~1,8 kHz e um polo ~6 kHz, recortado por estalinhos aleatórios.
		var hp := .6 * (hp_out + noise - hp_in)
		hp_in = noise
		hp_out = hp
		band += (hp - band) * (1.0 - exp(-TAU * 6000.0 * pitch * dt))
		if rng.randf() < 0.012: crinkle = rng.randf_range(.4, 1.0)
		crinkle *= exp(-dt * 90.0)
		var rustle := band * (crinkle + .08) * (exp(-t * 6.5) * minf(1.0, t / .02))
		out[index] = thump * 1.0 + body * .55 + rustle * .9
	return out


## Lata/tambor de chapa fina: estalo de ataque e modos inarmônicos (razões de casca cilíndrica)
## que soam ~0,9 s; o mais grave dura mais, os agudos morrem rápido, como uma lata de verdade.
static func _can(take_seed: int, pitch: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = take_seed
	var frames := int(RATE * .95)
	var dt := 1.0 / RATE
	var out := PackedFloat32Array()
	out.resize(frames)
	var base := rng.randf_range(330.0, 420.0) * pitch
	var ratios := [1.0, 1.59, 2.31, 3.17, 4.08, 5.37]
	var decays := [5.0, 7.0, 9.5, 13.0, 17.0, 24.0]
	var gains := [1.0, .7, .55, .4, .3, .22]
	var phases := []
	for index in ratios.size(): phases.append(rng.randf_range(0.0, TAU))
	var detune := []
	for index in ratios.size(): detune.append(rng.randf_range(.985, 1.015))
	var click := 0.0
	for index in frames:
		var t := index * dt
		var ring := 0.0
		for mode in ratios.size():
			var freq: float = base * float(ratios[mode]) * float(detune[mode])
			ring += sin(TAU * freq * t + float(phases[mode])) * float(gains[mode]) * exp(-t * float(decays[mode]))
		var noise := rng.randf_range(-1.0, 1.0)
		click += (noise - click) * (1.0 - exp(-TAU * 3500.0 * dt))
		var attack := click * exp(-t * 160.0) * 1.4
		# Batida grave do fundo do tambor, curta.
		var thud := sin(TAU * 120.0 * pitch * t) * exp(-t * 26.0) * .6
		out[index] = (ring * .42 + attack + thud) * minf(1.0, t / .0015)
	return out


## Plástico duro oco: toc seco com duas ressonâncias baixas e rápidas, sem cauda metálica.
static func _plastic(take_seed: int, pitch: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = take_seed
	var frames := int(RATE * .3)
	var dt := 1.0 / RATE
	var out := PackedFloat32Array()
	out.resize(frames)
	var f1 := rng.randf_range(260.0, 330.0) * pitch
	var f2 := f1 * rng.randf_range(2.4, 2.8)
	var low := 0.0
	var low2 := 0.0
	for index in frames:
		var t := index * dt
		var noise := rng.randf_range(-1.0, 1.0)
		low += (noise - low) * (1.0 - exp(-TAU * 1800.0 * dt))
		low2 += (low - low2) * (1.0 - exp(-TAU * 1800.0 * dt))
		var knock := low2 * exp(-t * 70.0) * 2.0
		var hollow := sin(TAU * f1 * t) * exp(-t * 30.0) + sin(TAU * f2 * t) * exp(-t * 45.0) * .5
		var thud := sin(TAU * 95.0 * pitch * t) * exp(-t * 35.0) * .5
		out[index] = (knock + hollow * .6 + thud) * minf(1.0, t / .001)
	return out


## Normaliza com 3 dB de folga (o pool de contato tem limitador em -6 dB) e desce os últimos
## 20 ms a zero para a tomada acabar sem clique.
static func _wav(mix: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.0
	for sample in mix: peak = maxf(peak, absf(sample))
	var gain := .7 / maxf(peak, .001)
	var frames := mix.size()
	var fade := int(RATE * .02)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	for index in frames:
		var tail := minf(1.0, float(frames - index) / fade)
		bytes.encode_s16(index * 2, clampi(int(mix[index] * gain * tail * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream
