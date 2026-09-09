extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

## AUDIT 11 — Revalidação da Ammu-Nation do Porto
## A auditoria original (ver AUDIT_REPORT.md, achado histórico) encontrou
## zero portas com role="ammunation" no distrito do Porto. Durante o
## aprofundamento seguinte, uma edição concorrente de outra sessão (não desta
## auditoria) adicionou uma porta real em District/NorthFrontage2/AmmunationEntrance.
## Esta tarefa pede uma revalidação explícita e isolada: confirmar se ela
## ainda existe no estado atual do mundo e testar sua interação real (entrada
## pela circulação real, sem bypass). Não cria nenhuma loja nova — se a porta
## não existir mais, este teste registra a divergência e para, sem inventar
## conteúdo.

func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_tag = "11_harbor_ammunation_revalidation"
	arm_watchdog(90.0)

	skip_onboarding_flags()
	isolate_saves(_tag)

	var world := await boot_harbor(30)
	var player: CharacterBody2D = world.get_node("Player")

	print("\n[ETAPA 1] Estado atual: a porta District/NorthFrontage2/AmmunationEntrance existe?")
	var entrance: Node = world.get_node_or_null("District/NorthFrontage2/AmmunationEntrance")
	if entrance == null:
		log_line("  [DIVERGÊNCIA] District/NorthFrontage2/AmmunationEntrance não existe mais no estado atual do mundo.")
		var any_found: Array = []
		for node in get_nodes_in_group("building_entrance"):
			if str(node.get("role")) == "ammunation":
				any_found.append(str(node.get_path()))
		if any_found.is_empty():
			log_line("  [DIVERGÊNCIA] Nenhuma porta com role='ammunation' existe em nenhum lugar do Porto agora — o achado original da auditoria (loja inacessível) voltou a ser o estado atual.")
		else:
			log_line("  [DIVERGÊNCIA] Não há porta no caminho esperado, mas existem outras com role='ammunation' em: %s — path pode ter mudado." % [any_found])
		check(false, "District/NorthFrontage2/AmmunationEntrance existe no estado atual (registrado como divergência acima; nenhuma loja nova foi criada por este teste)")
		await finish(_tag, world)
		return
	check(true, "District/NorthFrontage2/AmmunationEntrance existe no estado atual do mundo")

	var interiors: Node = world.get_node("Interiors")
	var interior: Node2D = interiors.get("ammunation_interior")
	check(interior != null and is_instance_valid(interior), "O interior real da Ammu-Nation do Porto existe e é válido")
	if interior == null:
		await finish(_tag, world)
		return

	print("\n[ETAPA 2] Entrada real: caminhar pela circulação até a porta (sem bypass)")
	var sensor: Area2D = entrance.get_node("InteractionArea")
	# Ao contrário da fachada da montanha (área aberta ao sul), este prédio do
	# Porto (District/NorthFrontage2) tem uma parede sólida a poucos passos ao
	# sul da porta — bloqueia fisicamente essa direção de aproximação
	# (confirmado: caminhar de lá para pouco antes de chegar). A calçada real
	# fica ao norte, de onde a aproximação chega sem obstáculo.
	var approach_start: Vector2 = sensor.global_position + Vector2(0, -60)
	player.global_position = approach_start
	player.velocity = Vector2.ZERO
	await physics_frames(5)

	var walked: bool = await walk_to(player, sensor.global_position, 300, 12.0)
	check(walked, "Jogador caminha de verdade até o sensor da porta real do Porto")
	await create_timer(0.4).timeout
	var sensor_detected: bool = entrance.is_actor_in_range(player)
	check(sensor_detected, "Sensor de proximidade real da porta do Porto detecta o jogador")
	if not sensor_detected:
		log_line("  [ACHADO] entrance InteractionArea: collision_layer=%d collision_mask=%d — player.collision_layer=%d. Sobreposição física real: %s" % [
			sensor.collision_layer, sensor.collision_mask, player.collision_layer, sensor.get_overlapping_bodies()
		])
		await finish(_tag, world)
		return

	await capture("11_harbor_ammunation_real_entry")
	var entered: bool = entrance.request_interaction(player)
	check(entered, "request_interaction() aceita a entrada real pela porta do Porto")
	if not entered:
		await finish(_tag, world)
		return

	var teleported: bool = await wait_until(
		func(): return player.global_position.distance_to(interior.global_position) < 900.0,
		5.0, "Jogador não foi teleportado para dentro do interior da Ammu-Nation do Porto"
	)
	check(teleported, "Jogador é teleportado para dentro do interior real da Ammu-Nation do Porto")

	print("\n[ETAPA 3] Compra real com o armeiro do Porto")
	# A HarborAmmunationInterior.gd atual (reescrita por outra sessão durante
	# esta auditoria — ver AUDIT_REPORT.md) usa um design diferente do da
	# montanha: sem Area2D de balcão nem NPC de diálogo separado — em vez
	# disso, um "merchant_point" local (raio de 70px) que abre um catálogo com
	# preview 3D giratório via a ação real "interact", navegado com
	# ui_left/ui_right e comprado com o botão real "COMPRAR" (Player.buy_weapon).
	if teleported and interior.has_method("open_catalog"):
		var merchant_global: Vector2 = interior.to_global(interior.merchant_point)
		var walked_to_merchant: bool = await walk_to(player, merchant_global, 300, 60.0)
		check(walked_to_merchant, "Jogador caminha até o armeiro real do Porto")
		await create_timer(0.4).timeout
		player.set("money", 5000)
		var money_before: int = int(player.get("money"))
		await press_key(KEY_E) # ação "interact" mapeada para E
		check(bool(interior.get("active")), "Ação real 'interact' abre o catálogo real do armeiro do Porto")
		if bool(interior.get("active")):
			await capture("11_harbor_ammunation_catalog_open")
			# Navega até encontrar uma arma comprável (sem trava de descoberta
			# nem já possuída), igual a um jogador usando ui_left/ui_right de verdade.
			var bought := false
			for _i in range(interior.stock.size()):
				if not interior.buy.disabled:
					var target_id: String = interior.stock[interior.selection]
					interior.buy.pressed.emit() # mesmo caminho de um clique real
					var inventory: Dictionary = player.get("weapon_inventory")
					bought = bool(inventory.get(target_id, false))
					if bought:
						check(int(player.get("money")) < money_before, "Compra real com o armeiro do Porto debita dinheiro (%s)" % target_id)
					break
				await press_key(KEY_RIGHT) # ui_right real: navega para a próxima arma do catálogo
			check(bought, "Ao menos uma arma do catálogo real do Porto pôde ser comprada pelo botão real")
			await press_key(KEY_ESCAPE)
			check(not bool(interior.get("active")), "ESC fecha o catálogo real do Porto")

	print("\n[ETAPA 4] Saída real pela porta do interior do Porto")
	var exit_door: Node = interior.get("exit_door")
	if exit_door != null:
		var exit_sensor: Area2D = exit_door.get_node("InteractionArea")
		var walked_to_exit: bool = await walk_to(player, exit_sensor.global_position, 300, 12.0)
		check(walked_to_exit, "Jogador caminha até a porta de saída real do Porto")
		await create_timer(0.4).timeout
		var exited: bool = exit_door.request_interaction(player)
		check(exited, "request_interaction() aceita a saída real pela porta do Porto")
		var left: bool = await wait_until(
			func(): return player.global_position.distance_to(interior.global_position) > 900.0,
			5.0, "Jogador não retornou fisicamente para fora da loja do Porto"
		)
		check(left, "Jogador retorna fisicamente para fora da Ammu-Nation do Porto")
		if left:
			await capture("11_harbor_ammunation_real_exit")

	await finish(_tag, world)
