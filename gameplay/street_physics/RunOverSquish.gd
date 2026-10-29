extends RefCounted
## Som do carro passando por cima de corpo caído (pedido do playtest 29/10: "tem que soltar
## sangue e fazer barulhinho"). Sem amostra externa: as tomadas são sintetizadas numa thread
## (`prewarm`, chamado pelo StreetPhysics no _ready) e ficam retidas; o quadro do primeiro
## esmagamento só escolhe uma tomada e toca num AudioStreamPlayer3D já existente do diretor.
## Mesmo padrão de gameplay/police_response/ground/TirePuncture.gd.

const RATE := 22050
const SECONDS := .42
const TAKES := 3

static var _takes: Array[AudioStreamWAV] = []
static var _task := -1


static func prewarm() -> void:
	if not _takes.is_empty() or _task >= 0: return
	_task = WorkerThreadPool.add_task(_build_takes, false, "Esmagamento de atropelado")


## Sem prewarm (teste isolado) ou thread ainda rodando: espera ou sintetiza aqui. No jogo o
## StreetPhysics pediu as tomadas no carregamento, muito antes do primeiro corpo no chão.
static func take() -> AudioStreamWAV:
	if _takes.is_empty():
		if _task >= 0:
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
		if _takes.is_empty(): _build_takes()
	return _takes[randi() % _takes.size()]


static func takes() -> Array[AudioStreamWAV]:
	return _takes


static func _build_takes() -> void:
	var built: Array[AudioStreamWAV] = []
	for index in TAKES: built.append(_synth(8209 + index * 613, 1.0 + (float(index) - 1.0) * .08))
	_takes = built


## Esmagamento abafado em três camadas, tudo grave porque o som vem de baixo do carro:
## - o baque surdo do pneu subindo e descendo do corpo (seno que cai de ~95 para ~45 Hz);
## - o chapinhar molhado: ruído passa-baixa (~700 Hz) com modulação rápida e irregular;
## - dois ou três estalos curtos e escuros (osso/roupa), sem agudo para não soar como vidro.
static func _synth(take_seed: int, pitch: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = take_seed
	var frames := int(RATE * SECONDS)
	var dt := 1.0 / RATE
	var mix := PackedFloat32Array()
	mix.resize(frames)
	var cracks: Array[float] = []
	for index in rng.randi_range(2, 3): cracks.append(rng.randf_range(.015, .11))
	var phase := 0.0
	var wet := 0.0
	var wet2 := 0.0
	var crack_low := 0.0
	var peak := 0.0
	for index in frames:
		var t := index * dt
		phase += TAU * pitch * (45.0 + 50.0 * exp(-t * 18.0)) * dt
		var thump := sin(phase) * exp(-t * 14.0) * minf(1.0, t / .004)
		var noise := rng.randf_range(-1.0, 1.0)
		# Dois polos em 700 Hz: o chapinhar fica dentro do carro, não na frente da câmera.
		var k := 1.0 - exp(-TAU * 700.0 * pitch * dt)
		wet += (noise - wet) * k
		wet2 += (wet - wet2) * k
		var gurgle := .55 + .45 * sin(TAU * (31.0 + 17.0 * sin(TAU * 5.0 * t)) * t)
		var squelch := wet2 * gurgle * minf(1.0, t / .01) * exp(-t * 9.0) * 2.4
		var crack_in := 0.0
		for at in cracks:
			var since := t - at
			if since >= 0.0 and since < .02: crack_in += noise * exp(-since * 260.0)
		crack_low += (crack_in - crack_low) * (1.0 - exp(-TAU * 1500.0 * dt))
		var sample := thump * .9 + squelch * .8 + crack_low * 1.3
		mix[index] = sample
		peak = maxf(peak, absf(sample))
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	var gain := .9 / maxf(peak, .001)
	# Últimos 25 ms descem a zero: fim de tomada sem clique.
	var fade := int(RATE * .025)
	for index in frames:
		var tail := minf(1.0, float(frames - index) / fade)
		bytes.encode_s16(index * 2, clampi(int(mix[index] * gain * tail * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream
