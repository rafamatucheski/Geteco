extends RefCounted
## Som de combate do Gameplay (tiro, impacto, golpe, grito, recarga, tranco de câmera), separado em
## 31/10 só para o Gameplay.gd caber na leitura: o estado (pools de voz, relógio, RNG) continua no
## Gameplay, porque testes e outros sistemas leem esses campos lá. Gameplay mantém cada função antiga
## como delegação de uma linha, então quem chama por nome (inclusive call()/has_method) não muda.
## `g` fica como Node3D, e não como o script do Gameplay, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: testes sobrescrevem algumas delas numa
## subclasse do Gameplay (_play_stream, _kick_camera, _hit_effect...) e o despacho tem de continuar igual.

const AUDIO = preload("res://gameplay/CombatAudio.gd")
const CATALOG = preload("res://gameplay/WeaponCatalog.gd")
const KATANA_AUDIO := preload("res://gameplay/KatanaAudio.gd")
const MELEE_FOLEY = preload("res://gameplay/MeleeFoley.gd")
const RIG_POSE = preload("res://gameplay/WeaponRigPose.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const WEAPON_SURFACE = preload("res://gameplay/WeaponSurface.gd")
## Os dois valores moram aqui porque são padrão de parâmetro destas funções (padrão precisa ser constante
## local); o Gameplay os reexporta com o mesmo nome. A razão de cada valor está ao lado da reexportação.
const NPC_GUNFIRE_DB := 0.0
const HEARING_DEFAULT := 30.0

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

func _pain_voice(victim: Node3D, amount: float) -> void:
	if victim == null or not is_instance_valid(victim) or amount <= 0.0: return
	if victim.get("dead") == true or (victim.get("health") != null and float(victim.get("health")) <= 0.0): return
	var id := victim.get_instance_id()
	if float(g._pain_next.get(id, -1.0)) > g._combat_clock: return
	var heavy: bool = amount >= 25.0 or g._badly_hurt(victim)
	if g._rng.randf() >= (g.PAIN_CHANCE_HEAVY if heavy else g.PAIN_CHANCE_LIGHT): return
	# Quem não é o Dante grita com a voz gravada do próprio corpo, sem legenda "Ai!" no ar.
	if victim != g.player and g._body_voice(victim, "heavy" if heavy else "light"):
		g._pain_next[id] = g._combat_clock + g.PAIN_COOLDOWN
		return
	if preload("res://audio/DirectedVoiceBank.gd").enabled():
		var binding := preload("res://audio/VoiceActorBinding.gd").pain(victim)
		if binding.is_empty(): return
		g._pain_next[id] = g._combat_clock + g.PAIN_COOLDOWN
		var label := victim.get_node_or_null("PainVoiceCaption") as Label3D
		if label == null:
			label = Label3D.new()
			label.name = "PainVoiceCaption"
			label.position.y = 2.1
			label.font_size = 32
			label.pixel_size = .005
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			victim.add_child(label)
		var spoken := preload("res://audio/ActorDialogueVoice.gd").speak(victim, "Ai!", binding, label)
		label.text = str(spoken.get("message", "Ai!"))
		label.show()
		var generation := int(label.get_meta("voice_generation", 0)) + 1
		label.set_meta("voice_generation", generation)
		g.get_tree().create_timer(maxf(.7, float(spoken.get("duration", 0.0))), false).timeout.connect(Callable(g, "_finish_pain_caption").bind(weakref(label), generation))
		return
	for voice in g._pain_pool:
		if voice.playing: continue
		var stream := AUDIO.take("hurt", g._rng)
		if stream == null: return
		g._pain_next[id] = g._combat_clock + g.PAIN_COOLDOWN
		voice.stream = stream
		voice.global_position = victim.global_position + Vector3.UP
		voice.volume_db = (-6.0 if victim == g.player else -11.0) + g._hearing_gain_db(victim.global_position, HEARING_DEFAULT)
		voice.pitch_scale = 1.0 if victim == g.player else 0.97
		voice.play()
		return

## Abaixo de 40% da vida o grito já sai forte, mesmo de tiro fraco.
func _badly_hurt(victim: Node3D) -> bool:
	var health_value: Variant = victim.get("health")
	var max_value: Variant = victim.get("max_health")
	return (health_value is float or health_value is int) and (max_value is float or max_value is int) and float(max_value) > 0.0 \
		and float(health_value) / float(max_value) < 0.4

## Grito gravado do corpo (PainVoiceBank): timbre fixo da pessoa, perda por distância do jogador.
func _body_voice(actor: Node3D, kind: String) -> bool:
	var choice: Dictionary = AUDIO.PAIN_BANK.pick(actor, kind, g._rng)
	if choice.is_empty(): return false
	var gain: float = g._hearing_gain_db(actor.global_position, g.HEARING_PAIN)
	if gain <= -60.0: return true
	for voice in g._pain_pool:
		if voice.playing: continue
		voice.stream = choice.stream
		voice.global_position = actor.global_position + Vector3.UP * 1.5
		voice.volume_db = float(g.PAIN_VOICE_DB.get(kind, -8.0)) + gain
		voice.pitch_scale = float(choice.pitch)
		voice.play()
		return true
	return true

## Para quem fere por fora do tiro (atropelamento em StreetPhysics): "light", "heavy" ou "death".
## false = corpo sem voz gravada (gênero desconhecido); quem chama segue com o som que já tinha.
func person_voice(actor: Node3D, kind: String) -> bool:
	if kind == "death":
		if not is_instance_valid(actor) or actor.has_meta("death_voiced"): return true
		if AUDIO.PAIN_BANK.pick(actor, "death", g._rng).is_empty(): return false
		g._death_voice(actor)
		return true
	return g._body_voice(actor, kind)

## Grito de quem acabou de morrer (tiro, golpe, explosão, fogo). Uma vez por corpo e no
## máximo DEATH_VOICES_PER_SECOND por segundo: a explosão que derruba cinco não vira coro.
func _death_voice(actor: Node3D) -> void:
	if not is_instance_valid(actor) or actor == g.player or actor.has_meta("death_voiced"): return
	actor.set_meta("death_voiced", true)
	if g._combat_clock - g._death_voice_window >= 1.0:
		g._death_voice_window = g._combat_clock
		g._death_voices_in_window = 0
	if g._death_voices_in_window >= g.DEATH_VOICES_PER_SECOND or g._rng.randf() >= g.DEATH_VOICE_CHANCE: return
	if g._body_voice(actor, "death"): g._death_voices_in_window += 1

func _finish_pain_caption(reference: WeakRef, generation: int) -> void:
	var label := reference.get_ref() as Label3D
	if not is_instance_valid(label) or int(label.get_meta("voice_generation", 0)) != generation: return
	var remaining := preload("res://audio/ActorDialogueVoice.gd").remaining_for(label)
	if remaining > 0:
		g.get_tree().create_timer(remaining, false).timeout.connect(Callable(g, "_finish_pain_caption").bind(reference, generation))
	else: label.hide()

## Tiro/explosão: 5 takes sem repetir o anterior + variação de tom e volume por disparo,
## como o `AudioStreamRandomizer` da V1 (`audio/combat/CombatAudioBank.gd`: random_pitch=1.035,
## random_volume_offset_db=0.65). Sem essa variação todo tiro soava idêntico — uma das
## diferenças perceptíveis de "efeito diferente" entre V1 e V2.
func _sound(kind: String, point: Vector3, base_volume_db: float = NPC_GUNFIRE_DB) -> void:
	var began := STALL_WORK.begin()
	g._stall_sound(kind,point,base_volume_db)
	STALL_WORK.finish_slow("gameplay.sound:"+kind,began,10000,g)

func _stall_sound(kind: String, point: Vector3, base_volume_db: float = NPC_GUNFIRE_DB) -> void:
	var stream := AUDIO.gunfire_take(kind, g._rng)
	if stream == null: return
	var reach: float = g.HEARING_EXPLOSION if kind == "explosion" else g.HEARING_GUNFIRE
	if kind == "pistol_suppressed":
		reach = g.HEARING_SUPPRESSED
		base_volume_db += g.SUPPRESSED_AUTHORED_DB
	var pitch := AUDIO.gunfire_pitch(g._rng) * (AUDIO.variant_pitch(kind) if AUDIO.VARIANT_BASE.has(kind) else 1.0)
	g._play_weapon_stream(stream, point, base_volume_db + AUDIO.gunfire_volume_jitter(g._rng), pitch, reach)
	# Camada de corpo (baque + cauda) no mesmo tom: o estalo gravado sozinho soava fraco.
	var body := AUDIO.gun_body(kind)
	if body != null: g._play_weapon_stream(body, point, base_volume_db + float(AUDIO.GUN_BODY[kind][3]), pitch, reach * 1.3)

## Fixed pools keep gunfire from consuming the glass-break voice or other effects.
func _setup_combat_audio() -> void:
	AUDIO.ensure_weapon_bus()
	for index in g.COMBAT_VOICES:
		var effect: AudioStreamPlayer3D = g._combat_voice(AUDIO.SFX_BUS_NAME)
		g.add_child(effect)
		g._audio_pool.append(effect)
		var weapon: AudioStreamPlayer3D = g._combat_voice(String(AUDIO.WEAPON_BUS_NAME))
		g.add_child(weapon)
		g._weapon_pool.append(weapon)
	for index in 4:
		var glass: AudioStreamPlayer3D = g._combat_voice(AUDIO.SFX_BUS_NAME)
		g.add_child(glass)
		g._glass_audio_pool.append(glass)

func _play_weapon_stream(stream: AudioStream, point: Vector3, volume_db: float, pitch: float = 1.0, reach: float = HEARING_DEFAULT) -> void:
	if stream == null or g._weapon_pool.is_empty(): return
	var gain: float = g._hearing_gain_db(point,reach)
	if gain <= -60.0: return
	var index: int = g._weapon_audio_next
	for offset in g._weapon_pool.size():
		var candidate: int = (g._weapon_audio_next + offset) % g._weapon_pool.size()
		if not g._weapon_pool[candidate].playing:
			index = candidate
			break
	var channel: AudioStreamPlayer3D = g._weapon_pool[index]
	g._weapon_audio_next = (index + 1) % g._weapon_pool.size()
	# At the ceiling replace an old tail, keeping the current shot audible.
	channel.stop()
	channel.global_position = point
	channel.stream = stream
	channel.volume_db = volume_db + gain
	channel.pitch_scale = pitch
	channel.play()

func _play_glass_break(point: Vector3, volume_offset := 0.0, pitch := 1.0) -> void:
	if g._glass_audio_pool.is_empty(): return
	var gain: float = g._hearing_gain_db(point,32.0)
	if gain <= -60.0: return
	var voice: AudioStreamPlayer3D = g._glass_audio_pool[g._glass_audio_next]
	g._glass_audio_next = (g._glass_audio_next + 1) % g._glass_audio_pool.size()
	# Replace only an earlier glass shower at the fixed ceiling, never a new shot.
	voice.stop()
	voice.global_position = point
	voice.stream = AUDIO.impact_take("glass",g._rng)
	if voice.stream == null: voice.stream = preload("res://gameplay/VehicleBreakIn.gd")._glass_stream()
	voice.volume_db = -9.0 + gain + volume_offset
	voice.pitch_scale = g._rng.randf_range(.94,1.06) * pitch
	voice.play()

## Toca um stream já carregado no primeiro canal livre do pool posicional.
func _play_stream(stream: AudioStream, point: Vector3, volume_db: float, pitch: float = 1.0, reach: float = HEARING_DEFAULT) -> void:
	if stream == null: return
	var gain: float = g._hearing_gain_db(point, reach)
	if gain <= -60.0: return
	for channel in g._audio_pool:
		if channel.playing: continue
		channel.global_position = point
		channel.stream = stream
		channel.volume_db = volume_db + gain
		channel.pitch_scale = pitch
		channel.play()
		return

## Som não posicional (coleta de item), como o `RewardAudioBank` da V1.
func _play_ui(stream: AudioStream, volume_db: float) -> void:
	if stream == null or not is_instance_valid(g._ui_audio): return
	g._ui_audio.stream = stream
	g._ui_audio.volume_db = volume_db
	g._ui_audio.play()

## Voz de combate: a posição só dá o panorama esquerda/direita; o volume por
## distância vem de `_hearing_gain_db`.
func _combat_voice(bus: String) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	voice.max_distance = 0.0
	# Era 0,6 (× 0,5 do projeto = 0,3): com o ouvinte 36 m atrás, tiro e grito ficavam no centro.
	voice.panning_strength = 1.0
	voice.bus = bus
	return voice

## Perda por distância medida do JOGADOR, não da câmera: queda linear até zero em
## `reach`, a curva do AudioStreamPlayer2D da V1 (attenuation = 1). Quem atira
## é o próprio jogador → 0 dB.
func _hearing_gain_db(point: Vector3, reach: float) -> float:
	if not is_instance_valid(g.player): return 0.0
	var offset: Vector3 = point - g.player.global_position
	offset.y = 0.0
	var fraction := 1.0 - offset.length() / maxf(reach, 0.1)
	return linear_to_db(fraction) if fraction > 0.001 else -80.0

## Disparo: tiro silenciado usa a amostra `suppressed_*` do V1 (ver SUPPRESSED_V1_DB: o −9 dB
## de `characters/Player.gd` somava com a amostra já baixa e sumia); o resto, o WAV
## da arma na intensidade própria dela (`audio_volume_db` do catálogo — antes ignorado, o
## que fazia toda arma soar no mesmo volume fixo).
func _shot_sound(id: String, data: Dictionary) -> void:
	var base_volume: float = float(data.get("audio_volume_db", -2.0))
	var base_id := str(data.get("model_base",id))
	g._kick_camera(float(data.get("camera_kick",g.CAMERA_KICK.get(id,0.0))))
	if data.get("suppressed", false) and base_id in g.SUPPRESSED_WEAPONS:
		var authored := id == "pistol_suppressed"
		var muffled := AUDIO.gunfire_take(id if authored else "suppressed_" + base_id, g._rng)
		if muffled != null:
			var offset: float = g.SUPPRESSED_AUTHORED_DB if authored and AUDIO.variant_has_shots(id) else g.SUPPRESSED_V1_DB
			g._play_weapon_stream(muffled, g.player.global_position, base_volume + offset + AUDIO.gunfire_volume_jitter(g._rng), AUDIO.gunfire_pitch(g._rng) * (AUDIO.variant_pitch(id) if AUDIO.VARIANT_BASE.has(id) else 1.0), g.HEARING_SUPPRESSED)
			return
	g._sound(String(data.get("sound_type", id)), g.player.global_position, base_volume)

## "Vupt" do golpe. Toca quando a arma passa (pico do som no instante do contato),
## não no aperto do botão: o taco e o machado têm 0,25 s de preparação e o ar soava
## antes de o braço começar a descer. Cada arma tem o seu ar (o taco usava o do soco,
## que trazia um baque embutido e "acertava" mesmo errando).
func _melee_swing_sound(id: String, data: Dictionary) -> void:
	var kind := String(g.MELEE_SOUND_KIND.get(id, "punch"))
	var contact := float(RIG_POSE.MELEE_CONTACT.get(id, 0.14))
	var peak := 0.05 if id == "knife" else float(AUDIO.WHOOSH_PEAK.get(kind, 0.05))
	g._pending_swing = {"id": id, "time": maxf(0.0, contact - peak), "data": data, "serial": g._attack_serial}

func _update_swing_sound() -> void:
	if g._pending_swing.is_empty(): return
	var id: String = g._pending_swing.id
	# Mesmas regras do contato: troca de arma, morte, garagem e transição cancelam.
	if not g.attack_allowed() or (g.equipped() != id and not (id == "fists" and g.equipped().is_empty())):
		g._pending_swing.clear()
		return
	if g._rig_pose.action_age + 0.00001 < float(g._pending_swing.time): return
	var data: Dictionary = g._pending_swing.data
	g._pending_swing = {}
	var stream: AudioStream
	if id == "katana" and g.katana_style().saber: stream = KATANA_AUDIO.stream("swing")
	# Lâminas longas: o ar das gravações do Firefly (audio/katana). O Foley do Codex na katana soava como
	# pancada genérica (usuário, 30/10: "o som tá ruim da katana"); fica para faca, taco e machado.
	elif id in g.NATIVE_SWORDS: stream = KATANA_AUDIO.swing(g._rng.randi_range(0, 2))
	elif id in MELEE_FOLEY.WEAPONS: stream = g._melee_foley.swing(id)
	else: stream = AUDIO.melee_whoosh(String(g.MELEE_SOUND_KIND.get(id, "punch")))
	# V1 `Player._melee_attack`: o volume do catálogo. Tom por golpe do combo (pesado
	# mais grave e mais forte) e um pouco de acaso, para a sequência não soar repetida.
	var heavy := bool(g._melee_action.get("heavy", g._rig_pose.heavy_attack()))
	var pitch: float = g._combo_pitch() * g._rng.randf_range(0.97, 1.03)
	g._play_stream(stream, g.player.global_position, float(data.get("audio_volume_db", -4.0)) + (2.0 if heavy else 0.0), pitch)

## Tom do golpe atual da sequência: o pesado que fecha o combo é o mais grave.
func _combo_pitch() -> float:
	if bool(g._melee_action.get("heavy", g._rig_pose.heavy_attack())): return g.COMBO_HEAVY_PITCH
	return float(g.COMBO_PITCH[g._rig_pose.combo_step % g.COMBO_PITCH.size()])

## Acerto corpo a corpo no corpo: som próprio de cada arma (soco, soqueira, taco,
## machado), mais grave e forte no golpe pesado. A faca mantém os contatos da V1.
func _melee_hit_sound(id: String, actor: Node3D, point: Vector3, amount: float, severed := false) -> void:
	if id in MELEE_FOLEY.WEAPONS and id not in g.NATIVE_SWORDS:
		var material: String = g._impact_material(actor)
		var heavy := bool(g._melee_action.get("heavy", g._rig_pose.heavy_attack()))
		var take: AudioStream = g._melee_foley.hit(id, material, heavy, severed)
		var level := -7.0 if id == "knife" else -4.5
		g._play_stream(take, point, level + (1.0 if heavy else 0.0), g._rng.randf_range(0.97, 1.03), 24.0)
		return
	if id in g.NATIVE_SWORDS:
		# Contato gravado + rasgo, só ao atingir carne; o ar sozinho não toca impacto. Corte de membro
		# soa mais forte e mais grave.
		if not (id == "katana" and g.katana_style().saber) and g._impact_material(actor) == "flesh":
			var heavy := bool(g._melee_action.get("heavy", g._rig_pose.heavy_attack())) or severed
			if severed: g._play_stream(KATANA_AUDIO.cut(g._rng.randi_range(0, 2)), point, 0.0, 0.82)
			g._play_stream(KATANA_AUDIO.cut(g._rng.randi_range(0, 2)), point, -3.0 + (2.0 if heavy else 0.0), g._combo_pitch() * g._rng.randf_range(0.97, 1.03))
			return
		g._play_stream(KATANA_AUDIO.stream("swing") if id == "katana" and g.katana_style().saber else AUDIO.knife_sample(g._rng.randi_range(0, 2)), point, -7.0, 0.7)
		return
	if id == "knife" or g._impact_material(actor) != "flesh" or not g.MELEE_HIT_KIND.has(id):
		if id == "knife" and g._impact_material(actor) == "flesh":
			g._play_stream(AUDIO.knife_sample(g._rng.randi_range(0, 2)), actor.global_position, -13.0)
		else:
			g._impact_sound(actor, point, amount)
		return
	var heavy: bool = g._rig_pose.heavy_attack()
	var volume := float(g.MELEE_HIT_DB.get(id, -6.0)) + (3.0 if heavy else 0.0)
	g._play_stream(AUDIO.melee_hit(String(g.MELEE_HIT_KIND[id]), g._rng.randi_range(0, 2)), point, volume, g._combo_pitch() * g._rng.randf_range(0.96, 1.04))
	# Camada de carne gravada da V1 por baixo, mais baixa: dá corpo ao sintetizado.
	g._play_stream(AUDIO.take("impact_flesh", g._rng), point, volume - 9.0)

func _melee_part_landed(point: Vector3) -> void:
	g._play_stream(g._melee_foley.landing(), point, -12.0, g._rng.randf_range(0.97, 1.03), 16.0)

## Lança-chamas: rajada de 0,38 s reiniciada enquanto o gatilho segue (V1 `_flamethrower_audio`).
func _flame_sound() -> void:
	g._flame_clock = 0.15
	if g._flame_audio.playing: return
	g._flame_audio.stream = AUDIO.flamethrower()
	g._flame_audio.global_position = g.player.global_position
	g._flame_audio.play()

func _play_reload_audio(id: String, multiplier: float) -> void:
	var stream := AUDIO.reload_take(id, g._rng)
	if stream == null: return
	g._reload_audio.stream = stream
	g._reload_audio.global_position = g.player.global_position
	g._reload_audio.pitch_scale = stream.get_length() / maxf(g._reload_total, 0.1) if CATALOG.get_weapon(id).has("reload_duration") else 1.0 / maxf(multiplier, 0.1)
	g._reload_audio.play()

## Tranco curto de câmera no disparo pesado (mesmo recurso do choque de veículo em
## `StreetPhysics`): `h_offset/v_offset` não brigam com o CameraRig. O tranco anterior é
## substituído, não somado, para rajada não virar terremoto.
func _kick_camera(strength: float) -> void:
	if strength <= 0.0 or not is_instance_valid(g.camera): return
	if g._kick_tween != null and g._kick_tween.is_valid(): g._kick_tween.kill()
	g._kick_tween = g.camera.create_tween()
	for step in 4:
		var amount := strength * (1.0 - step / 4.0)
		g._kick_tween.tween_property(g.camera, "h_offset", g._rng.randf_range(-1, 1) * amount, 0.03)
		g._kick_tween.parallel().tween_property(g.camera, "v_offset", g._rng.randf_range(0.2, 1.0) * amount, 0.03)
	g._kick_tween.tween_property(g.camera, "h_offset", 0.0, 0.06)
	g._kick_tween.parallel().tween_property(g.camera, "v_offset", 0.0, 0.06)

func projectile_bounce(point: Vector3, speed: float) -> void:
	if speed < 1.2: return
	g._play_stream(AUDIO.grenade_bounce(), point, -16.0 + clampf(speed - 2.0, 0.0, 6.0), g._rng.randf_range(0.9, 1.12))

## Point and normal distinguish real terrain contact from a wall above it.
func _impact_material(collider: Object, point := Vector3.INF, normal := Vector3.ZERO) -> String:
	return WEAPON_SURFACE.resolve(collider, point, normal)

func _casing_contact(point: Vector3, material: String, speed: float, shotgun: bool) -> void:
	var family := WEAPON_SURFACE.casing_family(material)
	var volume := -20.0 + clampf(speed - 3.0, -4.0, 1.0)
	if family in ["soft", "snow"]: volume -= 11.0
	# Polymer shotgun hulls have less ring than a small brass case.
	if shotgun: volume -= 3.0
	g._play_weapon_stream(AUDIO.contact_take("casing_" + family, g._rng), point, volume, g._rng.randf_range(0.96, 1.04) * (0.8 if shotgun else 1.0), 9.0)

## Som de contato. Impactos do mesmo material no mesmo instante (chumbo) compartilham uma voz, como no V1.
func _impact_sound(collider: Object, point: Vector3, amount: float, normal := Vector3.ZERO) -> void:
	var material: String = g._impact_material(collider, point, normal)
	g._recent_impacts = g._recent_impacts.filter(func(entry): return g._combat_clock - float(entry.time) < g.IMPACT_GROUP_SECONDS)
	for entry in g._recent_impacts:
		if entry.material == material: return
	g._recent_impacts.append({"time": g._combat_clock, "material": material})
	if material == "flesh":
		# A placa do colete segurou este tiro neste mesmo quadro físico (PoliceAgent/_apply_player_damage).
		var vest := collider is Node and int((collider as Node).get_meta("armor_hit_frame", -1)) == Engine.get_physics_frames()
		var body_hit := AUDIO.body_hit_take("vest" if vest else "flesh", g._rng)
		if body_hit != null:
			g._play_stream(body_hit, point, g.BODY_HIT_DB + clampf((amount - 15.0) / 15.0, -1.5, 2.0), g._rng.randf_range(0.94, 1.06), g.HEARING_BODY_HIT)
			return
	g._play_stream(AUDIO.impact_take(material, g._rng), point, -14.0 + clampf((amount - 15.0) / 15.0, -0.8, 2.0))
	# Ricochete: assobio por cima do toc. Era −13 dB só em metal (1 em 3) e quase nunca se ouvia;
	# concreto também desvia bala na rua.
	var ricochet_chance := 0.5 if material == "metal" else (0.2 if material == "concrete" else 0.0)
	if g._rng.randf() < ricochet_chance: g._firefly_sound("weapons_fire", "ricochet", point, -5.0, 40.0, 0.08)

## Sons de combate do Firefly (2026-10-15): pente vazio, sacar/guardar, pino da granada, cauda de
## explosão, ricochete e zunido de bala. Sem o arquivo importado não toca nada, como antes.
func _firefly_sound(folder: String, key: String, point: Vector3, volume_db: float, reach: float, pitch_jitter := 0.04) -> void:
	var take: AudioStream = AUDIO.FIREFLY.take(folder, key, g._rng)
	if take == null: return
	if folder == "weapons_fire":
		g._play_weapon_stream(take, point, volume_db, g._rng.randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter), reach)
	else: g._play_stream(take, point, volume_db, g._rng.randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter), reach)

func _is_firearm(id: String) -> bool:
	var data: Dictionary = CATALOG.WEAPONS.get(id, {})
	return not data.is_empty() and not data.get("is_melee", false) and not data.get("is_grenade", false)

## Troca de arma: katana sai/volta da bainha; arma de fogo sai/volta do coldre (punho livre, melee ou veículo).
func _weapon_switch_sound(from_id: String, to_id: String) -> void:
	if not is_instance_valid(g.player) or from_id == to_id: return
	var at: Vector3 = g.player.global_position
	if to_id == "katana": g._firefly_sound("katana", "draw", at, -8.0, 14.0)
	elif from_id == "katana": g._firefly_sound("katana", "sheath", at, -9.0, 14.0)
	elif g._is_firearm(to_id): g._firefly_sound("weapons_fire", "gun_draw", at, -11.0, 12.0)
	elif g._is_firearm(from_id): g._firefly_sound("weapons_fire", "gun_holster", at, -12.0, 12.0)
