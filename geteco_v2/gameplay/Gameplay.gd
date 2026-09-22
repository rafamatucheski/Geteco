extends Node3D

signal changed
signal message(text: String)
signal player_died
signal crime_reported(points: int)
signal weapon_fired(weapon_id: String, origin: Vector3)
signal explosion_occurred(origin: Vector3, radius: float, source: Node)
const CATALOG = preload("res://gameplay/WeaponCatalog.gd")
const ARSENAL = preload("res://gameplay/ArsenalWeapon3D.gd")
const POSE = preload("res://gameplay/WeaponPoseData.gd")
const OFFICER = preload("res://gameplay/PoliceAgent.gd")
const PROJECTILE = preload("res://gameplay/Projectile.gd")
const CUSTOM = preload("res://gameplay/WeaponCustomization.gd")
const EMERGENCY = preload("res://gameplay/emergency/EmergencyManager.gd")
const AUDIO = preload("res://gameplay/CombatAudio.gd")
const PROTECTION = preload("res://gameplay/DamageProtection.gd")
const EFFECTS = preload("res://gameplay/CombatEffects.gd")
const RIG_POSE = preload("res://gameplay/WeaponRigPose.gd")
## Cheat de arsenal do V1: digitar as letras em sequência (pausa máxima 3 s, buffer de 13).
const CHEAT_ARSENAL := "dukenuke"
const CHEAT_BUFFER := 13
const CHEAT_GAP := 3.0
## Gemido de dor (V1 `PainReaction`): chance 65% se o dano ≥ 25, senão 42%; no máximo 6 vozes e um gemido por
## vítima a cada 1,8 s. Aqui a chance é sorteada uma vez por golpe.
const PAIN_CHANCE_HEAVY := 0.65
const PAIN_CHANCE_LIGHT := 0.42
const PAIN_COOLDOWN := 1.8
const PAIN_VOICES := 6
## Golpe corpo a corpo (V1 `MELEE_SWING_DURATION` = 0,22 s; um pouco mais para o balanço da arma se ler).
const SWING_DURATION := 0.26
## Mira (V1 `Player._physics_process`): `is_aiming` = fire OU aim OU lanterna; `weapon_aim_active` = aim com arma
## de mão que mira (sem punhos, faca, machado, soqueira, taco, granada). O V1 solta a mira ao soltar o botão; aqui
## o corpo segura o rumo por AIM_HOLD depois de cada golpe/disparo (o clique dura um quadro e o corpo piscaria de volta
## para a direção do movimento). Escolha da adaptação, não calibrada.
const AIM_HOLD := 0.3
const NON_AIM_WEAPONS := ["fists", "knife", "axe", "knuckles", "bat", "grenade"]
## Clipes do `dante.glb` para golpes: [clipe, início, fim] em segundos, tocados a 1,0× (sem acelerar). Trechos
## escolhidos medindo a velocidade da mão nas chaves do clipe: `Attack` tem o golpe descendente (pico ~19,7 m/s) em
## t = 1,1 s; `Punch_Forward_with_Both_Fists` estende as mãos à frente em t ≈ 0,95 s. O trecho começa perto do contato
## para o impacto visível acompanhar o dano, que é aplicado no aperto do botão.
const MELEE_CLIPS := {
	"unarmed": ["Punch_Forward_with_Both_Fists", 0.75, 1.3],
	"knuckles": ["Punch_Forward_with_Both_Fists", 0.75, 1.3],
	"knife": ["Attack", 1.0, 1.5],
	"bat": ["Attack", 1.0, 1.5],
	"axe": ["Attack", 1.0, 1.5],
}
## Teclas 1–0 (`weapon_slot_N`): a mesma ordem do V1 (`Player._input`).
const SLOT_ORDER := ["pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "rpg", "flamethrower", "grenade"]
## V1 `Player._trigger_muzzle_flash_3d`: duração do clarão por arma (s).
const HEAVY_FLASH := ["magnum", "shotgun", "sawed_off", "rpg"]
## Agrupa impactos do mesmo material no mesmo instante (chumbo de escopeta), como o V1 (40 ms).
const IMPACT_GROUP_SECONDS := 0.04
## Crime por fonte CONTÍNUA (jato do lança-chamas, fogo aceso pelo jogador): uma denúncia por vítima
## a cada 10 s. O V1 não pontua por golpe: só na morte (20) ou com piso de 2 estrelas ao ferir policial;
## aqui se mantém o valor por golpe do V2 (12 civil / 18 policial), mas sem repeti-lo a 20 Hz.
const CONTINUOUS_CRIME_COOLDOWN := 10.0
## Crime do próprio disparo do lança-chamas: V2 cobrava +4 a cada 0,05 s. Agora +4 por segundo de jato.
const FLAME_SHOT_CRIME_INTERVAL := 1.0
## V1 `FlameJet._apply_fire_damage`: no máximo um dano do jato por alvo a cada 120 ms.
const FLAME_HIT_COOLDOWN := 0.12
## Atropelamento (`report_vehicle_assault`): o V1 denuncia UMA vez por vítima (a vítima sai da colisão e
## fica caída). No V2 a vítima viva continua colidindo e o `Vehicle` chama `receive_damage` a cada quadro
## de contato. Contato sem interrupção maior que isto é o MESMO atropelamento; separação maior = novo.
## Escolha não calibrada: ~60 quadros de física, folga larga contra tremor de contato.
const VEHICLE_CONTACT_GAP := 1.0
## Limpeza periódica dos registros por vítima.
const REGISTER_PRUNE_INTERVAL := 1.0
## Só estas armas têm amostra de tiro silenciado (V1 `ProceduralAudio.get_gunshot_stream`).
const SUPPRESSED_WEAPONS := ["pistol", "smg", "shotgun", "ak47", "m4a1", "hunting_rifle"]
## V1 `GrenadeProjectile.fuse_time` e limites de arremesso (`Player._shoot_towards`: 60 px … `throw_range`).
const GRENADE_FUSE := 2.0
const GRENADE_MIN_THROW := 60.0 / 16.0
## Tempo de voo até o chão com a saída da mão a 1,05 m, vy 5,5 m/s e g 12 m/s² (Projectile.gd).
const GRENADE_AIR_TIME := 1.08
## Fração do alcance pedido em que a granada toca o chão; o quique e o rolamento levam o resto.
const GRENADE_LANDING_SHARE := 0.8
const STAR_THRESHOLDS := [0, 12, 30, 60, 100, 160, 240]
const MAX_ACTIVE := [0, 2, 3, 4, 5, 5, 5]
const DEPLOYMENT := [0, 4, 6, 10, 14, 18, 22]
const DISPATCH := [0.0, 10.0, 8.0, 6.0, 5.0, 4.0, 4.0]
var world: Node3D
var player: CharacterBody3D
var camera: Camera3D
var state: RefCounted
var health := 100.0
var armor := 0.0
var stars := 0
var crime_points := 0
var hidden_time := 0.0
var last_known := Vector3.ZERO
var last_known_valid := false
var police: Array[CharacterBody3D] = []
var deployed := 0
var dispatch_owned := false
var dispatch_timer := 0.0
var cooldown := 0.0
var reload_timer := 0.0
var _reload_total := 0.0
var reloading_id := ""
var aim_point := Vector3.ZERO
var gun: Node3D
var socket: Node3D
var visual_id := "@unbuilt"
var contact_age := 10.0
var _occupancy: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _loot: Array[Dictionary] = []
var _effects: Array[Dictionary] = []
var _flash_material: StandardMaterial3D
var enabled := true
var _dead_notified := false
var _audio_cache: Dictionary = {}
var _audio_pool: Array[AudioStreamPlayer3D] = []
var customization: Dictionary = {}
var flashlight_enabled := false
var flashlight: SpotLight3D
var laser: MeshInstance3D
var emergency: Node3D
var _benchmark_costs := "--benchmark" in OS.get_cmdline_user_args()
var _muzzle_flash: MeshInstance3D
var _muzzle_light: OmniLight3D
var _muzzle_material: StandardMaterial3D
var _muzzle_timer := 0.0
var _flame_audio: AudioStreamPlayer3D
var _flame_clock := 0.0
var _reload_audio: AudioStreamPlayer3D
var _recent_impacts: Array[Dictionary] = []
## Identifica cada ataque/explosão: vários chumbos da mesma escopeta na mesma vítima são UMA denúncia.
var _attack_serial := 0
## Só dentro do laço de chumbos de `fire_at`: fora dele, golpes repetidos (chamadas diretas de `_damage`) contam.
var _in_pellet_volley := false
var _crime_attack: Dictionary = {}
var _crime_window: Dictionary = {}
var _flame_hit_at: Dictionary = {}
## Relógio de combate: soma o `delta` de física, então PAUSAR o jogo não consome janelas nem cooldowns
## (o relógio real, `Time.get_ticks_msec`, continuava correndo na pausa).
var _combat_clock := 0.0
var effects: Node3D
var _swing_age := -1.0
var _swing_side := 1.0
var _swing_stance := ""
var _swing_yaw := 0.0
var _cheat_buffer := ""
## Estado de mira (leitura externa): `aiming` = V1 `is_aiming`; `aim_active` = V1 `weapon_aim_active`.
var aiming := false
var aim_active := false
var _scope_active := false
var _aim_hold := 0.0
var _clip_name := ""
var _clip_start := 0.0
var _clip_end := 0.0
var _clip_age := 0.0
var _clip_weapon := ""
var _recoil := 0.0
var _cheat_last := -100.0
var _tracer_materials: Dictionary = {}
var _pain_pool: Array[AudioStreamPlayer3D] = []
var _pain_next: Dictionary = {}
var _prune_clock := 0.0
## vítima -> instante (relógio de combate) do último contato de veículo do jogador
var _vehicle_contact: Dictionary = {}
## Mortes policiais já atribuídas ao jogador. Separar este registro do
## debounce de pelotas, fogo e contato permite registrar uma morte que ocorre
## dentro da mesma janela da agressão, sem duplicá-la.
var _police_kill_reported: Dictionary = {}
var _flame_crime_clock := 0.0
var _rig_pose := RIG_POSE.new()
var _pose_frame: Dictionary = {}

func configure(p_world: Node3D, p_player: CharacterBody3D, p_camera: Camera3D, p_state: RefCounted) -> void:
	world = p_world
	player = p_player
	camera = p_camera
	state = p_state
	_rng.randomize()

func _exit_tree() -> void:
	# Stop active playbacks before releasing their cached streams. AudioServer
	# may otherwise still own the mixer playback during scene teardown.
	for channel in _audio_pool:
		if not is_instance_valid(channel): continue
		channel.stop()
		channel.stream = null
	_audio_pool.clear()
	_audio_cache.clear()
	# Descarga: solta a camada de combate do ator, apaga luzes e limpa os emissores.
	if is_instance_valid(player) and "combat_clip" in player: _present(NAN, "", 0.0)
	if is_instance_valid(player) and player.has_method("clear_combat_weapon_pose"): player.clear_combat_weapon_pose()
	for light in [_muzzle_light, flashlight]:
		if is_instance_valid(light): light.hide()
	if is_instance_valid(effects): effects.shutdown()
	for voice in [_flame_audio, _reload_audio] + _pain_pool:
		if not is_instance_valid(voice): continue
		voice.stop()
		voice.stream = null

func _ready() -> void:
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.albedo_color = Color("ffcc68")
	_flash_material.emission_enabled = true
	_flash_material.emission = Color("ff8734")
	_build_socket()
	emergency = EMERGENCY.new()
	emergency.configure(world, self)
	add_child(emergency)
	flashlight = SpotLight3D.new()
	flashlight.spot_range = 16.0
	flashlight.spot_angle = 26.0
	flashlight.light_energy = 2.5
	flashlight.shadow_enabled = false
	gun.add_child(flashlight)
	flashlight.hide()
	laser = MeshInstance3D.new()
	var laser_mesh := BoxMesh.new()
	laser_mesh.size = Vector3(0.006, 0.006, 1)
	laser.mesh = laser_mesh
	var laser_material := StandardMaterial3D.new()
	laser_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser_material.albedo_color = Color("e5493c")
	laser.material_override = laser_material
	laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(laser)
	laser.hide()
	# V1 roteava todo som de combate para o bus "SFX" (ver `.bus = "SFX"` em
	# `police/PoliceVehicleCombat.gd` etc.); sem isso o slider de SFX do menu de
	# configurações não tinha efeito nenhum sobre tiro/recarga/impacto.
	var sfx_bus := AUDIO.SFX_BUS_NAME
	for index in 8:
		var channel := AudioStreamPlayer3D.new()
		channel.max_distance = 55
		channel.unit_size = 5
		channel.bus = sfx_bus
		add_child(channel)
		_audio_pool.append(channel)
	# Clarão de boca do V1: esfera emissiva + uma OmniLight, sem sombra, reaproveitadas.
	_muzzle_material = StandardMaterial3D.new()
	_muzzle_material.albedo_color = Color(1.0, 0.85, 0.2)
	_muzzle_material.emission_enabled = true
	_muzzle_material.emission = Color(1.0, 0.6, 0.1)
	_muzzle_material.emission_energy_multiplier = 4.5
	_muzzle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Vozes dedicadas (param quando a recarga é cancelada / o gatilho do lança-chamas solta).
	effects = EFFECTS.new()
	effects.name = "CombatEffects"
	add_child(effects)
	for index in PAIN_VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.max_distance = 45
		voice.unit_size = 4
		voice.bus = sfx_bus
		add_child(voice)
		_pain_pool.append(voice)
	_flame_audio = AudioStreamPlayer3D.new()
	_flame_audio.max_distance = 55
	_flame_audio.unit_size = 5
	_flame_audio.volume_db = -15.0
	_flame_audio.bus = sfx_bus
	add_child(_flame_audio)
	_reload_audio = AudioStreamPlayer3D.new()
	_reload_audio.max_distance = 45
	_reload_audio.unit_size = 4
	_reload_audio.volume_db = -5.0
	_reload_audio.bus = sfx_bus
	add_child(_reload_audio)

func _build_socket() -> void:
	if not is_instance_valid(player): return
	var skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton:
		for bone in ["RightHand", "mixamorig_RightHand", "hand_r", "mixamorig:RightHand"]:
			if skeleton.find_bone(bone) < 0: continue
			var attachment := BoneAttachment3D.new()
			attachment.bone_name = bone
			skeleton.add_child(attachment)
			socket = attachment
			break
	if socket == null:
		socket = Node3D.new()
		player.add_child(socket)
		socket.position = Vector3(0.22, 1.0, -0.2)
	gun = Node3D.new()
	socket.add_child(gun)
	# A arma recebe uma transformação mundial resolvida pelas duas mãos. Como
	# top-level, o BoneAttachment não reaplica o osso um quadro depois e não
	# separa o cabo da palma durante movimento/recuo.
	gun.top_level = true

func equipped() -> String:
	return String(state.equipped_weapon) if state != null else ""

func attack_allowed() -> bool:
	return enabled and state != null and state.can_attack() and health > 0 and not get_tree().paused

func _physics_process(delta: float) -> void:
	if state == null or not enabled: return
	_combat_clock += delta
	_advance_police_rounds(delta)
	cooldown = maxf(0, cooldown - delta)
	if reload_timer > 0:
		reload_timer = maxf(0, reload_timer - delta)
		if not attack_allowed() or equipped() != reloading_id:
			reload_timer = 0
			reloading_id = ""
			_reload_audio.stop()
		elif reload_timer == 0:
			state.reload_weapon(reloading_id, int(weapon_data(reloading_id).magazine_size))
			reloading_id = ""
			changed.emit()
	_update_aim(delta)
	_update_weapon_pose(delta)
	_update_visual()
	_update_combat_clip(delta)
	_update_swing(delta)
	_update_recoil(delta)
	_update_muzzle_and_flame(delta)
	_update_police(delta)
	_update_effects(delta)
	_update_loot(delta)

func _update_visual() -> void:
	if gun == null: return
	var id := equipped()
	if id != visual_id:
		for child in gun.get_children():
			if child == flashlight: continue
			gun.remove_child(child)
			child.queue_free()
		visual_id = id
		_muzzle_flash = null
		_muzzle_light = null
		_muzzle_timer = 0.0
		if id != "" and id != "fists" and CATALOG.WEAPONS.has(id):
			var muzzle := ARSENAL.build(gun, id)
			CUSTOM.fit(gun, id, customization, muzzle)
			_build_muzzle_flash(id, muzzle)
		if player.has_method("set_combat_weapon_mount"):
			player.set_combat_weapon_mount(gun, POSE.GRIPS.get(id, Vector3.ZERO))
	gun.visible = attack_allowed() and id != "" and id != "fists" and bool(_pose_frame.get("visible", true))
	# A arma e as palmas usam o mesmo alvo em espaço do Actor. Isso preserva a
	# orientação do cabo dentro da mão; não há mais um prop plano girado só em Y.
	if gun.visible and not _pose_frame.is_empty() and is_instance_valid(player.visual):
		if player.has_method("combat_weapon_transform"):
			gun.global_transform = player.combat_weapon_transform(POSE.GRIPS.get(id, Vector3.ZERO))
		else:
			var local_basis: Basis = _pose_frame.basis
			gun.global_transform = Transform3D((player.visual.global_basis * local_basis).orthonormalized(), player.visual.to_global(_pose_frame.gun_origin))
		_update_weapon_parts(id)
	flashlight.visible = gun.visible and flashlight_enabled and CUSTOM.installed(customization, id)
	var laser_part := CUSTOM.selected(customization, id, "laser")
	laser.visible = gun.visible and laser_part != "none"
	if laser.visible:
		var origin := player.global_position + Vector3.UP * 1.05
		var direction := _aim_direction()
		if direction.length_squared() < 0.001: direction = Vector3.FORWARD
		var ray := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * 35, 7, [player.get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		var end: Vector3 = hit.get("position", ray.to)
		laser.global_position = (origin + end) * 0.5
		laser.look_at(end)
		laser.scale.z = maxf(0.01, origin.distance_to(end))
		laser.material_override.albedo_color = Color("58e07c") if laser_part == "laser_green" else Color("e5493c")

func _update_weapon_pose(delta: float) -> void:
	if not is_instance_valid(player): return
	var id := equipped()
	var speed_now := Vector2(player.velocity.x, player.velocity.z).length()
	var moving := speed_now > 0.12
	var sprinting := speed_now > 4.2
	var progress := 0.0
	if reload_timer > 0.0 and _reload_total > 0.0: progress = clampf(1.0 - reload_timer / _reload_total, 0.0, 1.0)
	_pose_frame = _rig_pose.update(id, delta, aiming, reload_timer > 0.0, progress, moving, sprinting, float(player.phase))
	if player.has_method("set_combat_weapon_pose"):
		player.set_combat_weapon_pose(id, _pose_frame)

func _update_weapon_parts(id: String) -> void:
	var pump := gun.get_node_or_null("Pump") as Node3D
	if pump != null: pump.position.z = -0.16 + float(_pose_frame.get("pump", 0.0))
	var slide := gun.get_node_or_null("Slide") as Node3D
	if slide != null:
		if not slide.has_meta("combat_rest_position"): slide.set_meta("combat_rest_position", slide.position)
		slide.position = (slide.get_meta("combat_rest_position") as Vector3) + Vector3(0, 0, 0.045 * float(_pose_frame.get("slide", 0.0)))
	var cylinder := gun.get_node_or_null("ReloadCylinder") as Node3D
	if cylinder != null:
		var progress := clampf(1.0 - reload_timer / maxf(_reload_total, 0.001), 0.0, 1.0) if reload_timer > 0.0 else 1.0
		var opening := smoothstep(0.05, 0.18, progress) * (1.0 - smoothstep(0.79, 0.92, progress)) if reload_timer > 0.0 else 0.0
		cylinder.position.x = -0.065 * opening
		cylinder.rotation.z = -0.45 * opening
	var rocket := gun.get_node_or_null("LoadedRocket") as Node3D
	if rocket != null:
		var ammo: Dictionary = state.get_ammo(id)
		rocket.visible = int(ammo.get("magazine", 0)) > 0 or (reload_timer > 0.0 and (1.0 - reload_timer / maxf(_reload_total, 0.001)) > 0.65)

## Clarão de boca do V1 (`Player._update_equipped_weapon_3d_mesh`): só armas de fogo,
## lança-foguetes e lança-chamas. Corpo a corpo e granada não têm boca.
func _build_muzzle_flash(id: String, muzzle: Vector3) -> void:
	var data: Dictionary = CATALOG.WEAPONS.get(id, {})
	if data.get("is_melee", false) or data.get("is_grenade", false): return
	var tip := muzzle
	if CUSTOM.selected(customization, id, "muzzle") == "suppressor": tip.z -= 0.145
	_muzzle_flash = MeshInstance3D.new()
	_muzzle_flash.mesh = _directional_flash_mesh()
	_muzzle_flash.material_override = _muzzle_material
	_muzzle_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle_flash.position = tip
	_muzzle_flash.visible = false
	gun.add_child(_muzzle_flash)
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1.0, 0.7, 0.2)
	_muzzle_light.light_energy = 2.8
	_muzzle_light.omni_range = 2.5
	_muzzle_light.shadow_enabled = false
	_muzzle_light.position = tip
	_muzzle_light.visible = false
	gun.add_child(_muzzle_light)

func _directional_flash_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ray in 6:
		var angle := TAU * float(ray) / 6.0
		var tangent := Vector3(cos(angle), sin(angle), 0.0)
		var side := Vector3(-sin(angle), cos(angle), 0.0)
		var root := tangent * 0.018
		var width := 0.032 if ray % 2 == 0 else 0.022
		var length := 0.26 if ray % 2 == 0 else 0.17
		var tip := tangent * (0.035 if ray % 2 == 0 else 0.022) + Vector3(0, 0, -length)
		for vertex in [root - side * width, tip, root + side * width]: surface.add_vertex(vertex)
		for vertex in [Vector3.ZERO, root + side * width, tip]: surface.add_vertex(vertex)
	return surface.commit()

func _muzzle_world_position() -> Vector3:
	if is_instance_valid(_muzzle_flash): return _muzzle_flash.global_position
	if is_instance_valid(gun): return gun.global_position - gun.global_basis.z * 0.2
	return player.global_position + Vector3.UP * 1.05

## `Player._trigger_muzzle_flash_3d`: escala e duração por arma; silenciador reduz o clarão e apaga a luz.
func _flash_muzzle(id: String) -> void:
	if not is_instance_valid(_muzzle_flash) or not is_instance_valid(_muzzle_light): return
	var heavy := id in HEAVY_FLASH
	var suppressed := CUSTOM.selected(customization, id, "muzzle") == "suppressor"
	var scale_value := Vector3.ONE * (1.35 if heavy else 0.8)
	if suppressed: scale_value *= 0.22
	if id == "flamethrower": scale_value = Vector3(0.30, 0.30, 1.65)
	elif id == "rpg": scale_value = Vector3(0.70, 0.70, 2.2)
	_muzzle_flash.scale = scale_value
	_muzzle_flash.visible = true
	_muzzle_light.visible = not suppressed
	_muzzle_timer = 0.075 if id == "flamethrower" else (0.09 if id == "rpg" else (0.065 if heavy else 0.035))

## Apaga o clarão e para o rugido do lança-chamas quando o gatilho solta ou o ataque é bloqueado.
func _update_muzzle_and_flame(delta: float) -> void:
	if _muzzle_timer > 0.0:
		_muzzle_timer -= delta
		if _muzzle_timer <= 0.0:
			if is_instance_valid(_muzzle_flash): _muzzle_flash.hide()
			if is_instance_valid(_muzzle_light): _muzzle_light.hide()
	if _flame_clock > 0.0: _flame_clock -= delta
	if _flame_crime_clock > 0.0: _flame_crime_clock -= delta
	_prune_clock += delta
	if _prune_clock >= REGISTER_PRUNE_INTERVAL:
		_prune_clock = 0.0
		_prune_combat_registers()
	if is_instance_valid(_reload_audio) and _reload_audio.playing and reload_timer <= 0.0: _reload_audio.stop()
	if is_instance_valid(_flame_audio) and _flame_audio.playing and is_instance_valid(player): _flame_audio.global_position = player.global_position
	if is_instance_valid(_flame_audio) and _flame_audio.playing and (_flame_clock <= 0.0 or not attack_allowed() or equipped() != "flamethrower" or reload_timer > 0.0):
		_flame_audio.stop()

## Efeito visual do contato: sangue nos corpos (e mancha se morreram), faísca/poeira nos demais.
## Alvo protegido não sangra. `hit` tem o formato do resultado do raio (collider, position, normal).
func _hit_effect(hit: Dictionary, amount: float, direction: Vector3) -> void:
	if not is_instance_valid(effects): return
	var collider: Object = hit.collider
	if not is_instance_valid(collider): return
	var material := _impact_material(collider)
	if material == "flesh":
		if _is_invulnerable(collider): return
		effects.blood(hit.position, direction, amount)
		_pain_voice(collider as Node3D, amount)
		var victim := collider as Node3D
		if victim != null and victim.get("dead") == true: effects.stain(victim.global_position, 0.6)
	else:
		effects.impact(hit.position, hit.normal, material, amount)

## Balanço da arma e torção do corpo durante o golpe. Parcial: não há pose de braço (o V1 usa IK sobre o
## rig Meshy, `PlayerCombatPose`/`MeshyMeleePose`); aqui só a arma na mão balança e o corpo gira.
func _start_swing(data: Dictionary, direction: Vector3) -> void:
	_swing_age = 0.0
	_swing_stance = String(data.get("stance", ""))
	_swing_side = -_swing_side
	_swing_yaw = atan2(-direction.x, -direction.z)

## Escreve na camada de combate do `Actor` só quando a propriedade existe (atores de teste não a têm).
func _present(facing: float, clip: String, clip_time: float, stance: String = "") -> void:
	if not is_instance_valid(player) or not "combat_clip" in player: return
	player.combat_facing = facing
	player.combat_clip = clip
	player.combat_clip_time = clip_time
	if "combat_stance" in player: player.combat_stance = stance

## Direção de mira no plano. Mouse: do jogador ao `aim_point` (que `FullSession` atualiza a cada quadro via
## `aim_from_screen`). Controle/toque: a MESMA conta de `GameInput.aim_target_3d`, só que lendo `aim_direction`
## (sem chamar a função, que integra a rotação do direcionador e não pode rodar duas vezes por quadro).
## Assim o rumo do corpo e o rumo do disparo (`fire_at(target)`) saem da mesma direção.
func _aim_direction() -> Vector3:
	var controls: Node = get_node_or_null("/root/GameInput")
	if controls != null and is_instance_valid(camera) and (controls.using_gamepad or not controls.touch_aim.is_zero_approx()):
		var stick: Vector2 = controls.touch_aim if not controls.touch_aim.is_zero_approx() else controls.aim_direction
		var right := camera.global_basis.x
		var down := camera.global_basis.z
		right.y = 0.0
		down.y = 0.0
		var pad := right.normalized() * stick.x + down.normalized() * stick.y
		if pad.length_squared() > 0.0001: return pad.normalized()
	var flat := aim_point - player.global_position
	flat.y = 0.0
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.ZERO

## Estado de mira e rumo do corpo. Só em jogo livre com ataque permitido (pausa, menu, garagem, veículo, ski,
## morte, transição e bloqueio de entrada zeram tudo e devolvem a locomoção).
func _update_aim(delta: float) -> void:
	if not is_instance_valid(player): return
	if _aim_hold > 0.0: _aim_hold -= delta
	# Tipos explícitos: `player.input_locked` é acesso dinâmico (Variant); não se apoia a inferência do `:=` numa cadeia `and`.
	var permitted: bool = attack_allowed() and not bool(player.input_locked) and _free_play_ok()
	var aim_pressed: bool = permitted and InputMap.has_action("aim") and Input.is_action_pressed("aim")
	var fire_pressed: bool = permitted and InputMap.has_action("fire") and Input.is_action_pressed("fire")
	var lantern: bool = permitted and is_instance_valid(flashlight) and flashlight.visible
	aim_active = aim_pressed and equipped() not in NON_AIM_WEAPONS
	aiming = permitted and (aim_pressed or fire_pressed or lantern or _aim_hold > 0.0)
	_scope_active = aim_pressed and CUSTOM.selected(customization, equipped(), "scope") != "none" and not bool(player.get_meta("isolated_interior", false))
	var direction: Vector3 = _aim_direction() if aiming else Vector3.ZERO
	var facing: float = atan2(-direction.x, -direction.z) if direction != Vector3.ZERO else NAN
	var stance := ""
	if aiming:
		var weapon: Dictionary = CATALOG.WEAPONS.get(equipped(), {})
		if weapon.get("is_grenade", false): stance = "grenade"
		elif not weapon.is_empty() and not weapon.get("is_melee", false): stance = "gun"
	_present(facing, player.combat_clip if "combat_clip" in player else "", player.combat_clip_time if "combat_clip_time" in player else 0.0, stance)
	if not permitted:
		_aim_hold = 0.0
		_cancel_combat_clip()

## Contrato de luneta (V1 `Player.weapon_scope_active`). VERDADEIRO enquanto TODAS valem, no quadro de física atual:
##   1. luneta instalada na arma equipada (`scope_part() != "none"`);
##   2. ação `aim` APERTADA agora (sem retenção: solta o botão, volta falso no próximo passo de física);
##   3. ataque permitido e jogo livre: sem pausa, menu, remapeamento, abertura, minigame do cofre, garagem, veículo,
##      ski, morte, entrada travada ou transição;
##   4. jogador fora de interior isolado (meta `isolated_interior`).
## Atualiza a cada `_physics_process` (60 Hz) e é relido com `attack_allowed()` na chamada. Quem lê em `_process` vê o
## valor do último passo de física (até ~1/60 s de defasagem). Trocar de arma, morrer ou entrar em veículo o zera no mesmo
## passo. Não há zoom, retícula nem suavização aqui: a câmera e a interface (outra equipe) aplicam e suavizam.
func scope_active() -> bool:
	return _scope_active and attack_allowed()

## Peça de luneta instalada na arma equipada ("none" se não há); a câmera usa o nome para escolher o zoom.
func scope_part() -> String:
	return CUSTOM.selected(customization, equipped(), "scope")

func _start_combat_clip(id: String, data: Dictionary) -> bool:
	var spec: Array = MELEE_CLIPS.get(String(data.get("stance", "")), [])
	if spec.is_empty() or not is_instance_valid(player) or not "animation" in player: return false
	var animation: AnimationPlayer = player.animation
	if animation == null or not animation.has_animation(spec[0]): return false
	_clip_name = spec[0]
	_clip_start = float(spec[1])
	_clip_end = float(spec[2])
	_clip_age = 0.0
	_clip_weapon = id
	return true

func _cancel_combat_clip() -> void:
	_clip_name = ""
	if is_instance_valid(player) and "combat_clip" in player: player.combat_clip = ""

## Avança o clipe no tempo de física do combate. Não aplica dano: o dano já foi aplicado em `fire_at`.
## Interrompe (e a locomoção retoma no quadro seguinte) ao trocar de arma, morrer, bloquear ataque
## (garagem, veículo, ski, transição) ou terminar o trecho. Na pausa este método não roda, então o clipe congela junto.
func _update_combat_clip(delta: float) -> void:
	if _clip_name == "": return
	if not attack_allowed() or equipped() != _clip_weapon:
		_cancel_combat_clip()
		return
	_clip_age += delta
	var time := _clip_start + _clip_age
	if time >= _clip_end:
		_cancel_combat_clip()
		return
	if "combat_clip" in player:
		player.combat_clip = _clip_name
		player.combat_clip_time = time

## Coice de arma de fogo com o `recoil` e a velocidade de retorno de `WeaponPoseData.PROFILES`.
func _update_recoil(delta: float) -> void:
	if _recoil <= 0.0005:
		if _recoil != 0.0:
			_recoil = 0.0
		return
	var rate := float(POSE.PROFILES.get(equipped(), [Vector3.ZERO, Vector3.ZERO, 0.0, 12.0])[3])
	_recoil *= exp(-rate * delta)

func _pain_voice(victim: Node3D, amount: float) -> void:
	if victim == null or not is_instance_valid(victim) or amount <= 0.0: return
	if victim.get("dead") == true or (victim.get("health") != null and float(victim.get("health")) <= 0.0): return
	var id := victim.get_instance_id()
	if float(_pain_next.get(id, -1.0)) > _combat_clock: return
	if _rng.randf() >= (PAIN_CHANCE_HEAVY if amount >= 25.0 else PAIN_CHANCE_LIGHT): return
	for voice in _pain_pool:
		if voice.playing: continue
		var stream := AUDIO.take("hurt", _rng)
		if stream == null: return
		_pain_next[id] = _combat_clock + PAIN_COOLDOWN
		voice.stream = stream
		voice.global_position = victim.global_position + Vector3.UP
		voice.volume_db = -6.0 if victim == player else -11.0
		voice.pitch_scale = 1.0 if victim == player else 0.97
		voice.play()
		return

func _update_swing(delta: float) -> void:
	if _swing_age < 0.0: return
	_swing_age += delta
	var progress := _swing_age / SWING_DURATION
	if progress >= 1.0 or not attack_allowed():
		_swing_age = -1.0
	# A janela acima só acompanha a ação lógica. A trajetória visual é específica
	# de cada arma em WeaponRigPose; não sobrepor um balanço genérico ao IK.

func weapon_data(id: String) -> Dictionary:
	return CUSTOM.effective_data(id, customization)

func buy_attachment(id: String, part: String) -> bool:
	if not state.owns_weapon(id) or not CUSTOM.supports(id, part): return false
	if CUSTOM.owns(customization, id, part): return install_attachment(id, part)
	if not state.spend(int(CUSTOM.PARTS[part].price), "weapon_part:" + id + ":" + part): return false
	var entry: Dictionary = customization.get(id, {"owned":false, "installed":false, "owned_parts":[], "parts":{}})
	if part == "flashlight":
		entry.owned = true
		entry.installed = true
	else:
		entry.owned_parts.append(part)
		entry.parts[CUSTOM.PARTS[part].slot] = part
	customization[id] = entry
	visual_id = "@rebuild"
	changed.emit()
	return true

func install_attachment(id: String, part: String, installed: bool = true) -> bool:
	if not CUSTOM.supports(id, part) or not CUSTOM.owns(customization, id, part): return false
	if part == "flashlight": customization[id].installed = installed
	elif installed: customization[id].parts[CUSTOM.PARTS[part].slot] = part
	else: customization[id].parts.erase(CUSTOM.PARTS[part].slot)
	visual_id = "@rebuild"
	changed.emit()
	return true

func toggle_flashlight() -> bool:
	if not attack_allowed() or not CUSTOM.installed(customization, equipped()): return false
	flashlight_enabled = not flashlight_enabled
	return true

func aim_from_screen(screen: Vector2) -> Vector3:
	if not is_instance_valid(camera): return player.global_position + Vector3.FORWARD * 10
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var plane := Plane(Vector3.UP, player.global_position.y + 1.0)
	var hit: Variant = plane.intersects_ray(origin, direction)
	if hit is Vector3: aim_point = hit
	return aim_point

func fire_at(target: Vector3) -> bool:
	if not attack_allowed() or cooldown > 0 or reload_timer > 0: return false
	var id := equipped()
	if id.is_empty(): id = "fists"
	if not CATALOG.WEAPONS.has(id): return false
	if id != "fists" and not state.owns_weapon(id): return false
	var data: Dictionary = weapon_data(id)
	var melee: bool = data.get("is_melee", false)
	if not melee and not state.consume_ammo(id, 1):
		# V1 (`Player._shoot_towards`): pente vazio recarrega sozinho quando há reserva.
		cooldown = 0.25
		if not reload_weapon(): message.emit("Sem munição.")
		return false
	cooldown = float(data.fire_interval)
	_attack_serial += 1
	_aim_hold = AIM_HOLD
	_rig_pose.attack(id, float(data.get("recoil_multiplier", 1.0)))
	if not melee: _recoil = float(POSE.PROFILES.get(id, [Vector3.ZERO, Vector3.ZERO, 0.0, 12.0])[2])
	if not melee: weapon_fired.emit(id, player.global_position)
	if melee: _melee_swing_sound(id, data)
	elif data.get("is_flame", false): _flame_sound()
	elif data.get("is_grenade", false): _play_stream(AUDIO.grenade_throw(), player.global_position, 0.0)
	else: _shot_sound(id, data)
	if not melee and not data.get("is_grenade", false): _flash_muzzle(id)
	aim_point = target
	var origin := _muzzle_world_position()
	var direction := target - origin
	direction.y = 0
	if direction.length_squared() < 0.001: direction = Vector3.FORWARD
	direction = direction.normalized()
	var defense_ray := PhysicsRayQueryParameters3D.create(origin, origin + direction * float(data.get("max_range", 420.0)) / 16.0, 7, [player.get_rid()])
	var defense_hit := get_world_3d().direct_space_state.intersect_ray(defense_ray)
	var self_defense: bool = not defense_hit.is_empty() and defense_hit.collider.get_meta("gameplay_role", "") == "cobra"
	if is_instance_valid(player.visual): player.visual.rotation.y = atan2(-direction.x, -direction.z)
	if data.get("is_grenade", false) or data.get("is_explosive", false):
		var shot := PROJECTILE.new()
		shot.controller = self
		shot.shooter = player
		shot.grenade = data.get("is_grenade", false)
		shot.damage = data.damage
		shot.radius = float(data.blast_radius) / 16.0
		# V1: a granada dura 2,0 s e o alcance vem da distância até o alvo (60 px até
		# `throw_range`); o foguete não fere quem o disparou (`Bullet._trigger_explosion`).
		shot.fuse = GRENADE_FUSE if shot.grenade else float(data.max_range) / float(data.projectile_speed)
		shot.hurt_shooter = shot.grenade
		if shot.grenade:
			var flat_target := target - origin
			flat_target.y = 0
			var throw_distance := clampf(flat_target.length(), GRENADE_MIN_THROW, float(data.get("throw_range", 320.0)) / 16.0)
			shot.velocity = direction * (throw_distance * GRENADE_LANDING_SHARE / GRENADE_AIR_TIME)
			shot.velocity.y = 5.5
		else:
			shot.velocity = direction * float(data.projectile_speed) / 16.0
		add_child(shot)
		shot.global_position = origin
		if not shot.grenade: effects.backblast(origin, direction)
	elif melee:
		# Clipe do rig quando existe; senão, o balanço procedural da arma.
		if not _start_combat_clip(id, data): _start_swing(data, direction)
		_melee(origin, direction, data)
	else:
		_in_pellet_volley = true
		if not data.get("is_flame", false): effects.shell(origin - direction * 0.12, direction, player.global_position.y)
		for pellet in int(data.get("pellets", 1)):
			var spread := float(data.get("spread", 0))
			var ray_direction := direction.rotated(Vector3.UP, _rng.randf_range(-spread, spread))
			var distance := float(data.get("max_range", 420.0)) / 16.0
			var query := PhysicsRayQueryParameters3D.create(origin, origin + ray_direction * distance, 7, [player.get_rid()])
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			var end: Vector3 = hit.get("position", query.to)
			if not hit.is_empty():
				var amount := CATALOG.distance_damage(int(data.damage), origin.distance_to(end) * 16.0, float(data.get("falloff_start", 0)), float(data.get("max_range", 420)), float(data.get("min_damage_ratio", 1)))
				if data.get("is_flame", false):
					if _flame_hit_due(hit.collider): _damage(hit.collider, amount, player, true)
				else:
					_damage(hit.collider, amount, player)
					_impact_sound(hit.collider, end, float(amount))
					_hit_effect(hit, float(amount), ray_direction)
			if data.get("is_flame", false):
				effects.flame(origin, ray_direction, origin.distance_to(end))
				emergency.ignite(end, player, 0.3)
			else:
				effects.tracer(origin, end, float(data.get("projectile_speed", 920.0)) / 16.0, data.get("tracer_color", Color("ffe36b")), float(data.get("damage", 16.0)))
		_in_pellet_volley = false
	if not melee and not self_defense:
		if data.get("is_flame", false):
			# Jato contínuo: a denúncia do disparo acompanha o tempo, não os 20 disparos por segundo.
			if _flame_crime_clock <= 0.0:
				_flame_crime_clock = FLAME_SHOT_CRIME_INTERVAL
				register_crime(4, player.global_position)
		else:
			register_crime(1 if data.get("suppressed", false) else 4, player.global_position)
	changed.emit()
	return true

func _melee(origin: Vector3, direction: Vector3, data: Dictionary) -> void:
	var reach := float(data.get("melee_range", 46.0)) / 16.0
	# Caixa à frente do jogador, do corpo até o alcance (V1: qualquer alvo a menos de `melee_range` no cone da frente).
	# A esfera antiga ficava centrada em `reach - 0,5` e deixava uma zona morta: alvo colado (< ~1,8 m com punhos) não era
	# atingido, e só valia de longe. Aqui vale do contato até o alcance, e acerta o mais próximo primeiro.
	var box := BoxShape3D.new()
	box.size = Vector3(1.3, 1.6, reach)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.z)), origin + direction * (reach * 0.5))
	query.collision_mask = 2
	query.exclude = [player.get_rid()]
	var candidates: Array[Node3D] = []
	for result in get_world_3d().direct_space_state.intersect_shape(query, 8):
		if result.collider is Node3D: candidates.append(result.collider)
	candidates.sort_custom(func(a: Node3D, b: Node3D): return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	for actor in candidates:
		var target := actor.global_position + Vector3.UP
		var ray := PhysicsRayQueryParameters3D.create(origin, target, 7, [player.get_rid()])
		var obstruction := get_world_3d().direct_space_state.intersect_ray(ray)
		if not obstruction.is_empty() and obstruction.collider != actor: continue
		_damage(actor, float(data.damage), player)
		if String(data.get("stance", "")) == "knife" and _impact_material(actor) == "flesh":
			_play_stream(AUDIO.knife_sample(_rng.randi_range(0, 2)), actor.global_position, -13.0)
		else:
			_impact_sound(actor, target, float(data.damage))
		_hit_effect({"collider": actor, "position": target, "normal": -direction}, float(data.damage), direction)
		break

## Maciota e o mecânico (e qualquer nó marcado): nada os fere, nem contam como lesão ou crime.
func _is_invulnerable(actor: Object) -> bool:
	return PROTECTION.is_protected(actor)

## Um golpe do V1 do lança-chamas por alvo a cada 120 ms (o jato V2 é um raio a 20 Hz).
func _flame_hit_due(target: Object) -> bool:
	if not is_instance_valid(target): return false
	var id := target.get_instance_id()
	if _combat_clock - float(_flame_hit_at.get(id, -FLAME_HIT_COOLDOWN)) < FLAME_HIT_COOLDOWN: return false
	_flame_hit_at[id] = _combat_clock
	return true

## Crime por ferir alguém, sem contar a mesma agressão duas vezes: chumbos do mesmo tiro (ou golpes da
## mesma explosão) são uma denúncia por vítima; fonte contínua (`continuous`) só denuncia de novo depois
## de CONTINUOUS_CRIME_COOLDOWN. Um golpe discreto novo (bala, faca) sempre denuncia.
func _crime_due(victim: Object, continuous: bool) -> bool:
	var id := victim.get_instance_id()
	if continuous:
		if float(_crime_window.get(id, -1.0)) > _combat_clock: return false
		_crime_window[id] = _combat_clock + CONTINUOUS_CRIME_COOLDOWN
	elif _in_pellet_volley and int(_crime_attack.get(id, -1)) == _attack_serial: return false
	_crime_attack[id] = _attack_serial
	return true

## Atropelamento com o veículo do jogador (chamado por `Actor.receive_damage` depois de o `Vehicle`
## bater na vítima). A atribuição continua em `Vehicle.is_player_damage_source()`: tráfego, viaturas de
## despacho (`external_input`) e carros sem o jogador ao volante NUNCA denunciam o jogador.
## Regra: um crime por vítima por contato. Cada chamada renova o contato; só depois de
## VEHICLE_CONTACT_GAP sem contato um novo atropelamento denuncia de novo. O valor (25) é o do V2;
## o V1 denunciava 6 (vítima sobrevive) ou 20 (fatal), uma única vez.
func report_vehicle_assault(victim: Node3D, vehicle: Node) -> void:
	if not is_instance_valid(victim) or not is_instance_valid(vehicle): return
	if not vehicle.has_method("is_player_damage_source") or not vehicle.is_player_damage_source(): return
	var id := victim.get_instance_id()
	var last := float(_vehicle_contact.get(id, -INF))
	_vehicle_contact[id] = _combat_clock
	var new_contact := _combat_clock - last > VEHICLE_CONTACT_GAP
	if victim.get_meta("gameplay_role", "") == "police":
		if new_contact: _report_police_assault(victim)
		if victim.get("dead") == true: _report_police_killed(victim)
		return
	if new_contact: register_crime(25, victim.global_position)

## Registros por vítima são inteiros (ids de instância), não referências: mesmo assim expiram por tempo,
## saem quando o ator deixa de existir e são zerados na troca de região.
func _prune_combat_registers() -> void:
	for id in _crime_window.keys():
		if float(_crime_window[id]) <= _combat_clock or not is_instance_id_valid(int(id)): _crime_window.erase(id)
	for id in _flame_hit_at.keys():
		if _combat_clock - float(_flame_hit_at[id]) > 1.0 or not is_instance_id_valid(int(id)): _flame_hit_at.erase(id)
	for id in _vehicle_contact.keys():
		if _combat_clock - float(_vehicle_contact[id]) > VEHICLE_CONTACT_GAP or not is_instance_id_valid(int(id)): _vehicle_contact.erase(id)
	for id in _police_kill_reported.keys():
		if not is_instance_id_valid(int(id)): _police_kill_reported.erase(id)
	for id in _pain_next.keys():
		if float(_pain_next[id]) <= _combat_clock or not is_instance_id_valid(int(id)): _pain_next.erase(id)
	for id in _crime_attack.keys():
		if not is_instance_id_valid(int(id)): _crime_attack.erase(id)
	if _crime_attack.size() > 128: _crime_attack.clear()
	_recent_impacts = _recent_impacts.filter(func(entry): return _combat_clock - float(entry.time) < IMPACT_GROUP_SECONDS)

func _clear_combat_registers() -> void:
	_crime_window.clear()
	_crime_attack.clear()
	_flame_hit_at.clear()
	_vehicle_contact.clear()
	_police_kill_reported.clear()
	_recent_impacts.clear()
	_pain_next.clear()
	_flame_crime_clock = 0.0

## `continuous`: dano de jato ou de fogo em tique periódico (ver `_crime_due`).
func _damage(actor: Object, amount: float, source: Node, continuous: bool = false) -> void:
	if _is_invulnerable(actor): return
	if actor == player:
		damage_player(amount)
	elif is_instance_valid(actor) and actor.has_method("receive_damage"):
		var was_dead: bool = actor.get("dead") == true
		actor.receive_damage(amount, source)
		var role := String(actor.get_meta("gameplay_role", "")) if actor is Node else ""
		var killed: bool = not was_dead and actor.get("dead") == true
		if actor is Node3D and role in ["civilian", "emergency"]:
			emergency.report_injury(actor, actor.get("dead") == true)
		if source == player and role != "cobra" and not actor.get_meta("local_security",false):
			if role == "police":
				if _crime_due(actor, continuous): _report_police_assault(actor as Node3D)
				if killed: _report_police_killed(actor as Node3D)
			elif _crime_due(actor, continuous):
				register_crime(12, player.global_position)

## V1 `ensure_minimum_wanted_level(2)`: ferir um policial nunca pode deixar o
## jogador abaixo de 30 pontos. Uma procura maior não recebe pontos artificiais
## a cada pelota ou tique contínuo.
func _report_police_assault(victim: Node3D) -> void:
	if not is_instance_valid(victim): return
	var missing := maxi(0, STAR_THRESHOLDS[2] - crime_points)
	if missing > 0: register_crime(missing, victim.global_position)

## V1 `report_officer_killed`: depois da agressão soma pelo menos 30 pontos e
## chega ao piso de 60. O id impede duplicação entre origens de dano.
func _report_police_killed(victim: Node3D) -> void:
	if not is_instance_valid(victim): return
	var id := victim.get_instance_id()
	if _police_kill_reported.has(id): return
	_police_kill_reported[id] = true
	register_crime(maxi(30, STAR_THRESHOLDS[3] - crime_points), victim.global_position)

func reload_weapon() -> bool:
	if not attack_allowed() or reload_timer > 0: return false
	var id := equipped()
	if not CATALOG.WEAPONS.has(id): return false
	var data: Dictionary = weapon_data(id)
	if int(data.magazine_size) < 1: return false
	var ammo: Dictionary = state.get_ammo(id)
	if int(ammo.get("reserve", 0)) < 1 or int(ammo.get("magazine", 0)) >= int(data.magazine_size): return false
	# V1 (`WeaponReload.duration`): o take mais longo do banco de recarga da arma; sem banco, o tempo antigo.
	var bank_seconds: float = AUDIO.reload_seconds(id)
	reload_timer = bank_seconds if bank_seconds > 0.0 else (1.35 if id not in ["rpg", "shotgun", "hunting_rifle"] else 2.2)
	reload_timer *= float(data.get("reload_multiplier", 1.0))
	_reload_total = reload_timer
	reloading_id = id
	_play_reload_audio(id, float(data.get("reload_multiplier", 1.0)))
	message.emit("Recarregando…")
	return true

func cycle_weapon(step: int) -> bool:
	if not attack_allowed(): return false
	var order: Array = CATALOG.ORDER
	var index := order.find(equipped())
	for offset in range(1, order.size() + 1):
		var id: String = order[posmod(index + offset * step, order.size())]
		if id == "fists" or state.owns_weapon(id):
			if state.equip_weapon(id):
				reload_timer = 0
				_reload_audio.stop()
				changed.emit()
				return true
	return false

## Tecla 1–0 do V1 (`SLOT_ORDER`). Passa por `state.equip_weapon`, que já recusa arma não
## carregada (arsenal da Monaliza), esquiando e a garagem.
func equip_slot(id: String) -> bool:
	if not attack_allowed() or not state.owns_weapon(id): return false
	if not state.equip_weapon(id): return false
	reload_timer = 0
	_reload_audio.stop()
	changed.emit()
	return true

## Jogo livre: sessão pronta, sem menu/remapeamento/abertura/cofre em minigame.
func _free_play_ok() -> bool:
	var session: Variant = world.get("session") if is_instance_valid(world) else null
	if session != null:
		if not session.ready_for_play or session.modal or not session.rebinding_action.is_empty(): return false
		if session.arrival.controls_locked or session.arrival.phase == "opening": return false
		if is_instance_valid(session.robberies.lockpick) and session.robberies.lockpick.active: return false
	var controls: Node = get_node_or_null("/root/GameInput")
	return controls == null or not controls.remapping

## `weapon_previous` e `weapon_slot_1..10` estão mapeados em GameInput mas o FullSession só trata
## `weapon_next`/`unarmed`. Trata-se aqui, depois do `_input` do FullSession e só em jogo livre.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or not attack_allowed(): return
	# A roda do mouse também aproxima/afasta a câmera (CameraRig) e `weapon_next` já a usa; não se
	# amarra o recuo da roda à troca de arma sem decisão do integrador. Teclado e controle valem.
	var previous := event.is_action_pressed("weapon_previous") and not (event is InputEventMouseButton)
	var slot := -1
	for index in SLOT_ORDER.size():
		if event.is_action_pressed("weapon_slot_%d" % (index + 1)): slot = index
	if not previous and slot < 0: return
	if not _free_play_ok(): return
	if previous: cycle_weapon(-1)
	else: equip_slot(SLOT_ORDER[slot])
	get_viewport().set_input_as_handled()

## Cheat de arsenal do V1: `Player._handle_cheat_key`. Mesmas guardas (pausa, campo de texto, remapeamento,
## modificadores, ataque bloqueado). FullSession encaminha antes dos atalhos de interação.
## Prefixos reconhecidos são consumidos para que E não abra diálogos durante a sequência.
func handle_arsenal_input(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo: return false
	var focus := get_viewport().gui_get_focus_owner()
	if not attack_allowed() or not _free_play_ok() or focus is LineEdit or focus is TextEdit or key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		_cheat_buffer = ""
		return false
	if _combat_clock - _cheat_last > CHEAT_GAP: _cheat_buffer = ""
	_cheat_last = _combat_clock
	var code: int = key.unicode if key.unicode != 0 else key.keycode
	if code == 0: code = key.physical_keycode
	if not ((code >= 65 and code <= 90) or (code >= 97 and code <= 122)):
		_cheat_buffer = ""
		return false
	_cheat_buffer = (_cheat_buffer + String.chr(code).to_lower()).right(CHEAT_BUFFER)
	if _cheat_buffer.ends_with(CHEAT_ARSENAL):
		_cheat_buffer = ""
		return activate_arsenal_cheat()
	for length in range(1,CHEAT_ARSENAL.length()):
		if _cheat_buffer.ends_with(CHEAT_ARSENAL.left(length)): return true
	return false

## Concede o arsenal pelo Economy existente (`Economy.activate_arsenal_cheat`): posse e munição no
## inventário normal, direito de carregar tudo só na sessão. Bloqueado onde atacar é bloqueado (garagem).
func activate_arsenal_cheat() -> bool:
	if not attack_allowed() or state == null or not "economy" in state: return false
	reload_timer = 0.0
	reloading_id = ""
	_reload_audio.stop()
	state.economy.activate_arsenal_cheat()
	changed.emit()
	message.emit("Cheat ativado")
	return true

func explode(point: Vector3, radius: float, amount: float, source: Node3D, hurt_source: bool = true) -> void:
	# Explosives launched outside cannot cross the safe-zone boundary through a transition.
	if source == player and not state.weapons_allowed(): return
	_sound("explosion", point)
	if emergency != null: emergency.ignite(point, source, 1.0)
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform.origin = point
	query.collision_mask = 6
	var seen: Dictionary = {}
	for result in get_world_3d().direct_space_state.intersect_shape(query, 64):
		var actor: Node3D = result.collider
		if not hurt_source and (actor == source or actor.get_parent() == source): continue
		if seen.has(actor.get_instance_id()): continue
		seen[actor.get_instance_id()] = true
		var target := actor.global_position + Vector3.UP
		var ray := PhysicsRayQueryParameters3D.create(point, target, 1)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		var falloff := clampf(1.0 - point.distance_to(target) / radius, 0, 1)
		_damage(actor, amount * falloff, source)
		_hit_effect({"collider": actor, "position": target, "normal": Vector3.UP}, amount * falloff, (target - point).normalized())
	if is_instance_valid(effects): effects.explosion(point, radius)
	# Um único evento por detonação admitida. A origem e a autoria são as mesmas
	# usadas pelo dano; `null` continua desconhecido e nunca vira jogador por inferência.
	explosion_occurred.emit(point, radius, source)

func damage_player(amount: float) -> void:
	_apply_player_damage(amount, true)

func damage_environment(amount: float) -> void:
	# Cold and other environmental damage do not consume ballistic armor or crime.
	_apply_player_damage(amount, false)

func _apply_player_damage(amount: float, use_armor: bool) -> void:
	if not is_finite(amount) or amount <= 0 or health <= 0 or state == null or not state.weapons_allowed(): return
	var absorbed := minf(armor, amount * 0.65) if use_armor else 0.0
	armor -= absorbed
	health = maxf(0, health - (amount - absorbed))
	if health > 0.0: _pain_voice(player, amount)
	changed.emit()
	if health == 0 and not _dead_notified:
		_dead_notified = true
		player.input_locked = true
		player_died.emit()

func heal(amount: float) -> bool:
	if amount <= 0 or health <= 0 or health >= 100: return false
	health = minf(100, health + amount)
	changed.emit()
	return true

func respawn() -> void:
	health = 100
	armor = 0
	_dead_notified = false
	player.input_locked = false
	clear_wanted()
	changed.emit()

func register_crime(points: int, point: Vector3) -> void:
	if points <= 0 or not state.weapons_allowed(): return
	var old_stars := stars
	crime_points = mini(300, crime_points + points)
	_update_stars()
	last_known = point
	last_known_valid = true
	hidden_time = 0
	if old_stars == 0 and stars > 0:
		dispatch_timer = [0.0, 6.0, 3.0, 1.0, 1.0, 1.0, 1.0][stars]
	crime_reported.emit(points)
	changed.emit()

func _update_stars() -> void:
	stars = 0
	for level in range(1, STAR_THRESHOLDS.size()):
		if crime_points >= STAR_THRESHOLDS[level]: stars = level

func report_contact(point: Vector3) -> void:
	last_known = point
	last_known_valid = true
	contact_age = 0
	hidden_time = 0

func police_can_see(officer: CharacterBody3D) -> bool:
	if "place_id" in state and not state.place_id.is_empty(): return false
	var suspect := pursuit_target()
	if health <= 0 or not state.weapons_allowed() or not suspect.visible: return false
	if officer.global_position.distance_to(suspect.global_position) > 26.875: return false
	var ray := PhysicsRayQueryParameters3D.create(officer.global_position + Vector3.UP * 1.4, suspect.global_position + Vector3.UP, 7, [officer.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.collider == suspect

func pursuit_target() -> Node3D:
	if world != null and world.get("driving") != null and world.driving.occupied:
		return world.driving.car
	return player

var _police_rounds: Array[Dictionary] = []

func police_shoot(officer: CharacterBody3D, amount: float, weapon_id: String = "pistol") -> void:
	if not police_can_see(officer): return
	if _police_rounds.size() >= 128: return
	var visual: Node3D = officer.get("visual")
	if not is_instance_valid(visual) or not visual.has_method("muzzle_position"): return
	var origin: Vector3 = visual.muzzle_position()
	var suspect := pursuit_target()
	var tactical := int(officer.get("tier")) >= 2
	var spread := 0.10 if tactical else 0.13
	var direction := origin.direction_to(suspect.global_position + Vector3.UP).rotated(Vector3.UP, _rng.randf_range(-spread, spread))
	var data := CATALOG.get_weapon(weapon_id)
	var token: Dictionary = effects.police_tracer(origin, direction, 75.0 if tactical else 55.0) if is_instance_valid(effects) else {}
	# A muzzle beyond a thin wall must not start the projectile on its far side.
	var bridge := PhysicsRayQueryParameters3D.create(officer.global_position + Vector3.UP * 1.1, origin, 7, [officer.get_rid()])
	var blocked := get_world_3d().direct_space_state.intersect_ray(bridge)
	_police_rounds.append({"point": origin, "direction": direction, "speed": 75.0 if tactical else 55.0,
		"distance": 0.0, "range": float(data.get("max_range", 420.0)) / 16.0,
		"damage": amount, "data": data, "source": weakref(officer), "rid": officer.get_rid(), "visual": token, "blocked": blocked})
	visual.attack()
	# V1 PoliceOfficer uses pistol for patrol and SMG for every other tier.
	_play_stream(AUDIO.take("pistol" if int(officer.get("tier")) == 0 else "smg", _rng), origin, -7.0, _rng.randf_range(0.95, 1.05))

func _advance_police_rounds(delta: float) -> void:
	for index in range(_police_rounds.size() - 1, -1, -1):
		var round: Dictionary = _police_rounds[index]
		var step := minf(float(round.speed) * delta, float(round.range) - float(round.distance))
		var end: Vector3 = round.point + round.direction * step
		var query := PhysicsRayQueryParameters3D.create(round.point, end, 7, [round.rid])
		var hit: Dictionary = round.blocked if not round.blocked.is_empty() else get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty(): end = hit.position
		round.distance += (round.point as Vector3).distance_to(end)
		round.point = end
		var finished := not hit.is_empty() or float(round.distance) >= float(round.range) - 0.0001
		if is_instance_valid(effects) and not round.visual.is_empty(): effects.move_police_tracer(round.visual, end, finished)
		if not hit.is_empty():
			var data: Dictionary = round.data
			var damage := CATALOG.distance_damage(int(round.damage), float(round.distance) * 16.0, float(data.get("falloff_start", 170.0)), float(data.get("max_range", 420.0)), float(data.get("min_damage_ratio", 0.25)))
			_damage(hit.collider, damage, round.source.get_ref())
			_impact_sound(hit.collider, end, damage)
			_hit_effect(hit, damage, round.direction)
		if finished: _police_rounds.remove_at(index)

func police_reload(officer: Node3D, weapon_id: String) -> void:
	if not is_instance_valid(officer): return
	var sample := AUDIO.reload_take(weapon_id, _rng)
	if sample != null:
		_play_stream(sample, officer.global_position, -9.0, sample.get_length() / maxf(AUDIO.MIN_RELOAD, AUDIO.reload_seconds(weapon_id)))

func _sound(kind: String, point: Vector3) -> void:
	var path := "%s_%d.wav" % [kind, _rng.randi_range(0, 2)]
	if not _audio_cache.has(path): _audio_cache[path] = AUDIO.wav(path)
	if _audio_cache[path] == null: return
	for channel in _audio_pool:
		if channel.playing: continue
		channel.global_position = point
		channel.stream = _audio_cache[path]
		channel.volume_db = -10.0
		channel.pitch_scale = 1.0
		channel.play()
		break

## Toca um stream já carregado no primeiro canal livre do pool posicional.
func _play_stream(stream: AudioStream, point: Vector3, volume_db: float, pitch: float = 1.0) -> void:
	if stream == null: return
	for channel in _audio_pool:
		if channel.playing: continue
		channel.global_position = point
		channel.stream = stream
		channel.volume_db = volume_db
		channel.pitch_scale = pitch
		channel.play()
		return

## Disparo: tiro silenciado usa a amostra `suppressed_*` do V1 (-9 dB, como o V1); o resto, o WAV da arma.
func _shot_sound(id: String, data: Dictionary) -> void:
	if data.get("suppressed", false) and id in SUPPRESSED_WEAPONS:
		var muffled := AUDIO.take("suppressed_" + id, _rng)
		if muffled != null:
			_play_stream(muffled, player.global_position, -19.0)
			return
	_sound(String(data.get("sound_type", id)), player.global_position)

## Golpe no ar do V1: faca = `KnifeAudio.swing`, machado = `BatAudio.swing`, o resto = golpe de punho.
func _melee_swing_sound(_id: String, data: Dictionary) -> void:
	var stance := String(data.get("stance", ""))
	var stream: AudioStream = AUDIO.punch_swing()
	if stance == "knife": stream = AUDIO.knife_sample(-1)
	elif stance == "axe": stream = AUDIO.bat_swing()
	_play_stream(stream, player.global_position, -10.0 + float(data.get("audio_volume_db", -4.0)))

## Lança-chamas: rajada de 0,38 s reiniciada enquanto o gatilho segue (V1 `_flamethrower_audio`).
func _flame_sound() -> void:
	_flame_clock = 0.15
	if _flame_audio.playing: return
	_flame_audio.stream = AUDIO.flamethrower()
	_flame_audio.global_position = player.global_position
	_flame_audio.play()

func _play_reload_audio(id: String, multiplier: float) -> void:
	var stream := AUDIO.reload_take(id, _rng)
	if stream == null: return
	_reload_audio.stream = stream
	_reload_audio.global_position = player.global_position
	_reload_audio.pitch_scale = 1.0 / maxf(multiplier, 0.1)
	_reload_audio.play()

func projectile_bounce(point: Vector3, speed: float) -> void:
	if speed < 1.8: return
	_play_stream(AUDIO.grenade_bounce(), point, -14.0, _rng.randf_range(1.55, 2.05))

## Material do que foi atingido (V1 `ImpactMaterial.resolve`): `impact_material` autorado, gente = corpo,
## veículo = metal, o resto = concreto. Sem nomes de objeto.
func _impact_material(collider: Object) -> String:
	var current := collider as Node
	for depth in 4:
		if not is_instance_valid(current): break
		var authored := String(current.get_meta("impact_material", ""))
		if authored in ["flesh", "metal", "concrete", "wood", "glass"]: return authored
		if String(current.get_meta("gameplay_role", "")) != "" or (current is CharacterBody3D and "dead" in current): return "flesh"
		if "half_length" in current and "speed" in current: return "metal"
		current = current.get_parent()
	return "concrete"

## Som de contato. Impactos do mesmo material no mesmo instante (chumbo) compartilham uma voz, como no V1.
func _impact_sound(collider: Object, point: Vector3, amount: float) -> void:
	var material := _impact_material(collider)
	_recent_impacts = _recent_impacts.filter(func(entry): return _combat_clock - float(entry.time) < IMPACT_GROUP_SECONDS)
	for entry in _recent_impacts:
		if entry.material == material: return
	_recent_impacts.append({"time": _combat_clock, "material": material})
	_play_stream(AUDIO.take("impact_" + material, _rng), point, -14.0 + clampf((amount - 15.0) / 15.0, -0.8, 2.0))

func _update_police(delta: float) -> void:
	police = police.filter(func(unit): return is_instance_valid(unit) and not unit.dead)
	contact_age += delta
	if crime_points > 0 and contact_age > 1.0: hidden_time += delta
	elif crime_points == 0: hidden_time = 0.0
	if crime_points > 0 and stars == 0 and hidden_time > 12.0:
		crime_points = 0
		changed.emit()
	if stars == 0: return
	if hidden_time > (120.0 if stars == 6 else 18.0 + stars * 5.0):
		clear_wanted()
		return
	dispatch_timer -= delta
	if not dispatch_owned and dispatch_timer <= 0 and police.size() < MAX_ACTIVE[stars] and deployed < DEPLOYMENT[stars]:
		dispatch_timer = DISPATCH[stars]
		spawn_officer()

func spawn_officer() -> CharacterBody3D:
	if dispatch_owned: return null
	if not last_known_valid: return null
	for attempt in 16:
		var angle := _rng.randf_range(0, TAU)
		var point := last_known + Vector3(cos(angle), 0, sin(angle)) * 16.0
		point.y = last_known.y + 0.05
		if not _clear_at(point): continue
		var floor_ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP * 2.0, 1)
		var floor_hit := get_world_3d().direct_space_state.intersect_ray(floor_ray)
		if floor_hit.is_empty(): continue
		var unit := OFFICER.new()
		unit.controller = self
		unit.tier = clampi(stars - 2, 0, 4)
		unit.last_known = last_known
		add_child(unit)
		unit.global_position = floor_hit.position + Vector3.UP * 0.05
		police.append(unit)
		deployed += 1
		return unit
	return null

func on_region_changed() -> void:
	_police_rounds.clear()
	_clear_combat_registers()
	_swing_age = -1.0
	_aim_hold = 0.0
	_recoil = 0.0
	_rig_pose.reset()
	_pose_frame = {}
	_muzzle_timer = 0.0
	for light in [_muzzle_light, _muzzle_flash]:
		if is_instance_valid(light): light.hide()
	for voice in [_flame_audio, _reload_audio]:
		if is_instance_valid(voice): voice.stop()
	_cancel_combat_clip()
	if is_instance_valid(player) and player.has_method("clear_combat_weapon_pose"): player.clear_combat_weapon_pose()
	_present(NAN, "", 0.0)
	if is_instance_valid(effects): effects.clear()
	for unit in get_children():
		if unit.get_meta("gameplay_role","") == "police": unit.queue_free()
	police.clear()
	last_known = Vector3.ZERO
	last_known_valid = false
	contact_age = 10.0
	hidden_time = 0.0
	_occupancy.clear()

func clear_wanted() -> void:
	stars = 0
	crime_points = 0
	hidden_time = 0
	deployed = 0
	last_known_valid = false
	for unit in police:
		if is_instance_valid(unit): unit.queue_free()
	police.clear()
	changed.emit()

func _clear_at(point: Vector3, mask: int = 1) -> bool:
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 1.5, 0.7)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform.origin = point + Vector3.UP
	query.collision_mask = mask
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _walkable_at(point: Vector3) -> bool:
	if not _clear_at(point): return false
	var floor_ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.6, point - Vector3.UP * 0.8, 1)
	return not get_world_3d().direct_space_state.intersect_ray(floor_ray).is_empty()

func find_path(start: Vector3, finish: Vector3) -> PackedVector3Array:
	if not _benchmark_costs: return _find_path(start,finish)
	var started := Time.get_ticks_usec()
	var result := _find_path(start,finish)
	var duration := Time.get_ticks_usec()-started
	if duration > 2000 and is_instance_valid(world):
		var costs: Array = world.get_meta("perf_costs",[])
		if costs.size() < 512:
			costs.append({"label":"gameplay.find_path","start_usec":started,"duration_usec":duration})
			world.set_meta("perf_costs",costs)
	return result

func _find_path(start: Vector3, finish: Vector3) -> PackedVector3Array:
	# Bounded local A* in native world metres. Static solid probes are cached;
	# CharacterBody3D remains the final authority for dynamic collisions.
	var from := Vector2i(roundi(start.x / 2), roundi(start.z / 2))
	var to := Vector2i(roundi(finish.x / 2), roundi(finish.z / 2))
	if from == to: return PackedVector3Array([finish])
	var frontier: Array[Vector2i] = [from]
	var previous: Dictionary = {}
	var costs: Dictionary = {from: 0.0}
	var dynamic_clear: Dictionary = {}
	var best := from
	for iteration in 256:
		if frontier.is_empty(): break
		var chosen := 0
		var score := INF
		for index in frontier.size():
			var value: float = costs[frontier[index]] + Vector2(frontier[index] - to).length()
			if value < score:
				score = value
				chosen = index
		var current: Vector2i = frontier.pop_at(chosen)
		if Vector2(current - to).length_squared() < Vector2(best - to).length_squared(): best = current
		if current == to:
			best = current
			break
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + offset
			if Vector2(next - from).length() > 20: continue
			var key := Vector3i(next.x, roundi(start.y), next.y)
			if not _occupancy.has(key): _occupancy[key] = _walkable_at(Vector3(next.x * 2, start.y, next.y * 2))
			if not _occupancy[key]: continue
			# Cars change position, so their occupancy lasts only for this path
			# request. This also lets crews walk around their own parked ambulance.
			if not dynamic_clear.has(next): dynamic_clear[next] = _clear_at(Vector3(next.x * 2, start.y, next.y * 2), 4)
			if not dynamic_clear[next]: continue
			var cost: float = costs[current] + 1
			if costs.has(next) and costs[next] <= cost: continue
			costs[next] = cost
			previous[next] = current
			if not frontier.has(next): frontier.append(next)
	var reverse: Array[Vector3] = []
	while best != from and previous.has(best):
		reverse.append(Vector3(best.x * 2, start.y, best.y * 2))
		best = previous[best]
	reverse.reverse()
	return PackedVector3Array(reverse)

## Material do traço na cor da arma (`tracer_color` do catálogo, como o V1); cache por cor.
func _tracer_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _tracer_materials.has(key):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		_tracer_materials[key] = material
	return _tracer_materials[key]

func _trace(from: Vector3, to: Vector3, lifetime: float, width: float, color: Color = Color(0, 0, 0, 0)) -> void:
	if _effects.size() >= 48: return
	var distance := from.distance_to(to)
	if distance < 0.01: return
	var effect := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width, distance)
	effect.mesh = mesh
	effect.material_override = _flash_material if color.a <= 0.0 else _tracer_material(color)
	effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(effect)
	effect.global_position = (from + to) * 0.5
	effect.look_at(to)
	_effects.append({"node": effect, "remaining": lifetime})

func _update_effects(delta: float) -> void:
	for index in range(_effects.size() - 1, -1, -1):
		_effects[index].remaining -= delta
		if _effects[index].remaining <= 0:
			_effects[index].node.queue_free()
			_effects.remove_at(index)

func drop_ammo(point: Vector3, id: String) -> void:
	var pickup := Node3D.new()
	add_child(pickup)
	pickup.global_position = point + Vector3.UP * 0.15
	pickup.rotation.z = PI / 2
	ARSENAL.build(pickup, id)
	_loot.append({"node": pickup, "weapon": id, "remaining": 60.0})

func _update_loot(delta: float) -> void:
	for index in range(_loot.size() - 1, -1, -1):
		var loot: Dictionary = _loot[index]
		loot.remaining -= delta
		var collected := false
		if attack_allowed() and loot.node.global_position.distance_to(player.global_position) < 1.0:
			if state.owns_weapon(loot.weapon):
				state.add_ammo(loot.weapon, 12)
				collected = true
			elif state.has_method("grant_weapon"):
				collected = state.grant_weapon(loot.weapon)
		if collected or loot.remaining <= 0:
			loot.node.queue_free()
			_loot.remove_at(index)
			if collected:
				message.emit("Munição recolhida.")
				changed.emit()

func snapshot() -> Dictionary:
	return {"health": health, "armor": armor, "crime_points": crime_points, "hidden_time": hidden_time, "customization": customization.duplicate(true)}

static func validate_snapshot(data: Dictionary) -> bool:
	for key in ["health", "armor", "crime_points", "hidden_time"]:
		if not data.has(key) or (typeof(data[key]) != TYPE_FLOAT and typeof(data[key]) != TYPE_INT) or not is_finite(float(data[key])): return false
	if float(data.health) < 0 or float(data.health) > 100 or float(data.armor) < 0 or float(data.armor) > 100: return false
	if float(data.crime_points) != floorf(float(data.crime_points)) or float(data.crime_points) < 0 or float(data.crime_points) > 300: return false
	if float(data.hidden_time) < 0 or float(data.hidden_time) > 120: return false
	if data.has("customization") and not data.customization is Dictionary: return false
	var restored_customization: Dictionary = CUSTOM.normalize(data.get("customization", {}))
	if restored_customization != data.get("customization", {}): return false
	return true

func restore_state(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	var restored_customization: Dictionary = CUSTOM.normalize(data.get("customization", {}))
	clear_wanted()
	health = float(data.health)
	armor = float(data.armor)
	crime_points = int(data.crime_points)
	hidden_time = float(data.hidden_time)
	customization = restored_customization
	visual_id = "@rebuild"
	_update_stars()
	last_known = player.global_position if is_instance_valid(player) else Vector3.ZERO
	last_known_valid = stars > 0
	dispatch_timer = 3
	_dead_notified = health <= 0
	changed.emit()
	return true
