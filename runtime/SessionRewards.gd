extends RefCounted
## Recompensas espalhadas nos interiores (coleta por contato, aviso único de falha por aproximação).
## Separado em 31/10 para o FullSession.gd caber na leitura; `_reward_failures` e `_reward_notice_id`
## continuam na sessão e cada função antiga virou delegação de uma linha.
## `g` fica como Node, e não como o script da FullSession, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`, para subclasses de teste da sessão
## continuarem valendo.

const REWARD_AUDIO := preload("res://gameplay/RewardAudio.gd")
const WEAPONS := preload("res://gameplay/WeaponCatalog.gd")

var g: Node

func _init(host: Node) -> void:
	g = host

func _update_reward() -> void:
	if g.room == null or g.room == g.world.maciota_place: return
	for point in g.room.reward_points:
		var data: Dictionary = point.get("reward",{})
		if not data.is_empty(): g.room.set_reward_available(not g.state.world_state.rewards.has(data.id),data.id)

func _collect_reward(source: Node3D) -> void:
	if not is_instance_valid(source) or not source.is_visible_in_tree() or g.world.gameplay.health <= 0: return
	for reward in source.reward_points:
		var data: Dictionary = reward.get("reward",{})
		if data.is_empty(): continue
		if g.state.world_state.rewards.has(data.id):
			source.set_reward_available(false,data.id)
			continue
		var point: Vector3 = reward.get("position",Vector3.ZERO)
		if g.world.player.global_position.distance_to(point) > .8: continue
		if g._reward_failures.has(data.id): continue
		var result: Dictionary = g.state.economy.grant_world_reward(data)
		if not result.ok:
			var reason := str(result.get("reason","grant_failed"))
			var item_name := str(WEAPONS.WEAPONS.get(str(data.get("item", "")), {}).get("label", "Item")) if data.get("kind", "") == "weapon" else "Recompensa"
			var explanation: String = {"already_owned":"Você já possui esta arma.", "wallet_full":"Carteira cheia.", "inventory_full":"Inventário cheio.", "ammo_full":"Munição no limite.", "invalid_reward":"Não foi possível coletar este item: dados inválidos.", "transaction_conflict":"Coleta bloqueada por conflito no registro da recompensa."}.get(reason, "Não foi possível concluir a coleta.")
			g.show_message("%s: %s" % [item_name, explanation])
			g._reward_notice_id = str(data.id)
			g._reward_failures[data.id] = {"source":weakref(source), "position":point, "region":g.state.region_id, "place":g.state.place_id}
			continue
		if not g.state.world_state.rewards.has(data.id): g.state.world_state.rewards.append(data.id)
		if result.get("changed",true):
			REWARD_AUDIO.play(g,REWARD_AUDIO.kind_for_reward(str(data.get("kind",""))))
		source.set_reward_available(false,data.id,true)
		# Coleta sem aviso na tela (como os drops de combate); só a falha avisa.
		g.save_game()

func _refresh_reward_feedback() -> void:
	# Uma falha por aproximação; não renove o aviso a cada tick nem após sair.
	for id in g._reward_failures.keys():
		var failure: Dictionary = g._reward_failures[id]
		var source = failure.source.get_ref()
		if is_instance_valid(source) and source.is_visible_in_tree() and failure.region == g.state.region_id and failure.place == g.state.place_id and not g.world.driving.occupied and g.world.player.global_position.distance_to(failure.position) <= .8: continue
		g._reward_failures.erase(id)
		if g._reward_notice_id == id:
			g._reward_notice_id = ""
			g.notice_time = 0.0
			g.notice.text = ""
			g.notice.hide()
