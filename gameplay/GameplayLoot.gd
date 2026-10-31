extends RefCounted
## Itens no chão do Gameplay (arma e colete de policial, dinheiro de civil, coleta por contato), separados
## em 31/10 para o Gameplay.gd caber na leitura. A lista `_loot` e os RNGs continuam no Gameplay (testes
## leem `_loot` lá); as funções antigas do Gameplay viraram delegações de uma linha.
## `g` fica como Node3D, e não como o script do Gameplay, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: testes sobrescrevem algumas delas numa
## subclasse do Gameplay (_play_stream, _kick_camera, _hit_effect...) e o despacho tem de continuar igual.

const AUDIO = preload("res://gameplay/CombatAudio.gd")
const CASH_DROP_RULES = preload("res://gameplay/CashDropRules.gd")
const CATALOG = preload("res://gameplay/WeaponCatalog.gd")
const LOOT = preload("res://gameplay/LootPickup.gd")
const PROTECTION = preload("res://gameplay/DamageProtection.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

## Chamado na morte de policial/gangue. Rolagem única por corpo, como
## `PoliceLoot.drop_now`: a arma dele (com munição) e/ou um colete, espalhados
## em volta do corpo (V1: ±12 px e ±16 px = 0,75 m e 1 m).
func drop_ammo(point: Vector3, id: String) -> void:
	# O patamar pesado é o que carrega M4A1 (`PoliceAgent.TIER_WEAPONS`, tier >= 2).
	var heavy := id == "m4a1"
	if CATALOG.WEAPONS.has(id) and g._rng.randf() <= (g.LOOT_WEAPON_CHANCE_HEAVY if heavy else g.LOOT_WEAPON_CHANCE):
		g.spawn_loot("weapon", id, g._rng.randi_range(g.LOOT_AMMO.x, g.LOOT_AMMO.y), point + Vector3(g._rng.randf_range(-0.75, 0.75), 0, g._rng.randf_range(-0.75, 0.75)))
	if g._rng.randf() <= (g.LOOT_ARMOR_CHANCE_HEAVY if heavy else g.LOOT_ARMOR_CHANCE):
		g.spawn_loot("armor", "", g.LOOT_ARMOR_POINTS, point + Vector3(g._rng.randf_range(-1.0, 1.0), 0, g._rng.randf_range(-1.0, 1.0)))

## Morte de policial/gangue com a arma na mão (15/10): a arma que cai é sempre o item de verdade, como no
## GTA. Antes a arma da mão ficava deitada no chão como enfeite (modelo simplificado de NPC, sem coleta) e o
## item só saía no sorteio de drop_ammo: o jogador via uma arma que não pegava. O colete continua sorteado.
func drop_dead_weapon(actor: Node3D, id: String) -> void:
	if not is_instance_valid(actor) or actor.get_meta("dead_weapon_looted", false): return
	var visual: Variant = actor.get("visual")
	var gun: Variant = visual.get("weapon") if visual is Node else null
	var point: Vector3 = actor.global_position
	if gun is Node3D and is_instance_valid(gun):
		point = Vector3(gun.global_position.x, actor.global_position.y, gun.global_position.z)
		gun.visible = false
	actor.set_meta("dead_weapon_looted", true)
	if CATALOG.WEAPONS.has(id):
		g.spawn_loot("weapon", id, g._rng.randi_range(g.LOOT_AMMO.x, g.LOOT_AMMO.y), point)
	var heavy := id == "m4a1"
	if g._rng.randf() <= (g.LOOT_ARMOR_CHANCE_HEAVY if heavy else g.LOOT_ARMOR_CHANCE):
		g.spawn_loot("armor", "", g.LOOT_ARMOR_POINTS, point + Vector3(g._rng.randf_range(-1.0, 1.0), 0, g._rng.randf_range(-1.0, 1.0)))

## Mortes de civis sorteiam independentemente do assassino, do crime e da resposta de emergência.
func drop_cash(actor: Node3D) -> void:
	if not is_instance_valid(actor) or actor == g.player or actor.get("dead") != true or PROTECTION.is_protected(actor): return
	if actor.get_meta("cash_drop_rolled", false): return
	# Marca até um sorteio vazio: dano num cadáver nunca pode sortear os bolsos de novo.
	actor.set_meta("cash_drop_rolled", true)
	var amount := CASH_DROP_RULES.roll(g._cash_rng)
	if amount == 0: return
	var cash: Array[Node3D] = []
	for pickup in g._loot:
		if is_instance_valid(pickup) and not pickup.consumed and pickup.kind == "cash": cash.append(pickup)
	if cash.size() >= g.MAX_CASH_DROPS:
		g._loot.erase(cash[0])
		cash[0].queue_free()
	g.spawn_loot("cash", "", amount, actor.global_position + Vector3(.65, .02, 0))

func spawn_loot(kind: String, id: String, amount: int, point: Vector3) -> Node3D:
	var pickup := LOOT.new()
	pickup.setup(kind, id, amount)
	g.add_child(pickup)
	pickup.global_position = point
	g._loot.append(pickup)
	return pickup

## Coleta por contato, sem mensagem na tela (a V1 mostrava "PEGOU ..."; aqui só
## o som e o HUD de munição/colete mudam). Item que não cabe (colete cheio,
## reserva no limite) fica no chão para depois.
func _update_loot(delta: float) -> void:
	for index in range(g._loot.size() - 1, -1, -1):
		var pickup: Node3D = g._loot[index]
		if not is_instance_valid(pickup) or pickup.consumed:
			g._loot.remove_at(index)
			continue
		if not pickup.advance(delta):
			pickup.queue_free()
			g._loot.remove_at(index)
			continue
		if not g.attack_allowed() or not is_instance_valid(g.player) or not pickup.can_collect(g.player.global_position): continue
		if not g._grant_loot(pickup):
			g._loot_refused(pickup)
			continue
		pickup.collect()
		g._loot.remove_at(index)
		g.changed.emit()

## Arma ou munição que não cabe ficava no chão em silêncio e parecia que não dava para pegar.
## Avisa uma vez por item, ao pisar nele.
func _loot_refused(pickup: Node3D) -> void:
	if pickup.kind == "cash" or pickup.has_meta("refusal_noticed"): return
	pickup.set_meta("refusal_noticed", true)
	var active_session: Variant = g.world.get("session") if is_instance_valid(g.world) else null
	if active_session == null or not active_session.has_method("show_message"): return
	if pickup.kind == "armor":
		active_session.show_message("Colete já está cheio.")
		return
	var id := String(pickup.weapon_id)
	var label := String(CATALOG.WEAPONS.get(id, {}).get("short_label", id)).capitalize()
	if g.state.owns_weapon(id): active_session.show_message("Sem espaço para munição de %s. Abra a mochila (Tab) e libere espaço." % label)
	else: active_session.show_message("Sem espaço na mochila para %s. Abra a mochila (Tab) e libere espaço." % label)

func _grant_loot(pickup: Node3D) -> bool:
	if pickup.consumed: return false
	if pickup.kind == "cash":
		if pickup.consumed or pickup.cash_credited or g.state == null or g.state.get("economy") == null: return false
		if not g.state.economy.collect_loose_cash(int(pickup.cash_amount)): return false
		pickup.cash_credited = true
		g._play_ui(AUDIO.reward("pickup", g._rng), -3.0)
		return true
	if pickup.kind == "armor":
		if g.armor >= 100.0: return false
		g.armor = minf(100.0, g.armor + float(pickup.armor_amount))
		g._play_ui(AUDIO.reward("pickup", g._rng), -3.0)
		return true
	var id := String(pickup.weapon_id)
	var previously_owned: bool = g.state.owns_weapon(id)
	var gained: bool = g.state.economy.collect_weapon_drop(id, int(pickup.ammo_amount))
	# Arma nova vai para a mão quando houver slot disponível; a roda pode trocar
	# depois pela variante guardada na mochila, sem retirar a arma já carregada.
	if gained and not previously_owned and g.state.has_method("equip_weapon"): g.state.equip_weapon(id)
	if gained: g._play_ui(AUDIO.reward("weapon", g._rng), -3.0)
	return gained

func clear_loot() -> void:
	for pickup in g._loot:
		if is_instance_valid(pickup): pickup.queue_free()
	g._loot.clear()
