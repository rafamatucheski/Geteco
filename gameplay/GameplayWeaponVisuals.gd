extends RefCounted
## Arma na mão do Gameplay (modelo, pose do rig, peças móveis da recarga, lanterna, laser, clarão de boca)
## e efeitos de contato/traço, separados em 31/10 para o Gameplay.gd caber na leitura. Os nós e o estado
## (gun, flashlight, _muzzle_flash, _pose_frame...) continuam no Gameplay, onde testes e o Actor os leem;
## as funções antigas do Gameplay viraram delegações de uma linha, na mesma ordem de chamada.
## `g` fica como Node3D, e não como o script do Gameplay, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: testes sobrescrevem algumas delas numa
## subclasse do Gameplay (_play_stream, _kick_camera, _hit_effect...) e o despacho tem de continuar igual.

const ARSENAL = preload("res://gameplay/ArsenalWeapon3D.gd")
const AUDIO = preload("res://gameplay/CombatAudio.gd")
const CATALOG = preload("res://gameplay/WeaponCatalog.gd")
const CUSTOM = preload("res://gameplay/WeaponCustomization.gd")
const KATANA_MODEL := preload("res://gameplay/KatanaModel.gd")
const POSE = preload("res://gameplay/WeaponPoseData.gd")
const RIG_POSE = preload("res://gameplay/WeaponRigPose.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## Arma na mão a partir de modelo pronto (21/10): cada troca de arma montava de novo o modelo procedural
## inteiro (malhas primitivas novas e dezenas de nós). ArsenalWeapon3D.build_cached monta uma vez por arma
## e depois só duplica os nós, com malhas e materiais compartilhados; acessórios e pintura continuam
## criando cópias próprias (WeaponAttachmentVisuals duplica antes de recolorir). Span gameplay.weapon_visual.
## GETECO_WEAPON_TEMPLATE=0 volta a montar do zero a cada troca, para A/B no mesmo export.
static var _weapon_template := OS.get_environment("GETECO_WEAPON_TEMPLATE") != "0"
## Lanterna na lente da peça montada (WeaponCustomization.fit, "TacticalFlashlight"),
## não na origem da arma. Inclinada para baixo: com a câmera alta, um facho reto na
## altura da mão só tocava o chão como uma mancha pequena à frente do Dante.
const FLASHLIGHT_TILT := -0.20

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

func _update_visual() -> void:
	if g.gun == null: return
	var id: String = g.equipped()
	g._update_back_katana(id)
	# Durante o guardar, a katana continua na mão até o clipe terminar (ela vai para as costas).
	if g._sheath_kind == "holster" and g._sheath_clip != "": id = g.visual_id
	var blade_style := {}
	if id == "katana":
		blade_style = g.katana_style()
		var style_key := str(blade_style)
		if style_key != g._katana_style:
			g.visual_id = "@katana_style"
			g._katana_style = style_key
	if id != g.visual_id:
		for child in g.gun.get_children():
			if child == g.flashlight: continue
			g.gun.remove_child(child)
			child.queue_free()
		g.visual_id = id
		g._muzzle_flash = null
		g._muzzle_light = null
		g._muzzle_timer = 0.0
		if id != "" and id != "fists" and CATALOG.WEAPONS.has(id):
			var visual_began := STALL_WORK.begin()
			var muzzle: Vector3 = KATANA_MODEL.build(g.gun, blade_style.saber, blade_style.color) if id == "katana" else (ARSENAL.build_cached(g.gun, id) if _weapon_template else ARSENAL.build(g.gun, id))
			CUSTOM.fit(g.gun, id, g.customization, muzzle)
			g._build_muzzle_flash(id, muzzle)
			g._mount_flashlight()
			STALL_WORK.finish_slow("gameplay.weapon_visual", visual_began, 2000, g)
		if g.player.has_method("set_combat_weapon_mount"):
			g.player.set_combat_weapon_mount(g.gun, POSE.GRIPS.get(id, Vector3.ZERO))
	g.gun.visible = g.attack_allowed() and id != "" and id != "fists" and bool(g._pose_frame.get("visible", true)) and g._sheath_clip == ""
	# A arma e as palmas usam o mesmo alvo em espaço do Actor. Isso preserva a
	# orientação do cabo dentro da mão; não há mais um prop plano girado só em Y.
	if g.gun.visible and not g._pose_frame.is_empty() and is_instance_valid(g.player.visual) and not g._pose_frame.has("hand_grip"):
		if g.player.has_method("combat_weapon_transform"):
			g.gun.global_transform = g.player.combat_weapon_transform(POSE.GRIPS.get(id, Vector3.ZERO))
		else:
			var local_basis: Basis = g._pose_frame.basis
			g.gun.global_transform = Transform3D((g.player.visual.global_basis * local_basis).orthonormalized(), g.player.visual.to_global(g._pose_frame.gun_origin))
		g._update_weapon_parts(id)
	g._update_left_knuckles(id)
	g.flashlight.visible = g.gun.visible and g.flashlight_enabled and CUSTOM.installed(g.customization, id)
	var laser_part: String = CUSTOM.selected(g.customization, id, "laser")
	# Laser só enquanto o jogador mira (botão de mirar), saindo do módulo na arma e
	# seguindo o cano. Antes ficava sempre aceso e nascia do peito do Dante, na
	# direção do mouse, desligado da arma (feedback de 25/09/2026).
	var lens := g.gun.find_child("LaserLens", true, false) as Node3D
	g.laser.visible = g.gun.visible and laser_part != "none" and g.aim_active and lens != null
	if g.laser.visible:
		var origin := lens.global_position
		var direction: Vector3 = -g.gun.global_basis.z
		direction.y = 0.0
		if direction.length_squared() < 0.001: direction = g._aim_direction()
		if direction.length_squared() < 0.001: direction = Vector3.FORWARD
		var ray := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * 35, 7, [(g.player as CharacterBody3D).get_rid()])
		var hit: Dictionary = g.get_world_3d().direct_space_state.intersect_ray(ray)
		var end: Vector3 = hit.get("position", ray.to)
		g.laser.global_position = (origin + end) * 0.5
		g.laser.look_at(end)
		g.laser.scale.z = maxf(0.01, origin.distance_to(end))
		g.laser.material_override.albedo_color = Color("58e07c") if laser_part == "laser_green" else Color("e5493c")

func _mount_flashlight() -> void:
	var mount := g.gun.find_child("TacticalFlashlight", true, false) as Node3D
	var lens := mount.find_child("Lens", true, false) as Node3D if mount != null else null
	g.flashlight.position = g.gun.to_local(lens.global_position) if lens != null else Vector3.ZERO
	g.flashlight.rotation = Vector3(FLASHLIGHT_TILT, 0.0, 0.0)

func _update_left_knuckles(id: String) -> void:
	# Com a mala na mão esquerda não há soqueira esquerda.
	var wanted: bool = id == "knuckles" and g.gun.visible and g.player.has_method("combat_left_palm_transform") and not bool(g._pose_frame.get("bag_carry", false))
	if not wanted:
		if is_instance_valid(g._left_knuckles): g._left_knuckles.visible = false
		return
	if not is_instance_valid(g._left_knuckles):
		g._left_knuckles = Node3D.new()
		g._left_knuckles.name = "LeftKnuckles"
		g._left_knuckles.top_level = true
		g.gun.get_parent().add_child(g._left_knuckles)
		ARSENAL.build(g._left_knuckles, "knuckles")
	g._left_knuckles.visible = true
	# A fileira de anéis segue o eixo Y da palma, igual à soqueira da direita.
	g._left_knuckles.global_transform = g.player.combat_left_palm_transform() * Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -POSE.GRIPS.knuckles)

func _update_weapon_pose(delta: float) -> void:
	if not is_instance_valid(g.player): return
	var id: String = g.equipped()
	if id.is_empty(): id = "fists"
	var speed_now: float = Vector2(g.player.velocity.x, g.player.velocity.z).length()
	var moving := speed_now > 0.12
	var sprinting := speed_now > 4.2
	var progress := 0.0
	if g.reload_timer > 0.0 and g._reload_total > 0.0: progress = clampf(1.0 - g.reload_timer / g._reload_total, 0.0, 1.0)
	var rig: Dictionary = g.player.combat_rig_info() if g.player.has_method("combat_rig_info") else {}
	rig["bag_carry"] = g.state.get("economy") != null and g.state.economy.grid_handbag()
	rig["clip_punch"] = g._clip_name.begins_with("ual/Punch")
	if id == "grenade":
		# A próxima granada vem da reserva quando a mão termina a recuperação,
		# inclusive ao equipar um save com a mão vazia. Sem recarga de pistola.
		var ammo: Dictionary = g.state.get_ammo(id)
		var recovered: bool = g._rig_pose.weapon_id != id or g._rig_pose.action_age + delta >= RIG_POSE.GRENADE_RECOVERY
		if int(ammo.get("magazine", 0)) == 0 and int(ammo.get("reserve", 0)) > 0 and recovered and g._pending_contact.is_empty() and g.reload_timer <= 0.0 and g.attack_allowed():
			if g.state.reload_weapon(id, 1):
				ammo = g.state.get_ammo(id)
				g.changed.emit()
		rig.loaded = int(ammo.get("magazine", 0)) > 0
	rig["action_rate"] = g._melee_rate if not g._melee_action.is_empty() else 1.0
	g._pose_frame = g._rig_pose.update(id, delta, g.aiming, g.reload_timer > 0.0, progress, moving, sprinting, float(g.player.phase), rig)
	if id == "shotgun" and g.reload_timer <= 0.0 and float(g._pose_frame.get("pump", 0.0)) > 0.02 and g._shotgun_pump_sound_serial != g._attack_serial:
		g._shotgun_pump_sound_serial = g._attack_serial
		g._play_weapon_stream(AUDIO.shotgun_pump(), g.player.global_position, -8.0 + g._rng.randf_range(-1.0, 1.0), g._rng.randf_range(0.97, 1.03), 12.0)
	if "sword_clip_set" in g.player: g.player.sword_clip_set = "ss" if id == "sword_shield" else "gs"
	var sword_clips: bool = id in g.NATIVE_SWORDS and g._sword_locomotion_clips()
	if "sword_locomotion" in g.player: g.player.sword_locomotion = sword_clips
	if "sword_block" in g.player: g.player.sword_block = g.shield_block
	if id in g.NATIVE_SWORDS:
		if sword_clips or g._clip_name.begins_with("mixsword/"):
			# Clipes do Mixamo (parado, andando, correndo e golpes): o clipe move os braços. A katana vai nas
			# duas mãos, com o fio para o inimigo; a espada do escudo, só na direita.
			g._pose_frame = {"visible": true, "armed": true, "native_sword": true, "hand_grip": g.HAND_SWORD_HELD if id == "sword_shield" else g.HAND_KATANA_HELD, "melee_action": g._clip_name != ""}
		else:
			# Sem a biblioteca do Mixamo: carregar procedural (lâmina para cima) e cortes de reserva.
			var ready: bool = g.aiming or g._combat_clock - g._katana_attack_clock < g._katana_moves.READY_SECONDS or (is_instance_valid(g.rage) and g.rage.active)
			g._pose_frame = g._katana_moves.update(delta, speed_now, float(g.player.phase), float(rig.get("body_bob", 0.0)), g.player.visual.rotation.y, ready, g._katana_combo, g._rig_pose.action_age)
	if g.player.has_method("set_combat_weapon_pose"):
		g.player.set_combat_weapon_pose(id, g._pose_frame)

func _update_weapon_parts(id: String) -> void:
	if id == "sawed_off":
		preload("res://gameplay/SawedOffPresentation.gd").update_parts(g.gun, float(g._pose_frame.get("break_open", 0.0)))
	var pump := g.gun.get_node_or_null("Pump") as Node3D
	if pump != null: pump.position.z = -0.16 + float(g._pose_frame.get("pump", 0.0))
	var slide := g.gun.get_node_or_null("Slide") as Node3D
	if slide != null:
		if not slide.has_meta("combat_rest_position"): slide.set_meta("combat_rest_position", slide.position)
		slide.position = (slide.get_meta("combat_rest_position") as Vector3) + Vector3(0, 0, 0.045 * float(g._pose_frame.get("slide", 0.0)))
	var cylinder := g.gun.get_node_or_null("ReloadCylinder") as Node3D
	if cylinder != null:
		var progress: float = clampf(1.0 - g.reload_timer / maxf(g._reload_total, 0.001), 0.0, 1.0) if g.reload_timer > 0.0 else 1.0
		var opening: float = smoothstep(0.05, 0.18, progress) * (1.0 - smoothstep(0.79, 0.92, progress)) if g.reload_timer > 0.0 else 0.0
		cylinder.position.x = -0.065 * opening
		cylinder.rotation.z = -0.45 * opening
	var magazine := g.gun.get_node_or_null("CurvedMagazine") as Node3D
	if magazine != null: g._update_magazine(magazine)
	var rocket := g.gun.get_node_or_null("LoadedRocket") as Node3D
	if rocket != null: g._update_rocket(rocket, id)

## Carregador destacável (AK-47) na mesma linha do tempo de `WeaponRigPose.reload_targets`:
## o vazio desce e cai ao soltar (0,09–0,20), a mão busca o novo no cinto e o traz
## preso à palma até o encaixe (0,30–0,45). Fora da recarga fica no lugar original.
func _update_magazine(magazine: Node3D) -> void:
	if not magazine.has_meta("combat_rest_transform"): magazine.set_meta("combat_rest_transform", magazine.transform)
	var rest: Transform3D = magazine.get_meta("combat_rest_transform")
	var progress: float = clampf(1.0 - g.reload_timer / maxf(g._reload_total, 0.001), 0.0, 1.0) if g.reload_timer > 0.0 else 1.0
	magazine.visible = true
	magazine.transform = rest
	if g.reload_timer <= 0.0: return
	if progress < 0.20 and progress >= 0.09:
		var fall := smoothstep(0.09, 0.20, progress)
		magazine.transform = rest.translated_local(Vector3(0, -0.16 * fall * fall, 0.02 * fall))
		magazine.visible = progress < 0.19
	elif progress < 0.30 and progress >= 0.20:
		magazine.visible = false
	elif progress < 0.45 and progress >= 0.30 and g.player.has_method("combat_left_palm_transform"):
		# Centro do carregador (espaço da arma) na palma esquerda, alinhado à arma.
		var center: Vector3 = g.gun.global_transform * Vector3(0, -0.10, -0.07)
		var palm: Vector3 = g.player.combat_left_palm_transform().origin
		var seat := smoothstep(0.40, 0.45, progress)
		magazine.global_position += (palm - center) * (1.0 - seat)

## Foguete do lança-foguetes na linha do tempo de `WeaponRigPose.reload_targets`: na
## palma esquerda desde a pega no cinto, encaixado na boca até o fim. Antes aparecia
## direto na arma a 65% e a mão subia vazia, como quem acena.
func _update_rocket(rocket: Node3D, id: String) -> void:
	if not rocket.has_meta("combat_rest_transform"): rocket.set_meta("combat_rest_transform", rocket.transform)
	rocket.transform = rocket.get_meta("combat_rest_transform")
	if g.reload_timer <= 0.0:
		rocket.visible = int(g.state.get_ammo(id).get("magazine", 0)) > 0
		return
	var progress: float = clampf(1.0 - g.reload_timer / maxf(g._reload_total, 0.001), 0.0, 1.0)
	rocket.visible = progress >= RIG_POSE.RPG_ROCKET_GRAB
	if rocket.visible and g.player.has_method("combat_left_palm_transform"):
		var palm: Vector3 = g.player.combat_left_palm_transform().origin
		var seat := smoothstep(RIG_POSE.RPG_ROCKET_SEAT.x, RIG_POSE.RPG_ROCKET_SEAT.y, progress)
		rocket.global_position += (palm - rocket.global_position) * (1.0 - seat)

## Clarão de boca do V1 (`Player._update_equipped_weapon_3d_mesh`): só armas de fogo,
## lança-foguetes e lança-chamas. Corpo a corpo e granada não têm boca.
func _build_muzzle_flash(id: String, muzzle: Vector3) -> void:
	var data: Dictionary = CATALOG.WEAPONS.get(id, {})
	if data.get("is_melee", false) or data.get("is_grenade", false): return
	var tip := muzzle
	if CUSTOM.selected(g.customization, id, "barrel") == "barrel_long":
		tip.z -= preload("res://gameplay/WeaponAttachmentVisuals.gd").LONG_BARREL
	match CUSTOM.selected(g.customization, id, "muzzle"):
		"suppressor": tip.z -= 0.145
		"compensator": tip.z -= 0.048
		"choke_full": tip.z -= 0.04
		"duckbill": tip.z -= 0.06
		"flame_focus": tip.z -= 0.10
		"flame_wide": tip.z -= 0.07
	g._muzzle_flash = MeshInstance3D.new()
	g._muzzle_flash.mesh = g._directional_flash_mesh()
	g._muzzle_flash.material_override = g._muzzle_material
	g._muzzle_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g._muzzle_flash.position = tip
	g._muzzle_flash.visible = false
	g.gun.add_child(g._muzzle_flash)
	g._muzzle_light = OmniLight3D.new()
	g._muzzle_light.light_color = Color(1.0, 0.7, 0.2)
	g._muzzle_light.light_energy = 2.8
	g._muzzle_light.omni_range = 2.5
	g._muzzle_light.shadow_enabled = false
	g._muzzle_light.position = tip
	g._muzzle_light.visible = false
	g.gun.add_child(g._muzzle_light)

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
	if is_instance_valid(g._muzzle_flash): return g._muzzle_flash.global_position
	if is_instance_valid(g.gun): return g.gun.global_position - g.gun.global_basis.z * 0.2
	return g.player.global_position + Vector3.UP * 1.05

## `Player._trigger_muzzle_flash_3d`: escala e duração por arma; silenciador reduz o clarão e apaga a luz.
func _flash_muzzle(id: String) -> void:
	if not is_instance_valid(g._muzzle_flash) or not is_instance_valid(g._muzzle_light): return
	var heavy: bool = id in g.HEAVY_FLASH or id == "shotgun_auto"
	var suppressed: bool = bool(CATALOG.WEAPONS.get(id,{}).get("suppressed",false)) or CUSTOM.selected(g.customization, id, "muzzle") == "suppressor"
	var scale_value := Vector3.ONE * (1.0 if heavy else 0.62)
	if id == "smg_compact": scale_value *= 0.80
	elif id == "smg_tactical": scale_value *= 0.92
	elif id == "shotgun_auto": scale_value *= 0.85
	if suppressed: scale_value *= 0.22
	if id == "flamethrower": scale_value = Vector3(0.30, 0.30, 1.65)
	elif id == "rpg": scale_value = Vector3(0.55, 0.55, 1.7)
	g._muzzle_flash.scale = scale_value
	g._muzzle_flash.visible = true
	g._muzzle_light.visible = not suppressed
	g._muzzle_timer = 0.075 if id == "flamethrower" else (0.09 if id == "rpg" else (0.065 if heavy else 0.035))
	if is_instance_valid(g.effects) and id != "flamethrower":
		var muzzle_pos: Vector3 = g._muzzle_world_position()
		var aim_dir: Vector3 = -g.gun.global_transform.basis.z if is_instance_valid(g.gun) else -g.player.global_transform.basis.z
		g.effects.muzzle_smoke(muzzle_pos, aim_dir)

## Efeito visual do contato: sangue nos corpos (e mancha se morreram), faísca/poeira nos demais.
## Alvo protegido não sangra. `hit` tem o formato do resultado do raio (collider, position, normal).
func _hit_effect(hit: Dictionary, amount: float, direction: Vector3) -> void:
	if not is_instance_valid(g.effects): return
	var collider: Object = hit.collider
	if not is_instance_valid(collider): return
	var material: String = g._impact_material(collider, hit.position, hit.normal)
	if material == "flesh":
		if g._is_invulnerable(collider): return
		g.effects.blood(hit.position, direction, amount)
		g._pain_voice(collider as Node3D, amount)
		var victim := collider as Node3D
		if victim != null and victim.get("dead") == true:
			# Uma poça por cadáver, sob o tronco: o corpo tomba ~0,7 m no sentido do golpe.
			if not victim.has_meta("v2_blood_pool"):
				victim.set_meta("v2_blood_pool", true)
				var flat := Vector3(direction.x, 0.0, direction.z).normalized()
				g.effects.stain(victim.global_position + flat * 0.7, 0.75)
		elif amount >= 18.0 and randf() < 0.5:
			# Respingo cai adiante, no sentido do tiro, não sob o ponto do impacto.
			var spray := Vector3(direction.x, 0.0, direction.z).normalized() * randf_range(0.6, 1.3)
			g.effects.stain(hit.position + spray, randf_range(0.18, 0.3))
	else:
		g.effects.impact(hit.position, hit.normal, material, amount)

## Material do traço na cor da arma (`tracer_color` do catálogo, como o V1); cache por cor.
func _tracer_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not g._tracer_materials.has(key):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		g._tracer_materials[key] = material
	return g._tracer_materials[key]

func _trace(from: Vector3, to: Vector3, lifetime: float, width: float, color: Color = Color(0, 0, 0, 0)) -> void:
	if g._effects.size() >= 48: return
	var distance := from.distance_to(to)
	if distance < 0.01: return
	var effect := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, width, distance)
	effect.mesh = mesh
	effect.material_override = g._flash_material if color.a <= 0.0 else g._tracer_material(color)
	effect.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(effect)
	effect.global_position = (from + to) * 0.5
	effect.look_at(to)
	g._effects.append({"node": effect, "remaining": lifetime})

func _update_effects(delta: float) -> void:
	for index in range(g._effects.size() - 1, -1, -1):
		g._effects[index].remaining -= delta
		if g._effects[index].remaining <= 0:
			g._effects[index].node.queue_free()
			g._effects.remove_at(index)
