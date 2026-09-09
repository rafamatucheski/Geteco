extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

## AUDIT 06 — Compra e seleção de armas
## Part A is a structural, world-level check: does any reachable Ammu-Nation
## entrance exist in the live Harbor district right now? (ver AUDIT_REPORT.md,
## histórico do achado: na primeira passada desta auditoria, a resposta era
## não — HarborInteriorManager._bind_exterior_entrances() só amarrava Garagem/
## Polícia/Clínica/Oficina/Bombeiros. Uma edição concorrente e externa a esta
## sessão adicionou uma entrada real em District/NorthFrontage2/AmmunationEntrance
## durante esta própria auditoria; a checagem abaixo reflete o estado atual do
## mundo, não um resultado fixo, e deve ser reexecutada para confirmar em caso
## de dúvida.) Part B exercita a API real de compra/seleção em Player.gd
## (buy_weapon, equip_weapon, buy_ammo_amount, buy_armor_amount, seleção por
## tecla numérica), que funciona de forma independente do resultado da Part A.

func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_tag = "06_weapons_purchase_and_selection"
	arm_watchdog(90.0)

	skip_onboarding_flags()
	isolate_saves(_tag)

	var world := await boot_harbor(30)
	var player: Node = world.get_node("Player")

	print("\n[ETAPA 1] Existe alguma entrada de Ammu-Nation alcançável no distrito do Porto?")
	var ammunation_entrances := 0
	for e in get_nodes_in_group("building_entrance"):
		if str(e.get("role")) == "ammunation":
			ammunation_entrances += 1
			log_line("  [ACHADO] Entrada de Ammu-Nation em %s, conexões do sinal destination_requested=%d" % [e.get_path(), e.destination_requested.get_connections().size()])
	check(ammunation_entrances > 0, "Existe pelo menos uma entrada com role='ammunation' na árvore do Porto agora (estado dinâmico — ver nota no topo do arquivo e AUDIT_REPORT.md)")
	var interiors: Node = world.get_node("Interiors")
	check(is_instance_valid(interiors.get("ammunation_interior")), "O interior da Ammu-Nation existe e é válido")

	print("\n[ETAPA 2] Compra real de arma (produção: Player.buy_weapon) — escopeta, sem trava de descoberta")
	player.set("money", 5000)
	var initial_money: int = int(player.get("money"))
	var buy_msg: String = player.call("buy_weapon", "shotgun")
	check(buy_msg == "COMPRA REALIZADA", "buy_weapon('shotgun') retorna a mensagem real de sucesso ('%s')" % buy_msg)
	check(int(player.get("money")) == initial_money - 1800, "O preço da escopeta ($1800) é debitado corretamente")
	var inventory: Dictionary = player.get("weapon_inventory")
	check(bool(inventory.get("shotgun", false)), "shotgun passa a constar no inventário real do jogador")

	print("\n[ETAPA 3] Repetição: comprar a mesma arma de novo deve recusar sem debitar de novo")
	var money_after_first_buy: int = int(player.get("money"))
	var repeat_buy_msg: String = player.call("buy_weapon", "shotgun")
	check(repeat_buy_msg != "COMPRA REALIZADA", "Segunda compra da mesma arma não retorna sucesso")
	check(int(player.get("money")) == money_after_first_buy, "Segunda tentativa de compra não debita dinheiro de novo")
	log_line("  [ACHADO] Mensagem de 'arma já possuída' retornada pela produção: '%s' (bytes corrompidos de UTF-8 duplamente codificado, visíveis ao jogador na loja)" % repeat_buy_msg)

	print("\n[ETAPA 4] Falha esperada: dinheiro insuficiente")
	player.set("money", 10)
	var poor_msg: String = player.call("buy_weapon", "ak47")
	check(poor_msg == "DINHEIRO INSUFICIENTE", "Sem dinheiro suficiente, buy_weapon recusa com a mensagem correta")
	var ak_inventory: Dictionary = player.get("weapon_inventory")
	check(not bool(ak_inventory.get("ak47", false)), "A arma não é adicionada ao inventário quando a compra falha")
	player.set("money", 5000)

	print("\n[ETAPA 5] Descoberta de mundo trava a compra da SMG até o item ser encontrado")
	var smg_before: String = player.call("buy_weapon", "smg")
	check(smg_before != "COMPRA REALIZADA", "Sem ter encontrado a SMG no mundo, a compra é recusada mesmo com dinheiro")
	check(smg_before == "Encontre a SMG dentro do avião no lago.", "A recusa mostra a dica real de descoberta da SMG")
	var pickups: Array = player.get("world_pickups_collected")
	pickups.append("mountain_cargo_plane_smg_01")
	player.set("world_pickups_collected", pickups)
	var smg_after: String = player.call("buy_weapon", "smg")
	check(smg_after == "COMPRA REALIZADA", "Após a descoberta real (world_pickups_collected), a compra da SMG passa a funcionar")

	print("\n[ETAPA 6] Compra de munição e colete, repetidas 2x")
	for cycle in range(2):
		var ammo_msg: String = player.call("buy_ammo_amount", "shotgun", 12, 120)
		check(ammo_msg == "MUNIÇÃO COMPRADA", "Ciclo %d: compra de munição real funciona" % cycle)
		var armor_msg: String = player.call("buy_armor_amount", 50, 250)
		check(armor_msg == "COLETE EQUIPADO", "Ciclo %d: compra de colete real funciona" % cycle)
	player.set("armor", int(player.get("max_armor")))
	var maxed_armor_msg: String = player.call("buy_armor_amount", 50, 250)
	check(maxed_armor_msg != "COLETE EQUIPADO", "Colete no máximo recusa nova compra")
	log_line("  [ACHADO] Mensagem de 'colete no máximo' retornada pela produção: '%s' (mesmo problema de codificação)" % maxed_armor_msg)

	print("\n[ETAPA 7] Seleção real de arma com tecla numérica (produção: Player._input)")
	player.call("equip_weapon", "pistol")
	check(str(player.get("active_weapon_id")) == "pistol", "equip_weapon('pistol') muda a arma ativa")
	player.set("is_control_disabled", false)
	player.set("is_in_dialogue", false)
	await press_key(KEY_4) # mapeado para "shotgun" em Player._input
	check(str(player.get("active_weapon_id")) == "shotgun", "Tecla 4 seleciona a escopeta comprada, exatamente como no jogo real")
	await press_key(KEY_1) # mapeado para "pistol", sempre possuída
	check(str(player.get("active_weapon_id")) == "pistol", "Tecla 1 volta para a pistola (repetição de seleção funciona)")
	await press_key(KEY_3) # mapeado para "smg", agora possuída após a descoberta simulada
	check(str(player.get("active_weapon_id")) == "smg", "Tecla 3 seleciona a SMG liberada pela descoberta, repetindo a seleção com sucesso")

	await finish(_tag, world)
