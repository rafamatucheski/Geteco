extends Node3D
## Cidade viva em Harbor. Queixa de playtest (21/10/2026): "a cidade parece morta, não dá pra
## ouvir os outros carros, as pessoas andando, as pessoas falando". Três camadas novas, com teto
## fixo de vozes, montadas uma vez em `_ready` (sob a cortina, dentro de WorldAudio) e
## reaproveitadas: nenhum nó novo por passo, fala ou burburinho.
##  - passos dos pedestres a até 14 m (no máximo 6 seguidos, 4 vozes);
##  - burburinho espacial (1 voz) no centro de quem anda por perto, mais forte com mais gente;
##  - falas curtas já gravadas de civis (1 voz), de vez em quando, num pedestre próximo.
## Além disso define a mixagem dos leitos de WorldAudio (trânsito, gente, rua, brisa, porto) e
## dos detalhes pontuais (gaivota, buzina) quando ligada.
##
## Por que o volume é medido do JOGADOR: o ouvinte do Godot é a câmera, ~36 m acima/atrás dele
## (`CameraRig.EXTERIOR_OFFSET`). Com atenuação nativa, tudo na calçada já nascia a 30–45 m do
## ouvinte e o max_distance cortava o resto. Como em `Gameplay._hearing_gain_db` e em
## `ActorDialogueVoice`, a posição só dá o panorama e a perda por distância é calculada aqui.
##
## Interruptor de A/B: GETECO_CITY_LIFE_AUDIO=0 desliga tudo isto, os leitos novos (rua, brisa) e
## devolve a mixagem antiga dos leitos, dos detalhes e do motor do trânsito (NearbyVehicleAudio).
## Custo esperado (estimativa por contagem de operações, NÃO medido em release): a seleção a cada
## 0,2 s percorre `world.people` (≤ 60 atores, distância ao quadrado) ~0,02–0,05 ms; por quadro,
## ≤ 6 pedestres seguidos e 6 vozes ~0,01–0,02 ms. Mixagem: no máximo 6 vozes 3D sem atenuação
## nativa e sem consulta de Area3D (`area_mask = 0`) + 2 leitos não posicionais em WorldAudio.
## Falas: WAVs pedidos em thread desde o carregamento e retidos; nunca `load()` síncrono no jogo.
const V1_AUDIO := preload("res://audio/v1_ambience/V1AudioCatalog.gd")
const SURFACES := preload("res://audio/v1_ambience/SurfaceResolver3D.gd")
const PROFILES := preload("res://audio/v1_ambience/AmbienceProfile.gd")
const CADENCE := preload("res://audio/FootstepCadence.gd")
const FIREFLY := preload("res://audio/FireflyBank.gd")
const DIRECTED := preload("res://audio/DirectedVoiceBank.gd")
const BINDING := preload("res://audio/VoiceActorBinding.gd")
const EXPRESSIVE := preload("res://audio/ExpressiveVoice.gd")
const DIALOGUE := preload("res://audio/ActorDialogueVoice.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const SWITCH := "GETECO_CITY_LIFE_AUDIO"
## Só Harbor por enquanto: serra e deserto têm leitos e superfícies próprios.
const REGIONS := ["harbor"]
const SELECTION_INTERVAL := 0.2

## Passos: até 1,5 m soam no nível dos passos do jogador (-17 dB menos ~15 dB da câmera em
## WorldAudio), somem em 14 m. 6 pedestres a ~2 passos/s com amostras de 0,15 s dão ~2 vozes
## simultâneas em média: 4 sobram; passo sem voz livre é descartado, nunca cria voz nova.
const STEP_RANGE := 14.0
const STEP_NEAR := 1.5
const STEP_VOLUME_DB := -31.0
const MAX_WALKERS := 6
const STEP_VOICES := 4
const STEP_SURFACES := ["concrete", "wet", "grass", "grass_wet"]

## Burburinho (leito "crowd" do ElevenLabs, -26 dBFS rms): grupo de 5+ a ~5 m fica perto de
## -34 dBFS, abaixo das falas e acima dos passos; uma pessoa sozinha não faz burburinho.
const MURMUR_RANGE := 20.0
const MURMUR_NEAR := 4.0
const MURMUR_REACH := 28.0
const MURMUR_VOLUME_DB := -6.0

## Falas: o banco dirigido normaliza diálogo em ~-20 LUFS (+10 dB do bus SFX). Conversa ouvida
## de passagem fica 16 dB abaixo do diálogo, some em 22 m. Uma por vez, a cada 9–20 s, nunca a
## mesma pessoa duas vezes em 60 s, nunca com estrela de procurado, tiro ou explosão recentes.
const CHATTER_RANGE := 12.0
const CHATTER_NEAR := 2.0
const CHATTER_REACH := 22.0
const CHATTER_VOLUME_DB := -16.0
const CHATTER_INTERVAL := Vector2(9.0, 20.0)
const CHATTER_SPEAKER_COOLDOWN := 60.0
const CHATTER_MAX_DRIVE_SPEED := 8.0
const ALARM_SECONDS := 25.0
const PERSONALITIES := ["friendly", "reserved", "nervous"]
const LANGUAGES := ["pt_BR", "en"]
## Só frases que fazem sentido ouvidas na calçada (conversa, telefone). Ficam de fora as de
## arma, susto e ameaça. A disponibilidade por idioma/voz vem do banco dirigido: hoje há falas
## masculinas em português e femininas em inglês; o que for gravado depois entra sozinho.
const CHATTER_TEXTS := [
	"Oi. Tudo bem?",
	"Opa, tudo certo? Bom te ver por aqui.",
	"Tá tudo bem por aqui. Obrigado por perguntar.",
	"Ha! Essa foi boa. Eu precisava rir um pouco.",
	"Dia corrido, mas uma conversa boa sempre ajuda.",
	"Só quero terminar o dia em paz.",
	"Hoje estou sem cabeça pra brincadeira.",
	"Essa peça está me dando trabalho. Vai ser bom ver tudo funcionando.",
	"Papelada não acaba nunca. E você, como está levando o dia?",
	"Estava falando com o pessoal de casa. É bom saber que está tudo bem.",
	"Estou conferindo as coisas. Se eu me perder na conta, começo de novo.",
	"Achei uma leitura boa. Só falta um pouco de sossego pra terminar.",
	"Já entendi. Preciso voltar ao que estava fazendo.",
	"Pode falar.",
	"Só um instante.",
]

## Leitos de WorldAudio com a cidade viva (bus Ambient, sem ganho). Medido pelo decodificador do
## Godot (21/10): leitos do ElevenLabs -26 dBFS rms; rua/vento originais da V1 -23. Com os
## deslocamentos antigos (-10/-12) e os pesos do perfil, gente e trânsito ficavam em -55 a -60
## dBFS, inaudíveis. Alvo numa rua movimentada: trânsito ~-32, gente ~-35, rua ~-41, brisa ~-35
## (litoral) a ~-43 (miolo); porto ~-34.
const BED_OFFSETS := {"traffic":-6.0, "city":-2.0, "street":-13.0, "breeze":-12.0, "port":-6.0, "dockside":-4.0}
## Detalhes pontuais de WorldAudio ouvidos do jogador: nível (bus Ambient) para ~-32 a -40 dBFS
## rms depois da distância. Antes, pela câmera, chegavam ~24 dB abaixo do nominal ou cortados.
const DETAIL_VOLUME_DB := {"ship_horn":-18.0, "gull":-11.0, "clang":-13.0, "buoy":-8.0, "dog":-14.0,
	"birds":-15.0, "scrap":-13.0, "car_horn":-19.0}

var world
var rng := RandomNumberGenerator.new()
var _step_voices: Array[AudioStreamPlayer3D] = []
## instance_id -> {"ref", "travelled", "accum", "surface"}
var _walkers: Dictionary = {}
var _murmur: AudioStreamPlayer3D
var _murmur_gain := 0.0
var _murmur_target := 0.0
var _murmur_point := Vector3.ZERO
var _murmur_goal := Vector3.ZERO
var _chatter: AudioStreamPlayer3D
var _chatter_speaker: WeakRef
var _chatter_gain_db := 0.0
var _chatter_clock := 6.0
var _chatter_heard: Dictionary = {}
var _chatter_last_path := ""
## idioma -> gênero -> personalidade -> [{"path", "gain_db"}]
var _lines: Dictionary = {}
var _pending_loads: PackedStringArray = PackedStringArray()
var _streams: Dictionary = {}
var _selection_clock := 0.0
var _clock := 0.0
var _alarm_until := -1000.0
var _gameplay_linked := false
var _active := false
var _on_foot := true
var _raining := false
var _focus := 1.0
var _steps_played := 0
var _steps_dropped := 0
var _chatter_played := 0
var _peak_step_voices := 0

static func enabled() -> bool:
	return OS.get_environment(SWITCH).to_lower() not in ["0", "false", "off", "no"]

## Perda por distância medida do jogador: até `near` m 0 dB, rampa linear até zero em `reach`.
static func hearing_db(distance: float, near: float, reach: float) -> float:
	var fraction := 1.0 - maxf(0.0, distance - near) / maxf(reach - near, 0.1)
	return linear_to_db(fraction) if fraction > 0.001 else -80.0

## Voz 3D só com panorama: o volume por distância é de quem chama.
static func make_player_relative(voice: AudioStreamPlayer3D) -> void:
	voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	voice.max_distance = 0.0
	voice.panning_strength = 0.6
	# O filtro de atenuação usa o ganho total (inclui volume_db): voz baixa ficava abafada.
	voice.attenuation_filter_db = 0.0
	# O jogo não usa Area3D de áudio; poupa a consulta de física por voz.
	voice.area_mask = 0

static func player_relative_voice(label: String, bus: StringName) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.name = label
	voice.max_polyphony = 1
	voice.bus = bus if AudioServer.get_bus_index(bus) >= 0 else &"Master"
	make_player_relative(voice)
	return voice

## Detalhe pontual de WorldAudio (um emissor só): no exterior de Harbor, ouvido do jogador; nos
## interiores e nas outras regiões, a atenuação nativa de sempre.
static func configure_detail(voice: AudioStreamPlayer3D, player_relative: bool) -> void:
	if player_relative:
		make_player_relative(voice)
		return
	voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	voice.panning_strength = 1.0
	voice.attenuation_filter_db = -24.0
	voice.area_mask = 1

static func detail_volume_db(kind: String, legacy_db: float) -> float:
	return float(DETAIL_VOLUME_DB.get(kind, legacy_db))

## Ajusta os alvos dos leitos de WorldAudio (chamado a cada 0,25 s). O trânsito passa a seguir os
## carros por perto, não a quantidade de pedestres (antes era `city * 0,8`); o piso de 35% é a
## cidade distante, que nunca some na rua. Fora de Harbor ou num interior, nada muda além de
## silenciar os dois leitos novos.
static func shape_beds(targets: Dictionary, region: String, place: String, point: Vector3, dark: bool, traffic_presence: float) -> void:
	if region not in REGIONS or not place.is_empty():
		targets["street"] = 0.0
		targets["breeze"] = 0.0
		return
	var urban := PROFILES.harbor_urban_weight(point)
	var coast := PROFILES.harbor_coast_weight(point)
	targets["traffic"] = urban * (0.35 + 0.65 * clampf(traffic_presence, 0.0, 1.0)) * (0.7 if dark else 1.0)
	targets["street"] = urban * (0.4 if dark else 0.55)
	targets["breeze"] = 0.4 + 0.6 * clampf(coast, 0.0, 1.0)

func _ready() -> void:
	rng.randomize()
	var began := STALL_WORK.begin()
	for index in STEP_VOICES:
		var voice := player_relative_voice("PedestrianStep%d" % index, &"SFX")
		add_child(voice)
		_step_voices.append(voice)
	_murmur = player_relative_voice("StreetMurmur", &"Ambient")
	var takes := FIREFLY.count("ambience_el", "crowd")
	if takes > 0: _murmur.stream = FIREFLY.loop("ambience_el", "crowd_%d.wav" % rng.randi_range(0, takes - 1))
	add_child(_murmur)
	_chatter = player_relative_voice("StreetChatter", &"SFX")
	add_child(_chatter)
	# Tudo que pode tocar no meio do jogo fica lido e retido agora, sob a cortina: passos (7 KB
	# cada), gaivota/cão dos detalhes da cidade e as buzinas distantes.
	for surface in STEP_SURFACES:
		for variant in 4: V1_AUDIO.footstep(surface, variant)
	for kind in ["gull", "dog"]:
		for variant in 3: V1_AUDIO.detail(kind, variant)
	FIREFLY.all("vehicle_fx", "car_horn")
	_prepare_chatter()
	STALL_WORK.finish_slow("audio.city_life.prepare", began, 2000, self)

func _exit_tree() -> void:
	var voices: Array = [_murmur, _chatter]
	voices.append_array(_step_voices)
	for voice in voices:
		if not is_instance_valid(voice): continue
		voice.stop()
		voice.stream = null
	_walkers.clear()
	_chatter_speaker = null
	# Libera os pedidos já concluídos; um ainda em leitura termina sozinho na thread.
	for path in _pending_loads:
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(path)
	_pending_loads.clear()
	_streams.clear()

## Resolve, uma vez, quais falas neutras têm gravação válida por idioma e voz, e pede os WAVs
## em thread. O índice do banco dirigido é lido aqui (sob a cortina) se ninguém leu antes.
func _prepare_chatter() -> void:
	if not DIRECTED.enabled(): return
	var requested: Dictionary = {}
	for language in LANGUAGES:
		var by_gender: Dictionary = {}
		for gender in ["male", "female"]:
			var by_personality: Dictionary = {}
			for personality in PERSONALITIES:
				var persona := "civilian %s %s" % [personality, gender]
				var takes: Array = []
				for text in CHATTER_TEXTS:
					var row := DIRECTED.canonical(text, persona)
					# Identidade e gênero vêm do elenco (o mesmo filtro de ActorDialogueVoice.speak).
					var person := DIRECTED.profile(row)
					if person.is_empty() or str(person.get("gender", "")) != gender: continue
					var take := DIRECTED.resolve(row, language, str(person.character_id), str(row.get("source_section", "")))
					if take.is_empty(): continue
					var gain := clampf(float(take.get("playback_gain_db", take.get("directed_gain_db", 0.0))), -24.0, 12.0)
					var options: Array = [{"path": str(take.path), "gain_db": gain}]
					var variants: Variant = take.get("variants", [])
					if variants is Array:
						for variant in variants:
							if not variant is Dictionary: continue
							var path := str(variant.get("path", ""))
							if not path.begins_with("res://audio/mission_voices/directed/") or ".." in path: continue
							options.append({"path": path, "gain_db": clampf(float(variant.get("playback_gain_db", gain)), -24.0, 12.0)})
					for option in options:
						var path: String = option.path
						if requested.has(path):
							takes.append(option)
							continue
						if not ResourceLoader.exists(path, "AudioStream"): continue
						requested[path] = true
						if ResourceLoader.has_cached(path):
							_streams[path] = ResourceLoader.load(path, "AudioStream")
						elif ResourceLoader.load_threaded_request(path, "AudioStream") == OK:
							_pending_loads.append(path)
						else: continue
						takes.append(option)
				if not takes.is_empty(): by_personality[personality] = takes
			if not by_personality.is_empty(): by_gender[gender] = by_personality
		_lines[language] = by_gender

func _process(delta: float) -> void:
	_clock += delta
	_selection_clock -= delta
	if _selection_clock <= 0.0:
		_selection_clock = SELECTION_INTERVAL
		var began := STALL_WORK.begin()
		_select()
		STALL_WORK.finish_slow("audio.city_life.select", began, 2000, self)
	if not _active: return
	if not is_instance_valid(world.player):
		_active = false
		_silence()
		return
	var origin: Vector3 = world.player.global_position
	if _on_foot: _update_steps(origin)
	_update_murmur(origin, delta)
	_update_chatter(origin, delta)

func _select() -> void:
	_poll_loads()
	_link_gameplay()
	var was_active := _active
	_active = _can_run()
	if not _active:
		if was_active: _silence()
		return
	var session = world.session
	_focus = 0.35 if session.dialogue_open else (0.62 if session.modal else 1.0)
	_on_foot = world.driving == null or not world.driving.occupied
	var weather = session.weather
	_raining = weather != null and int(weather.weather_state) in [1, 2]
	var origin: Vector3 = world.player.global_position
	var candidates: Array = []
	var murmur_sum := Vector3.ZERO
	var murmur_count := 0
	for actor in world.people:
		if not _present(actor): continue
		var offset: Vector3 = actor.global_position - origin
		offset.y = 0.0
		var distance_squared := offset.length_squared()
		var calm: bool = actor.get("controlled_automatically") != true
		if calm and distance_squared < MURMUR_RANGE * MURMUR_RANGE:
			murmur_sum += actor.global_position
			murmur_count += 1
		if _on_foot and distance_squared < STEP_RANGE * STEP_RANGE and &"travelled" in actor:
			var velocity: Vector3 = actor.velocity
			if velocity.x * velocity.x + velocity.z * velocity.z > 0.09:
				candidates.append([distance_squared, actor])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var keep: Dictionary = {}
	for index in mini(MAX_WALKERS, candidates.size()):
		var actor: Node3D = candidates[index][1]
		var id := actor.get_instance_id()
		keep[id] = true
		if not _walkers.has(id):
			# Fase inicial sorteada: dois pedestres lado a lado não pisam juntos.
			_walkers[id] = {"ref": weakref(actor), "travelled": float(actor.get("travelled")), "accum": rng.randf_range(0.0, 0.6), "surface": "concrete"}
		_walkers[id].surface = _surface_at(actor.global_position)
	for id in _walkers.keys():
		if not keep.has(id): _walkers.erase(id)
	var calm_city := _clock >= _alarm_until and _stars() == 0
	if murmur_count >= 2:
		_murmur_goal = murmur_sum / murmur_count
		if _murmur_gain <= 0.003: _murmur_point = _murmur_goal
	_murmur_target = clampf((murmur_count - 1) / 4.0, 0.0, 1.0) * (1.0 if calm_city else 0.0) * (0.6 if _dark() else 1.0)
	_chatter_clock -= SELECTION_INTERVAL
	if _chatter_clock <= 0.0 and not _chatter.playing:
		_chatter_clock = rng.randf_range(CHATTER_INTERVAL.x, CHATTER_INTERVAL.y)
		if calm_city and _focus >= 0.8 and _chatter_allowed_by_vehicle(): _try_chatter(origin)

func _can_run() -> bool:
	if world == null or not is_instance_valid(world.player) or not world.player.is_inside_tree(): return false
	var session = world.session
	if session == null or session.state == null: return false
	if str(session.state.region_id) not in REGIONS or not str(session.state.place_id).is_empty(): return false
	return true

func _present(actor: Variant) -> bool:
	if not is_instance_valid(actor) or not actor is Node3D or actor.is_queued_for_deletion(): return false
	if not actor.is_visible_in_tree() or actor.get("dead") == true or actor.get("is_player") == true: return false
	var health: Variant = actor.get("health")
	return not ((health is float or health is int) and health <= 0)

func _surface_at(point: Vector3) -> String:
	var surface := SURFACES._geographic_surface("harbor", point)
	if not _raining: return surface
	if surface == "concrete": return "wet"
	if surface in ["grass", "dirt"]: return surface + "_wet"
	return surface

func _update_steps(origin: Vector3) -> void:
	var playing := 0
	for voice in _step_voices:
		if voice.playing: playing += 1
	for id in _walkers:
		var walker: Dictionary = _walkers[id]
		var actor := walker.ref.get_ref() as CharacterBody3D
		if not is_instance_valid(actor): continue
		var travelled := float(actor.get("travelled"))
		var moved := travelled - float(walker.travelled)
		walker.travelled = travelled
		# Parado, ou teleporte/respawn: sem passo e sem acumular.
		if moved <= 0.0 or moved > 2.0: continue
		walker.accum = float(walker.accum) + moved
		var stride := CADENCE.stride(Vector2(actor.velocity.x, actor.velocity.z).length())
		if float(walker.accum) < stride: continue
		walker.accum = fmod(float(walker.accum), stride)
		if not actor.is_on_floor(): continue
		if _play_step(actor, str(walker.surface), origin): playing += 1
	_peak_step_voices = maxi(_peak_step_voices, playing)

func _play_step(actor: Node3D, surface: String, origin: Vector3) -> bool:
	var offset := actor.global_position - origin
	offset.y = 0.0
	var gain := hearing_db(offset.length(), STEP_NEAR, STEP_RANGE)
	if gain <= -60.0: return false
	var voice: AudioStreamPlayer3D = null
	for candidate in _step_voices:
		if not candidate.playing:
			voice = candidate
			break
	if voice == null:
		_steps_dropped += 1
		return false
	var stream := V1_AUDIO.footstep(surface, rng.randi_range(0, 3))
	if stream == null: return false
	voice.stream = stream
	voice.global_position = actor.global_position + Vector3.UP * 0.05
	voice.pitch_scale = V1_AUDIO.footstep_pitch(surface) * rng.randf_range(0.94, 1.06)
	# Pé esquerdo e direito nunca batem igual (mesmo jitter dos passos do jogador).
	voice.volume_db = STEP_VOLUME_DB + gain + linear_to_db(_focus) + rng.randf_range(-1.5, 1.5)
	voice.play()
	_steps_played += 1
	return true

func _update_murmur(origin: Vector3, delta: float) -> void:
	if _murmur.stream == null: return
	_murmur_gain = lerpf(_murmur_gain, _murmur_target, 1.0 - exp(-delta / 1.2))
	_murmur_point = _murmur_point.lerp(_murmur_goal, 1.0 - exp(-delta * 1.5))
	var offset := _murmur_point - origin
	offset.y = 0.0
	var hearing := hearing_db(offset.length(), MURMUR_NEAR, MURMUR_REACH)
	if _murmur_gain < 0.003 or hearing <= -60.0:
		if _murmur.playing: _murmur.stop()
		return
	_murmur.global_position = _murmur_point + Vector3.UP * 1.5
	_murmur.volume_db = MURMUR_VOLUME_DB + linear_to_db(_murmur_gain) + hearing + linear_to_db(_focus)
	if not _murmur.playing and _murmur_gain > 0.01:
		_murmur.play(rng.randf_range(0.0, maxf(0.0, _murmur.stream.get_length() - 0.5)))

func _update_chatter(origin: Vector3, _delta: float) -> void:
	if not _chatter.playing: return
	var speaker := _chatter_speaker.get_ref() as Node3D if _chatter_speaker != null else null
	if not _speaker_ok(speaker) or _focus < 0.8 or _clock < _alarm_until or not _chatter_allowed_by_vehicle():
		_chatter.stop()
		return
	var offset := speaker.global_position - origin
	offset.y = 0.0
	var hearing := hearing_db(offset.length(), CHATTER_NEAR, CHATTER_REACH)
	if hearing <= -60.0:
		_chatter.stop()
		return
	_chatter.global_position = speaker.global_position + Vector3.UP * 1.55
	_chatter.volume_db = CHATTER_VOLUME_DB + _chatter_gain_db + hearing

## Pedestre calmo, sem reação a perigo, sem estar caído e sem diálogo de verdade tocando nele.
func _speaker_ok(actor: Variant) -> bool:
	if not _present(actor): return false
	if actor.get("controlled_automatically") == true or actor.has_meta("street_down"): return false
	var spoken := (actor as Node).get_node_or_null(DIALOGUE.PLAYER_NAME) as AudioStreamPlayer3D
	return spoken == null or not spoken.playing

func _try_chatter(origin: Vector3) -> void:
	var language := DIRECTED.language(EXPRESSIVE.selected_language())
	var by_gender: Dictionary = _lines.get(language, {})
	if by_gender.is_empty(): return
	var best: Node3D = null
	var best_distance := CHATTER_RANGE * CHATTER_RANGE
	var best_takes: Array = []
	for actor in world.people:
		if not _speaker_ok(actor): continue
		var offset: Vector3 = actor.global_position - origin
		offset.y = 0.0
		var distance_squared := offset.length_squared()
		if distance_squared >= best_distance: continue
		var id: int = actor.get_instance_id()
		if _clock - float(_chatter_heard.get(id, -1000.0)) < CHATTER_SPEAKER_COOLDOWN: continue
		# Gênero do corpo renderizado; nunca uma voz de outro gênero e nunca um palpite.
		var personalities: Dictionary = by_gender.get(BINDING.gender_of(actor), {})
		if personalities.is_empty(): continue
		var keys: Array = personalities.keys()
		keys.sort()
		# Mesmo corpo, mesma voz: a personalidade sai da identidade fixa do pedestre.
		var identity: Variant = actor.get("identity")
		var voice_seed: int = int(identity) if identity is int else id
		var takes: Array = []
		for option in personalities[keys[posmod(voice_seed, keys.size())]]:
			if _streams.has(option.path) and option.path != _chatter_last_path: takes.append(option)
		if takes.is_empty(): continue
		best = actor
		best_distance = distance_squared
		best_takes = takes
	if best == null: return
	var choice: Dictionary = best_takes[rng.randi_range(0, best_takes.size() - 1)]
	_chatter.stream = _streams[choice.path]
	_chatter.pitch_scale = 1.0
	_chatter_gain_db = float(choice.gain_db)
	_chatter_speaker = weakref(best)
	_chatter_heard[best.get_instance_id()] = _clock
	_chatter_last_path = str(choice.path)
	if _chatter_heard.size() > 64:
		for key in _chatter_heard.keys():
			if _clock - float(_chatter_heard[key]) > CHATTER_SPEAKER_COOLDOWN: _chatter_heard.erase(key)
	var offset := best.global_position - origin
	offset.y = 0.0
	_chatter.global_position = best.global_position + Vector3.UP * 1.55
	_chatter.volume_db = CHATTER_VOLUME_DB + _chatter_gain_db + hearing_db(offset.length(), CHATTER_NEAR, CHATTER_REACH)
	_chatter.play()
	_chatter_played += 1

func _chatter_allowed_by_vehicle() -> bool:
	if world.driving == null or not world.driving.occupied: return true
	var car: Variant = world.driving.car
	return is_instance_valid(car) and absf(float(car.get("speed"))) < CHATTER_MAX_DRIVE_SPEED

func _poll_loads() -> void:
	if _pending_loads.is_empty(): return
	var still: PackedStringArray = PackedStringArray()
	for path in _pending_loads:
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			still.append(path)
		elif status == ResourceLoader.THREAD_LOAD_LOADED:
			# Concluído: devolve na hora, sem esperar a leitura.
			var stream := ResourceLoader.load_threaded_get(path) as AudioStream
			if stream != null: _streams[path] = stream
	_pending_loads = still

func _link_gameplay() -> void:
	if _gameplay_linked or world == null: return
	var gameplay: Variant = world.get("gameplay")
	if not is_instance_valid(gameplay): return
	if gameplay.has_signal("weapon_fired"): gameplay.weapon_fired.connect(_on_weapon_fired)
	if gameplay.has_signal("npc_gunfire"): gameplay.npc_gunfire.connect(_on_npc_gunfire)
	if gameplay.has_signal("explosion_occurred"): gameplay.explosion_occurred.connect(_on_explosion)
	_gameplay_linked = true

func _on_weapon_fired(_weapon_id: String, _origin: Vector3) -> void:
	_alarm_until = _clock + ALARM_SECONDS

func _on_npc_gunfire(_origin: Vector3, _direction: Vector3, _shooter: Node) -> void:
	_alarm_until = _clock + ALARM_SECONDS

func _on_explosion(_origin: Vector3, _radius: float, _source: Node) -> void:
	_alarm_until = _clock + ALARM_SECONDS

func _stars() -> int:
	var gameplay: Variant = world.get("gameplay")
	return int(gameplay.get("stars")) if is_instance_valid(gameplay) else 0

func _dark() -> bool:
	var weather = world.session.weather
	if weather == null: return false
	var time := float(weather.time_of_day)
	return time < 0.28 or time > 0.78

func _silence() -> void:
	for voice in _step_voices: voice.stop()
	_murmur.stop()
	_chatter.stop()
	_murmur_gain = 0.0
	_murmur_target = 0.0
	_walkers.clear()

func snapshot() -> Dictionary:
	var steps_playing := 0
	for voice in _step_voices:
		if voice.playing: steps_playing += 1
	var lines: Dictionary = {}
	for language in _lines:
		var count := 0
		for gender in _lines[language]:
			for personality in _lines[language][gender]: count += (_lines[language][gender][personality] as Array).size()
		lines[language] = count
	return {"enabled": true, "active": _active, "walkers": _walkers.size(), "walker_limit": MAX_WALKERS,
		"step_voices": _step_voices.size(), "step_voices_playing": steps_playing, "step_voice_limit": STEP_VOICES,
		"peak_step_voices": _peak_step_voices, "steps_played": _steps_played, "steps_dropped": _steps_dropped,
		"murmur_playing": _murmur.playing, "murmur_gain": _murmur_gain, "murmur_volume_db": _murmur.volume_db,
		"chatter_playing": _chatter.playing, "chatter_played": _chatter_played, "chatter_lines": lines,
		"chatter_streams_ready": _streams.size(), "chatter_streams_pending": _pending_loads.size(),
		"voice_limit": STEP_VOICES + 2, "playing_voices": steps_playing + int(_murmur.playing) + int(_chatter.playing)}
