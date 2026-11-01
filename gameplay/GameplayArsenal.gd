extends RefCounted
## Arsenal do Gameplay (forja, acessórios, lanterna, recarga, troca de arma) e as trapaças digitadas
## (dukenuke, godmode, grana), separados em 01/11 (Onda 2 de docs/plano-divisao-arquivos-grandes-20261101.md)
## para o Gameplay.gd caber na leitura. O estado (customization, reload_timer, _cheat_buffer, god_mode,
## _god_marked...) e os sinais continuam no Gameplay, onde testes, HUD e save os leem; cada função antiga
## virou delegação de uma linha com a mesma assinatura, então quem chama por nome (call/has_method) não muda.
## `g` fica como Node3D, e não como o script do Gameplay, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: testes sobrescrevem attack_allowed,
## equipped e _play_reload_audio numa subclasse do Gameplay e o despacho tem de continuar igual.

const AUDIO := preload("res://gameplay/CombatAudio.gd")
const CATALOG := preload("res://gameplay/WeaponCatalog.gd")
const CUSTOM := preload("res://gameplay/WeaponCustomization.gd")
const FORGE := preload("res://gameplay/forge/BladeForge.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

## Forja da Serra: cobra o próximo nível (ou a lendária), grava na entrada da arma e
## remonta a lâmina. O efeito no combate sai de `weapon_data` (WeaponCustomization).
func buy_forge_upgrade(id: String, track: String, quest_stage: String) -> Dictionary:
	if g.state == null or not g.state.owns_weapon(id): return {"ok":false, "reason":"Você não tem essa arma."}
	var offer: Dictionary = FORGE.offer(g.customization, quest_stage, id, track)
	if not offer.ok: return offer
	if not g.state.spend(int(offer.price), str(offer.receipt)): return {"ok":false, "reason":"Saldo insuficiente."}
	FORGE.install(g.customization, id, track)
	g.refresh_blade_visuals()
	g.changed.emit()
	return offer

func buy_attachment(id: String, part: String) -> bool:
	if not g.state.owns_weapon(id) or not CUSTOM.supports(id, part): return false
	if CUSTOM.owns(g.customization, id, part): return g.install_attachment(id, part)
	if not g.state.spend(int(CUSTOM.PARTS[part].price), "weapon_part:" + id + ":" + part): return false
	var entry: Dictionary = g.customization.get(id, {"owned":false, "installed":false, "owned_parts":[], "parts":{}})
	if part == "flashlight":
		entry.owned = true
		entry.installed = true
	else:
		entry.owned_parts.append(part)
		entry.parts[CUSTOM.PARTS[part].slot] = part
	g.customization[id] = entry
	g.visual_id = "@rebuild"
	g.changed.emit()
	return true

func install_attachment(id: String, part: String, installed: bool = true) -> bool:
	if not CUSTOM.supports(id, part) or not CUSTOM.owns(g.customization, id, part): return false
	if part == "flashlight": g.customization[id].installed = installed
	elif installed: g.customization[id].parts[CUSTOM.PARTS[part].slot] = part
	else: g.customization[id].parts.erase(CUSTOM.PARTS[part].slot)
	g.visual_id = "@rebuild"
	g.changed.emit()
	return true

func toggle_flashlight() -> bool:
	if not g.attack_allowed() or not CUSTOM.installed(g.customization, g.equipped()): return false
	g.flashlight_enabled = not g.flashlight_enabled
	return true

func toggle_personal_lights() -> bool:
	# Um comando remapeável para todo equipamento utilizável. Se algum estiver ligado, desliga
	# os dois; senão liga os dois. Uma arma indisponível mantém o estado.
	var belt_available: bool = is_instance_valid(g.belt_flashlight) and g.belt_flashlight.owned
	var weapon_available: bool = g.attack_allowed() and CUSTOM.installed(g.customization, g.equipped())
	if not belt_available and not weapon_available: return false
	var enable: bool = not ((belt_available and g.belt_flashlight.enabled) or (weapon_available and g.flashlight_enabled))
	if belt_available:
		g.belt_flashlight.enabled = enable
		g.belt_flashlight.update_visibility()
	if weapon_available: g.flashlight_enabled = enable
	return true

func reload_weapon() -> bool:
	if not g.attack_allowed() or g.reload_timer > 0: return false
	var id: String = g.equipped()
	if not CATALOG.WEAPONS.has(id): return false
	var data: Dictionary = g.weapon_data(id)
	if int(data.magazine_size) < 1: return false
	var ammo: Dictionary = g.state.get_ammo(id)
	if int(ammo.get("reserve", 0)) < 1 or int(ammo.get("magazine", 0)) >= int(data.magazine_size): return false
	# Authored weapon timing owns gameplay. Legacy weapons without a duration
	# retain the V1 bank duration; replacing audio cannot change variant balance.
	var bank_seconds: float = AUDIO.reload_seconds(id)
	g.reload_timer = float(data.get("reload_duration", bank_seconds if bank_seconds > 0.0 else (1.35 if id not in ["rpg", "shotgun", "hunting_rifle"] else 2.2)))
	g.reload_timer *= float(data.get("reload_multiplier", 1.0))
	g._reload_total = g.reload_timer
	g.reloading_id = id
	g._play_reload_audio(id, float(data.get("reload_multiplier", 1.0)))
	var reload_spec: Dictionary = g.GUN_CLIPS.get(id, {})
	if not reload_spec.is_empty() and is_instance_valid(g.player) and "animation" in g.player and g.player.animation != null and g.player.animation.has_animation(reload_spec.reload):
		g._play_gun_clip(id, "reload", g.player.animation.get_animation(reload_spec.reload).length / maxf(g._reload_total, 0.1))
	return true

func cycle_weapon(step: int) -> bool:
	if not g.attack_allowed(): return false
	var order: Array = CATALOG.ORDER
	var index := order.find(g.equipped())
	for offset in range(1, order.size() + 1):
		var id: String = order[posmod(index + offset * step, order.size())]
		if id == "fists" or g.state.owns_weapon(id):
			if g.state.equip_weapon(id):
				g.reload_timer = 0
				g._reload_audio.stop()
				g.changed.emit()
				return true
	return false

## Tecla 1–0 do V1 (`SLOT_ORDER`). Passa por `state.equip_weapon`, que já recusa arma não
## carregada (arsenal da Monaliza), esquiando e a garagem.
func equip_slot(id: String) -> bool:
	if not g.attack_allowed() or not g.state.owns_weapon(id): return false
	if not g.state.equip_weapon(id): return false
	g.reload_timer = 0
	g._reload_audio.stop()
	g.changed.emit()
	return true

## Cheat de arsenal do V1: `Player._handle_cheat_key`. Mesmas guardas (pausa, campo de texto, remapeamento,
## modificadores, ataque bloqueado). FullSession encaminha antes dos atalhos de interação.
## Prefixos reconhecidos são consumidos para que E não abra diálogos durante a sequência.
func handle_arsenal_input(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo: return false
	var focus: Control = g.get_viewport().gui_get_focus_owner()
	if not g.attack_allowed() or not g.free_play_ok() or focus is LineEdit or focus is TextEdit or key.ctrl_pressed or key.alt_pressed or key.meta_pressed:
		g._cheat_buffer = ""
		return false
	if g._combat_clock - g._cheat_last > g.CHEAT_GAP: g._cheat_buffer = ""
	g._cheat_last = g._combat_clock
	var code: int = key.unicode if key.unicode != 0 else key.keycode
	if code == 0: code = key.physical_keycode
	if not ((code >= 65 and code <= 90) or (code >= 97 and code <= 122)):
		g._cheat_buffer = ""
		return false
	g._cheat_buffer = (g._cheat_buffer + String.chr(code).to_lower()).right(g.CHEAT_BUFFER)
	if g._cheat_buffer.ends_with(g.CHEAT_ARSENAL):
		g._cheat_buffer = ""
		return g.activate_arsenal_cheat()
	if g._cheat_buffer.ends_with(g.CHEAT_GODMODE):
		g._cheat_buffer = ""
		return g.toggle_god_mode()
	if g._cheat_buffer.ends_with(g.CHEAT_MONEY):
		g._cheat_buffer = ""
		return g.toggle_infinite_money()
	for length in range(1,g.CHEAT_ARSENAL.length()):
		if g._cheat_buffer.ends_with(g.CHEAT_ARSENAL.left(length)): return true
	for length in range(1,g.CHEAT_GODMODE.length()):
		if g._cheat_buffer.ends_with(g.CHEAT_GODMODE.left(length)): return true
	for length in range(1,g.CHEAT_MONEY.length()):
		if g._cheat_buffer.ends_with(g.CHEAT_MONEY.left(length)): return true
	return false

func toggle_infinite_money() -> bool:
	if g.state == null or not "economy" in g.state: return false
	g.state.economy.cheat_infinite_money = not g.state.economy.cheat_infinite_money
	g.changed.emit()
	g.message.emit("Dinheiro infinito ligado" if g.state.economy.cheat_infinite_money else "Dinheiro infinito desligado")
	return true

## Liga/desliga a invencibilidade. Protege o jogador e o carro que ele dirige pela mesma marca
## `invulnerable` que Maciota usa, então tiro, explosão, atropelamento e batida passam sem ferir.
func toggle_god_mode() -> bool:
	if g.state == null: return false
	g.god_mode = not g.god_mode
	g.sync_god_mode()
	g.changed.emit()
	g.message.emit("Invencibilidade ligada" if g.god_mode else "Invencibilidade desligada")
	return true

## Mantém a marca no jogador e no veículo atual (que muda ao entrar/sair de um carro).
func sync_god_mode() -> void:
	var wanted: Array[Node] = []
	if g.god_mode:
		if is_instance_valid(g.player): wanted.append(g.player)
		var target: Node3D = g.pursuit_target()
		if is_instance_valid(target) and target != g.player: wanted.append(target)
	for node in g._god_marked.duplicate():
		if not is_instance_valid(node):
			g._god_marked.erase(node)
		elif not wanted.has(node):
			node.remove_meta(PROTECTION.META)
			g._god_marked.erase(node)
	for node in wanted:
		if g._god_marked.has(node) or node.get_meta(PROTECTION.META, false) == true: continue
		node.set_meta(PROTECTION.META, true)
		g._god_marked.append(node)

## Ativa o arsenal temporário do Economy, sem gravar armas/munição no save.
## Bloqueado onde atacar é bloqueado (garagem).
func activate_arsenal_cheat() -> bool:
	if not g.attack_allowed() or g.state == null or not "economy" in g.state: return false
	g.reload_timer = 0.0
	g.reloading_id = ""
	g._reload_audio.stop()
	g.state.economy.activate_arsenal_cheat()
	g.changed.emit()
	g.message.emit("Cheat ativado")
	return true
