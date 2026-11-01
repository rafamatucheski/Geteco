extends RefCounted
## Katana e bainha do Gameplay: katanas das costas e da mão, escudo no antebraço, sacar e guardar com os
## clipes do Mixamo, golpes nativos da katana e da espada e escudo, zumbido do sabre e o pedido de RAGE.
## Separado em 01/11 (Onda 2 de docs/plano-divisao-arquivos-grandes-20261101.md) para o Gameplay.gd caber
## na leitura. Os nós e o estado (back_katana, hand_katana, hand_shield, _sheath_*, _katana_combo,
## _clip_*...) e as constantes medidas (KATANA_ATTACKS, HAND_KATANA_*...) continuam no Gameplay, onde
## testes e o Actor os leem; cada função antiga virou delegação de uma linha com a mesma assinatura.
## `g` fica como Node3D, e não como o script do Gameplay, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: testes sobrescrevem attack_allowed e
## equipped numa subclasse do Gameplay e o despacho tem de continuar igual.

const FORGE := preload("res://gameplay/forge/BladeForge.gd")
const KATANA_AUDIO := preload("res://gameplay/KatanaAudio.gd")
const KATANA_MODEL := preload("res://gameplay/KatanaModel.gd")
const RAGE := preload("res://gameplay/KatanaRage.gd")
const SWORD_SHIELD_MODEL := preload("res://gameplay/SwordShieldModel.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

## Katana presa nas costas: o modelo vai no osso da coluna e aparece quando a arma não está na mão.
## Cabo no ombro direito (−X), lâmina descendo até o quadril esquerdo (+X); a ponta fica em −Z do modelo.
## Posição e rumo estimados pelo esqueleto, não medidos na tela: conferir no jogo.
func _build_back_katana() -> void:
	var skeleton := g.player.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null or skeleton.find_bone("Spine02") < 0 or skeleton.find_bone("RightHand") < 0: return
	g.back_katana = g._katana_on_bone(skeleton, "Spine02", "BackKatana")
	g.back_katana.transform = g.BACK_KATANA_LOCAL
	g.hand_katana = g._katana_on_bone(skeleton, "RightHand", "SheathHandKatana")
	if skeleton.find_bone("LeftForeArm") < 0: return
	var forearm := BoneAttachment3D.new()
	forearm.bone_name = "LeftForeArm"
	skeleton.add_child(forearm)
	g.hand_shield = Node3D.new()
	g.hand_shield.name = "HandShield"
	forearm.add_child(g.hand_shield)
	SWORD_SHIELD_MODEL.build_shield(g.hand_shield)
	g.hand_shield.transform = g.SHIELD_FOREARM_LOCAL
	g.hand_shield.visible = false

func _katana_on_bone(skeleton: Skeleton3D, bone: String, node_name: String) -> Node3D:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	var katana := Node3D.new()
	katana.name = node_name
	attachment.add_child(katana)
	KATANA_MODEL.build(katana, false, Color("68cfff"))
	if FORGE.legendary(g.customization, "katana"): preload("res://gameplay/WeaponAttachmentVisuals.gd").legendary(katana, "katana")
	katana.visible = false
	return katana

## Remonta a lâmina na mão no próximo quadro e as katanas das costas/bainha agora.
func refresh_blade_visuals() -> void:
	g.visual_id = "@rebuild"
	for katana: Node3D in [g.back_katana, g.hand_katana]:
		if not is_instance_valid(katana): continue
		var shown := katana.visible
		for child in katana.get_children():
			katana.remove_child(child)
			child.free()
		if katana.has_meta("forge_legendary"): katana.remove_meta("forge_legendary")
		KATANA_MODEL.build(katana, false, Color("68cfff"))
		if FORGE.legendary(g.customization, "katana"): preload("res://gameplay/WeaponAttachmentVisuals.gd").legendary(katana, "katana")
		katana.visible = shown

func katana_style() -> Dictionary:
	var honor: Dictionary = g.state.world_state.get("takeshi", {}) if g.state != null else {}
	return {"saber": bool(honor.get("saber_unlocked", false)), "color": Color.from_string(str(honor.get("saber_color", "68cfffff")), Color("68cfff"))}

func _update_saber_audio() -> void:
	if not is_instance_valid(g._saber_hum): return
	var should_play: bool = g.equipped() == "katana" and g.gun.visible and g.katana_style().saber
	if should_play:
		g._saber_hum.global_position = g.player.global_position + Vector3.UP
		if not g._saber_hum.playing:
			g._saber_hum.stream = KATANA_AUDIO.stream("hum")
			g._saber_hum.play()
	elif g._saber_hum.playing: g._saber_hum.stop()

## Sacar (katana guardada → mão) e guardar (mão → costas) com os clipes do Mixamo. Só dispara na troca
## de arma; sem o clipe na biblioteca, a troca segue instantânea.
func _update_back_katana(id: String) -> void:
	if id != g._sheath_last_id and g._sheath_last_id != "":
		if id == "katana": g._start_sheath("draw")
		elif g._sheath_last_id == "katana": g._start_sheath("holster")
		g._weapon_switch_sound(g._sheath_last_id, id)
	g._sheath_last_id = id
	if g.hand_shield != null and is_instance_valid(g.player): g.hand_shield.visible = id == "sword_shield" and not bool(g.player.get("dead"))
	if g.back_katana == null or not is_instance_valid(g.player): return
	var carried: bool = g.state != null and bool(g.state.owns_weapon("katana")) and not bool(g.player.get("dead"))
	var moving: bool = g._sheath_clip != ""
	# O Actor leva COMBAT_BLEND (0,08 s) para passar da locomoção ao clipe: no início do saque a mão ainda
	# não chegou às costas, então a espada só troca de lugar depois disso.
	var in_hand: bool = moving and not (g._sheath_kind == "draw" and g._sheath_age < g.SHEATH_HANDOFF)
	# Durante o clipe a espada está na mão; fora dele, nas costas ou na pose de combate.
	g.back_katana.visible = carried and ((id != "katana" and not moving) or (moving and not in_hand))
	if g.hand_katana != null: g.hand_katana.visible = carried and in_hand

func _sword_locomotion_clips() -> bool:
	return is_instance_valid(g.player) and g.player.has_method("has_sword_locomotion") and g.player.has_sword_locomotion()

func _start_sheath(kind: String) -> void:
	if not is_instance_valid(g.player) or not "animation" in g.player or g.player.animation == null: return
	var clip := "mixsword/sheathe_greatsword"
	if not g.player.animation.has_animation(clip):
		clip = "mixsword/withdraw_katana" if kind == "draw" else "mixsword/sheathe_katana"
		if not g.player.animation.has_animation(clip): return
	g._sheath_kind = kind
	g._sheath_clip = clip
	g._sheath_length = g.SHEATH_DRAW_DURATION if kind == "draw" else g.SHEATH_HOLSTER_DURATION
	g._sheath_age = 0.0

func _update_sheath(delta: float) -> void:
	if g._sheath_clip == "": return
	if not is_instance_valid(g.player) or bool(g.player.get("dead")) or not g.attack_allowed():
		g._end_sheath()
		return
	g._sheath_age += delta
	if g._sheath_age >= g._sheath_length:
		g._end_sheath()
		return
	if "combat_clip" in g.player:
		var clip_length: float = g.player.animation.get_animation(g._sheath_clip).length
		var progress := clampf(g._sheath_age / g._sheath_length, 0.0, 1.0)
		# Só o clipe da greatsword vai ao contrário ao sacar; os de reserva já têm o sentido certo.
		if g._sheath_kind == "draw" and g._sheath_clip.ends_with("sheathe_greatsword"):
			# Primeiro alcança o cabo nas costas durante a mistura do Actor; depois puxa a lâmina.
			progress = 1.0 - clampf((g._sheath_age - g.SHEATH_HANDOFF) / (g._sheath_length - g.SHEATH_HANDOFF), 0.0, 1.0)
		g.player.combat_clip = g._sheath_clip
		g.player.combat_clip_time = clip_length * progress
		# O IK da arma seguinte não pode sobrescrever os braços do clipe de sacar/guardar.
		# Mantém também as pernas de locomoção quando o jogador troca de arma andando.
		g._pose_frame = {"visible": false, "armed": true, "native_sword": true, "hand_grip": g.HAND_KATANA_HELD}
		# "combat_clip" só existe em Actor.gd, que também define set_combat_weapon_pose: chamada direta.
		g.player.set_combat_weapon_pose("katana", g._pose_frame)
		# A pegada gira junto com o clipe: guarda (lâmina à frente) no início, posição das costas no fim.
		if g.hand_katana != null and g._sheath_clip.ends_with("sheathe_greatsword"):
			# As medidas autoradas têm quatro casas decimais: normalize antes do slerp.
			g.hand_katana.transform = g.HAND_KATANA_HELD.orthonormalized().interpolate_with(g.HAND_KATANA_SHEATHED.orthonormalized(), progress)

func _end_sheath() -> void:
	g._sheath_clip = ""
	g._sheath_kind = ""
	if is_instance_valid(g.player) and "combat_clip" in g.player and str(g.player.combat_clip).begins_with("mixsword/"):
		g.player.combat_clip = ""

func _play_katana_clip(id := "katana") -> void:
	if not is_instance_valid(g.player): return
	var attacks: Array = g.SHIELD_ATTACKS if id == "sword_shield" else g.KATANA_ATTACKS
	g._shield_kicking = id == "sword_shield" and g.shield_block
	if g._shield_kicking: attacks = [g.SHIELD_KICK]
	else: g._katana_combo = (g._katana_combo + 1) % 3
	g._katana_attack_clock = g._combat_clock
	# Cicla mesmo com cliques deliberados: os cortes de volta têm trajetórias próprias
	# de mão/lâmina, em vez de inverter ou acelerar o mesmo clipe.
	g._cancel_combat_clip()
	g._clip_name = ""
	g._clip_start = 0.05
	g._clip_end = 1.25
	g._clip_rate = 1.7
	g._clip_age = 0.0
	g._clip_weapon = id
	var attack: Array = attacks[0] if g._shield_kicking else attacks[g._katana_combo % attacks.size()]
	if "animation" in g.player and g.player.animation != null and g.player.animation.has_animation(attack[0]):
		g._clip_name = attack[0]
		g._clip_start = float(attack[1])
		g._clip_end = float(attack[3])
		g._clip_rate = g.SHIELD_ATTACK_RATE if id == "sword_shield" else g.KATANA_ATTACK_RATE
	g._aim_hold = 0.8
	if not g._pending_swing.is_empty(): g._pending_swing.time = g._katana_contact_time() - 0.05

func request_rage() -> bool:
	# Teclado, controle e HUD compartilham as checagens de contexto e o retorno.
	if not is_instance_valid(g.rage) or not g.rage.unlocked() or not g.free_play_ok() or g.get_tree().paused: return false
	if g.rage.activate(): return true
	if g.rage.active: return true
	if g.equipped() != "katana":
		g.message.emit("Equipe a katana para ativar o RAGE.")
	elif g.rage.charge < RAGE.CAPACITY:
		g.message.emit(String(TranslationServer.translate("RAGE: %d%%. Receba dano de combate para carregar.")) % floori(g.rage.charge))
	else:
		g.message.emit("RAGE indisponível nesta situação.")
	return true

func _katana_contact_time() -> float:
	var shield: bool = g._clip_weapon == "sword_shield"
	if shield and g._clip_name == g.SHIELD_KICK[0]: return (float(g.SHIELD_KICK[2]) - float(g.SHIELD_KICK[1])) / g.SHIELD_ATTACK_RATE
	var attacks: Array = g.SHIELD_ATTACKS if shield else g.KATANA_ATTACKS
	var attack: Array = attacks[maxi(g._katana_combo, 0) % attacks.size()]
	if g._clip_name == attack[0]: return (float(attack[2]) - float(attack[1])) / (g.SHIELD_ATTACK_RATE if shield else g.KATANA_ATTACK_RATE)
	return preload("res://gameplay/KatanaMoveset.gd").CONTACT[maxi(g._katana_combo,0)]
