extends RefCounted
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## Áudio de combate do V2: amostras copiadas do V1 (recarga, impactos, RPG, tiros
## silenciados) e os geradores procedurais que o V1 usava para golpes, faca, taco,
## lança-chamas e arremesso de granada. Nada aqui é efeito novo: são
## as mesmas fórmulas de `ProceduralAudio.gd` e `audio/combat/{Knife,Bat}Audio.gd`.
## Os WAVs são carregados como recursos importados. `load_from_file` funciona
## no editor porque enxerga o arquivo-fonte, mas não é válido como contrato de
## exportação: no PCK o áudio é um recurso importado. O preset inclui o banco.
const AUDIO_DIR := "res://assets/gameplay/audio/"
## Nome do bus para onde vai todo som de combate. `V2Settings` (`runtime/Settings.gd`)
## cria esse bus no `_enter_tree`, mas testes que instanciam `Gameplay.gd` sem
## autoloads (`Gameplay.new()` isolado) não o têm — cai em "Master" nesse caso.
static var SFX_BUS_NAME: String:
	get: return "SFX" if AudioServer.get_bus_index("SFX") != -1 else "Master"
const RELOAD_WEAPONS := ["pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle", "rpg", "flamethrower", "grenade"]
const RELOAD_TAKES := 3
## Tiro/explosão: 5 takes por som, como `audio/acoustic/<arma>_0..4.wav` da V1.
const GUNFIRE_TAKES := 5
## Mesma faixa do `AudioStreamRandomizer` da V1 (`audio/combat/CombatAudioBank.gd`):
## `random_pitch = 1.035` (multiplicador, tom varia entre 1/1.035 e 1.035) e
## `random_volume_offset_db = 0.65` (±0,65 dB por tiro).
const GUNFIRE_PITCH_RANGE := 1.035
const GUNFIRE_VOLUME_JITTER_DB := 0.65
static var _last_gunfire_take: Dictionary = {}
## V1 `WeaponReload.duration`: nunca menos que isto, mesmo com amostra curta.
const MIN_RELOAD := 0.5
static var _wav: Dictionary = {}
static var _generated: Dictionary = {}
static var _reload_seconds: Dictionary = {}
const GUNFIRE_FAMILIES := ["pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle", "rpg", "explosion"]
const SUPPRESSED_FAMILIES := ["pistol", "smg", "shotgun", "ak47", "m4a1", "hunting_rifle"]
const SHORT_FAMILIES := ["hurt", "panic", "impact_concrete", "impact_flesh", "impact_glass", "impact_metal", "impact_wood", "reward_pickup", "reward_cash"]
const SINGLE_SAMPLES := ["reward_weapon.wav", "reward_collectible.wav", "reward_achievement.wav"]

## Load every authored take under the loading curtain, without choosing a take,
## advancing gameplay RNG, starting a voice or changing the no-repeat history.
## Batches are bounded to one family; filesystem work runs on loader threads.
static func prewarm_gameplay_banks(tree: SceneTree) -> void:
	for family in GUNFIRE_FAMILIES:
		await _prewarm_family(family,GUNFIRE_TAKES,tree)
	for family in SUPPRESSED_FAMILIES:
		await _prewarm_family("suppressed_"+family,GUNFIRE_TAKES,tree)
	for family in SHORT_FAMILIES:
		await _prewarm_family(family,RELOAD_TAKES,tree)
	var singles: Array[String] = []
	for key in SINGLE_SAMPLES: singles.append(key)
	await _prewarm_samples(singles,tree)
	# Procedural waveforms also belong to first use, not an active shot/bounce.
	for family in GUN_BODY:
		gun_body(family)
		await tree.process_frame
	punch_swing()
	bat_swing()
	for kind in WHOOSH_SPEC: melee_whoosh(kind)
	for kind in ["punch", "knuckles", "bat", "axe"]:
		for variant in 3: melee_hit(kind, variant)
	for kind in [-1,0,1,2]: knife_sample(kind)
	flamethrower()
	grenade_throw()
	grenade_bounce()
	await tree.process_frame

static func _prewarm_family(prefix: String, count: int, tree: SceneTree) -> void:
	var keys: Array[String] = []
	for index in count: keys.append("%s_%d.wav" % [prefix,index])
	await _prewarm_samples(keys,tree)

static func _prewarm_samples(keys: Array[String], tree: SceneTree) -> void:
	var pending: Array[String] = []
	for key in keys:
		if _wav.has(key): continue
		var path := AUDIO_DIR + key
		if not ResourceLoader.exists(path,"AudioStream") or ResourceLoader.has_cached(path):
			wav(key)
		elif ResourceLoader.load_threaded_request(path,"AudioStream") == OK:
			pending.append(key)
		else:
			wav(key)
	for key in pending:
		var path := AUDIO_DIR + key
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await tree.process_frame
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			_wav[key] = ResourceLoader.load_threaded_get(path) as AudioStream
		else:
			wav(key)

## Retain imported reload banks while the loading curtain is still active.
## Request one weapon's three takes together and fetch only after loading ends.
static func prewarm_reload_banks(tree: SceneTree) -> void:
	for weapon_id in RELOAD_WEAPONS:
		var keys: Array[String] = []
		for index in RELOAD_TAKES:
			var key := "reload/%s_%d.wav" % [weapon_id, index]
			keys.append(key)
		await _prewarm_samples(keys,tree)
		reload_seconds(weapon_id)

## WAV do disco, com cache. Nulo se o arquivo não existir.
static func wav(relative_path: String) -> AudioStream:
	if _wav.has(relative_path): return _wav[relative_path]
	var path := AUDIO_DIR + relative_path
	var began := STALL_WORK.begin()
	var stream := ResourceLoader.load(path, "AudioStream", ResourceLoader.CACHE_MODE_REUSE) as AudioStream if ResourceLoader.exists(path, "AudioStream") else null
	STALL_WORK.finish_slow("combat_audio.load:"+relative_path,began,5000)
	_wav[relative_path] = stream
	return stream

## Um take aleatório de `<prefixo>_<0..2>.wav` (nulo se a família não existir).
static func take(prefix: String, rng: RandomNumberGenerator) -> AudioStream:
	return wav("%s_%d.wav" % [prefix, rng.randi_range(0, RELOAD_TAKES - 1)])

## Take de tiro/explosão entre os 5 disponíveis, sem repetir o take anterior da mesma
## família — replica `AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS` da V1.
static func gunfire_take(prefix: String, rng: RandomNumberGenerator) -> AudioStream:
	var index := rng.randi_range(0, GUNFIRE_TAKES - 1)
	if GUNFIRE_TAKES > 1 and _last_gunfire_take.get(prefix, -1) == index:
		index = (index + 1) % GUNFIRE_TAKES
	_last_gunfire_take[prefix] = index
	return wav("%s_%d.wav" % [prefix, index])

## Variação de tom por disparo (±3,5%), mesma faixa do `random_pitch` da V1.
static func gunfire_pitch(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(1.0 / GUNFIRE_PITCH_RANGE, GUNFIRE_PITCH_RANGE)

## Variação de volume por disparo (±0,65 dB), mesma faixa do `random_volume_offset_db` da V1.
static func gunfire_volume_jitter(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(-GUNFIRE_VOLUME_JITTER_DB, GUNFIRE_VOLUME_JITTER_DB)

## Som de coleta da V1 (`audio/rewards/RewardAudioBank.gd`): "weapon" para arma/
## munição, "pickup" (3 takes) para colete.
static func reward(kind: String, rng: RandomNumberGenerator) -> AudioStream:
	if kind == "weapon": return wav("reward_weapon.wav")
	return wav("reward_pickup_%d.wav" % rng.randi_range(0, 2))

static func reload_take(weapon_id: String, rng: RandomNumberGenerator) -> AudioStream:
	if weapon_id not in RELOAD_WEAPONS: return null
	return wav("reload/%s_%d.wav" % [weapon_id, rng.randi_range(0, RELOAD_TAKES - 1)])

## Duração de recarga como no V1: o take mais longo do banco da arma (mínimo 0,5 s).
## 0 = sem banco (o chamador usa o tempo padrão).
static func reload_seconds(weapon_id: String) -> float:
	if weapon_id not in RELOAD_WEAPONS: return 0.0
	if _reload_seconds.has(weapon_id): return _reload_seconds[weapon_id]
	var seconds := 0.0
	for index in RELOAD_TAKES:
		var stream := wav("reload/%s_%d.wav" % [weapon_id, index])
		if stream != null: seconds = maxf(seconds, stream.get_length())
	var result := maxf(MIN_RELOAD, seconds) if seconds > 0.0 else 0.0
	_reload_seconds[weapon_id] = result
	return result

# --- Geradores procedurais (cópia das fórmulas V1) ------------------------------

static func _make(samples: PackedByteArray, rate: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = samples
	return stream

## `ProceduralAudio.get_punch_swing_stream`: soco, soqueira e taco.
static func punch_swing() -> AudioStream:
	if _generated.has("punch"): return _generated["punch"]
	var rate := 22050
	var count := int(rate * 0.22)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 921
	var last_noise := 0.0
	for i in count:
		var t := float(i) / float(rate)
		last_noise = last_noise * 0.82 + rng.randf_range(-1.0, 1.0) * 0.18
		var whoosh := last_noise * sin(PI * clampf(t / 0.10, 0.0, 1.0)) * exp(-t * 9.0) * 0.55
		var impact_t := maxf(0.0, t - 0.09)
		var thud := sin(TAU * 92.0 * impact_t) * exp(-impact_t * 40.0) * 0.75
		var thud_noise := rng.randf_range(-1.0, 1.0) * exp(-impact_t * 70.0) * 0.25
		data.encode_s16(i * 2, clampi(int(tanh((whoosh + thud + thud_noise) * 1.15) * 0.8 * 32767.0), -32768, 32767))
	_generated["punch"] = _make(data, rate)
	return _generated["punch"]

## `KnifeAudio._sample`: `kind` -1 = ar (golpe no vazio); 0..2 = três contatos surdos.
static func knife_sample(kind: int) -> AudioStream:
	var key := "knife%d" % kind
	if _generated.has(key): return _generated[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 913 + kind
	var rate := 22050
	var count := int(rate * (0.10 if kind < 0 else 0.16))
	var data := PackedByteArray()
	data.resize(count * 2)
	var low := 0.0
	var soft := 0.0
	for i in count:
		var t := float(i) / rate
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.12)
		soft = lerpf(soft, low, 0.12)
		var attack := minf(t / 0.008, 1.0)
		var sample := soft * pow(sin(PI * float(i) / count), 2.0) * 0.75
		if kind >= 0:
			sample = (sin(TAU * (105.0 + kind * 9.0) * t) * 0.42 + soft * 0.8) * exp(-t * 44.0)
			sample *= 1.0 - smoothstep(0.11, 0.16, t)
		data.encode_s16(i * 2, int(clampf(sample * attack, -0.95, 0.95) * 32767))
	_generated[key] = _make(data, rate)
	return _generated[key]

## `BatAudio.swing`: só ar; o contato é tocado apenas quando acerta.
static func bat_swing() -> AudioStream:
	if _generated.has("bat"): return _generated["bat"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 914
	var rate := 22050
	var count := int(rate * 0.32)
	var data := PackedByteArray()
	data.resize(count * 2)
	var low := 0.0
	for i in count:
		var t := float(i) / rate
		low = lerpf(low, rng.randf_range(-1.0, 1.0), 0.18)
		var envelope := smoothstep(0.07, 0.22, t) * (1.0 - smoothstep(0.22, 0.32, t))
		data.encode_s16(i * 2, int(low * envelope * 29000.0))
	_generated["bat"] = _make(data, rate)
	return _generated["bat"]

# --- Golpes corpo a corpo (V2) ---------------------------------------------------
# O "vupt" do ar e o som do acerto são separados: o ar toca quando a arma passa
# (pico no instante do contato, não no aperto do botão) e o acerto só quando atinge.
# Antes o taco usava o som do soco, que já trazia um baque embutido — "acertava"
# mesmo errando — e soco, taco e machado acertavam com o mesmo som de carne.

## Instante do pico do "vupt" dentro da amostra (s): o Gameplay começa a tocar em
## `contato − pico`, para o ar soar mais forte quando a arma passa pelo alvo.
const WHOOSH_PEAK := {"punch": 0.055, "bat": 0.10, "axe": 0.11}
## [duração (s), Hz inicial do filtro, Hz no pico, Hz final, ressonância, ganho].
const WHOOSH_SPEC := {
	"punch": [0.16, 700.0, 1900.0, 900.0, 0.55, 0.85],
	"bat": [0.26, 380.0, 1250.0, 420.0, 0.62, 1.0],
	"axe": [0.28, 300.0, 1050.0, 360.0, 0.70, 1.0],
}

## Ar cortado por punho, taco ou machado: ruído num filtro passa-banda ressonante cujo
## centro sobe até o pico e cai depois (efeito Doppler da arma passando perto da
## orelha), com envelope assimétrico. O machado tem um zumbido grave da lâmina.
static func melee_whoosh(kind: String) -> AudioStream:
	if not WHOOSH_SPEC.has(kind): kind = "punch"
	var key := "whoosh_" + kind
	if _generated.has(key): return _generated[key]
	var spec: Array = WHOOSH_SPEC[kind]
	var peak: float = WHOOSH_PEAK[kind]
	var rate := 22050
	var duration: float = spec[0]
	var count := int(rate * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var low := 0.0
	var band := 0.0
	for i in count:
		var t := float(i) / float(rate)
		var rise := clampf(t / peak, 0.0, 1.0)
		var fall := clampf((t - peak) / maxf(duration - peak, 0.001), 0.0, 1.0)
		var center: float = lerpf(float(spec[1]), float(spec[2]), rise * rise) if t < peak else lerpf(float(spec[2]), float(spec[3]), fall)
		# Filtro de estado variável (Chamberlin): passa-banda com ressonância `q`.
		var f := 2.0 * sin(PI * center / float(rate))
		var q: float = 1.0 - float(spec[4])
		var noise := rng.randf_range(-1.0, 1.0)
		low += f * band
		var high := noise - low - q * band
		band += f * high
		var envelope := pow(rise, 2.2) if t < peak else pow(1.0 - fall, 1.6)
		var sample := band * envelope * 1.4
		if kind == "axe":
			# Zumbido da cabeça do machado girando: grave, só perto do pico.
			sample += sin(TAU * (95.0 + 60.0 * rise) * t) * envelope * envelope * 0.35
		data.encode_s16(i * 2, clampi(int(tanh(sample * float(spec[5])) * 0.85 * 32767.0), -32768, 32767))
	_generated[key] = _make(data, rate)
	return _generated[key]

## Acerto no corpo, três variações por arma:
## - punch: baque grave que cai de tom + estalo curto de pele (soco e soqueira; a
##   soqueira tem um tinido metálico leve por cima);
## - bat: "toc" oco de madeira (ressonâncias de ~420 e ~1,1 kHz) + baque do corpo;
## - axe: estalo seco da lâmina entrando, corte úmido (ruído médio) e baque pesado,
##   com um tinido metálico curto.
static func melee_hit(kind: String, variant: int) -> AudioStream:
	var key := "hit_%s_%d" % [kind, variant]
	if _generated.has(key): return _generated[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var rate := 22050
	var duration := {"punch": 0.20, "knuckles": 0.22, "bat": 0.32, "axe": 0.38}.get(kind, 0.22) as float
	var count := int(rate * duration)
	var data := PackedByteArray()
	data.resize(count * 2)
	var detune := 1.0 + (variant - 1) * 0.06
	var lp := 0.0
	var lp2 := 0.0
	var band := 0.0
	var low := 0.0
	for i in count:
		var t := float(i) / float(rate)
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.25
		lp2 += (lp - lp2) * 0.18
		var sample := 0.0
		match kind:
			"punch", "knuckles":
				var freq := 88.0 * detune * (1.0 + 0.9 * exp(-t * 55.0))
				var thump := sin(TAU * freq * t) * exp(-t * 26.0)
				var slap := (noise - lp2) * exp(-t * 170.0) * 0.9
				var body := lp2 * 2.2 * exp(-t * 34.0)
				sample = thump * 0.95 + slap + body * 0.5
				if kind == "knuckles":
					sample += sin(TAU * 2350.0 * detune * t) * exp(-t * 60.0) * 0.18 + sin(TAU * 3720.0 * t) * exp(-t * 90.0) * 0.10
			"bat":
				var wood := sin(TAU * 420.0 * detune * t) * exp(-t * 34.0) * 0.55 + sin(TAU * 1130.0 * detune * t) * exp(-t * 60.0) * 0.32
				var knock := (noise - lp) * exp(-t * 260.0) * 0.8
				var freq := 74.0 * detune * (1.0 + 0.7 * exp(-t * 45.0))
				var thud := sin(TAU * freq * t) * exp(-t * 18.0)
				sample = wood + knock + thud * 0.85 + lp2 * 1.6 * exp(-t * 22.0) * 0.4
			"axe":
				var crack := (noise - lp) * exp(-t * 420.0) * 1.1
				# Corte úmido: passa-banda em ~700 Hz por 60 ms.
				var f := 2.0 * sin(PI * 700.0 * detune / float(rate))
				low += f * band
				band += f * (noise - low - 0.45 * band)
				var chop := band * exp(-t * 32.0) * 1.3
				var freq := 62.0 * detune * (1.0 + 0.8 * exp(-t * 40.0))
				var thud := sin(TAU * freq * t) * exp(-t * 14.0)
				var ring := sin(TAU * 2140.0 * detune * t) * exp(-t * 38.0) * 0.16 + sin(TAU * 3390.0 * t) * exp(-t * 55.0) * 0.08
				sample = crack + chop + thud + ring
		var attack := minf(t / 0.0015, 1.0)
		data.encode_s16(i * 2, clampi(int(tanh(sample * attack * 1.1) * 0.9 * 32767.0), -32768, 32767))
	_generated[key] = _make(data, rate)
	return _generated[key]

## Rugido contínuo do lança-chamas em laço sem emenda. A rajada de 0,38 s da V1
## tinha envelope senoidal (zero nas pontas) e era reiniciada só quando acabava:
## segurando o gatilho, o som pulsava "uá-uá" a cada 0,38 s. Aqui o ruído é
## gerado com sobra e o fim é misturado ao começo, então o laço não estala.
## Quem toca para o som ao soltar o gatilho (`Gameplay._update_muzzle_and_flame`).
static func flamethrower() -> AudioStream:
	if _generated.has("flame"): return _generated["flame"]
	var rate := 22050
	var count := int(rate * 1.2)
	var blend := int(rate * 0.12)
	var rng := RandomNumberGenerator.new()
	rng.seed = 922
	var raw := PackedFloat32Array()
	raw.resize(count + blend)
	var lp := 0.0
	var lp_sub := 0.0
	var crackle := 0.0
	for i in count + blend:
		var t := float(i) / float(rate)
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.14
		lp_sub += (noise - lp_sub) * 0.03
		# Estalos esparsos de combustível queimando por cima do rugido.
		if rng.randf() < 0.0016: crackle = rng.randf_range(0.5, 1.0) * (1.0 if rng.randf() < 0.5 else -1.0)
		crackle *= 0.93
		# 10 Hz fecha 12 ciclos inteiros em 1,2 s: a modulação também não emenda torta.
		var roar := (lp * 0.5 + lp_sub * 0.62) * (0.86 + 0.14 * sin(TAU * 10.0 * t))
		raw[i] = roar + (noise - lp) * 0.07 + crackle * 0.35
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var sample := raw[i]
		if i < blend:
			var w := float(i) / float(blend)
			sample = raw[i] * w + raw[count + i] * (1.0 - w)
		data.encode_s16(i * 2, clampi(int(tanh(sample * 0.9) * 0.5 * 32767.0), -32768, 32767))
	var stream := _make(data, rate)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = count
	_generated["flame"] = stream
	return stream

## Corpo de cada calibre: [Hz do baque, decaimento do baque, segundos de cauda, dB relativo ao tiro].
## As gravações de tiro são só o estalo (~0,2 s, quase nada abaixo de 100 Hz):
## sozinhas soavam fracas, principalmente Magnum e escopeta. Esta camada soma
## o soco grave e a cauda difusa de rua. Não há reflexões discretas (eco repetido).
const GUN_BODY := {
	"pistol": [96.0, 40.0, 0.35, -9.0], "magnum": [60.0, 20.0, 0.95, -2.5],
	"smg": [104.0, 46.0, 0.25, -11.0], "shotgun": [56.0, 18.0, 0.85, -2.5],
	"sawed_off": [52.0, 16.0, 0.85, -1.5], "ak47": [78.0, 30.0, 0.55, -6.0],
	"m4a1": [86.0, 34.0, 0.5, -7.0], "hunting_rifle": [58.0, 22.0, 1.1, -3.0],
}

static func gun_body(kind: String) -> AudioStream:
	if not GUN_BODY.has(kind): return null
	var key := "body_" + kind
	if _generated.has(key): return _generated[key]
	var spec: Array = GUN_BODY[kind]
	var rate := 22050
	var tail := float(spec[2])
	var count := int(rate * (tail + 0.05))
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var lp := 0.0
	var lp2 := 0.0
	for i in count:
		var t := float(i) / float(rate)
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.06
		lp2 += (lp - lp2) * 0.06
		# Baque: seno que cai de tom (sensação de pressão), ataque de 2 ms.
		var freq: float = float(spec[0]) * (1.0 + 0.8 * exp(-t * 40.0))
		var thump := sin(TAU * freq * t) * exp(-t * float(spec[1])) * minf(t / 0.002, 1.0)
		# Cauda: ruído grave com envelope que sobe em 25 ms e morre em `tail`.
		var roll := lp2 * 5.0 * smoothstep(0.0, 0.025, t) * exp(-t * 4.6 / tail)
		data.encode_s16(i * 2, clampi(int(tanh(thump * 0.95 + roll * 0.55) * 0.9 * 32767.0), -32768, 32767))
	_generated[key] = _make(data, rate)
	return _generated[key]

## `ProceduralAudio.get_grenade_throw_stream`: pino e sopro do arremesso.
static func grenade_throw() -> AudioStream:
	if _generated.has("grenade"): return _generated["grenade"]
	var rate := 22050
	var count := int(rate * 0.22)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / float(rate)
		var pin_click := sin(TAU * 3400.0 * t) * exp(-t * 220.0) * 0.85
		var swoosh := sin(TAU * (300.0 + 400.0 * t) * t) * exp(-t * 18.0) * 0.50
		data.encode_s16(i * 2, clampi(int((pin_click + swoosh) * 0.70 * 32767.0), -32768, 32767))
	_generated["grenade"] = _make(data, rate)
	return _generated["grenade"]

## Contato curto da granada com piso/parede, derivado do ricochete procedural V1.
static func grenade_bounce() -> AudioStream:
	if _generated.has("grenade_bounce"): return _generated["grenade_bounce"]
	var rate := 22050
	var count := int(rate * 0.085)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 947
	for i in count:
		var t := float(i) / float(rate)
		# Corpo de ferro fundido no chão: baque grave + tinido curto. Só o tinido
		# (e ainda tocado com tom 1,5–2x) soava como sininho.
		var thud := sin(TAU * 170.0 * t) * exp(-t * 55.0)
		var ping := sin(TAU * (880.0 - 260.0 * t) * t) * exp(-t * 85.0)
		var click := rng.randf_range(-1.0, 1.0) * exp(-t * 140.0) * 0.3
		data.encode_s16(i * 2, clampi(int((thud * 0.5 + ping * 0.3 + click) * 32767.0), -32768, 32767))
	_generated["grenade_bounce"] = _make(data, rate)
	return _generated["grenade_bounce"]
