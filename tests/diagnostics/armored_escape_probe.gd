extends "res://tests/test_armored_combat_session.gd"
## DIAGNÓSTICO DIRIGIDO NO MAIN — o cenário do corredor passou 20/20 em 2026-10-07.
## Escopo: roubo diurno no carregamento do Cobre, armor100 inicial, corrida normal a pé,
## perseguição policial real e decaimento normal de procurado; recibo de R$40000 pago uma vez só.
## Evidência: evidence/armored-escape-cobre-corridor.log e
## evidence/armored-escape-cobre-33400-5731331/escape-wallet.json.
## Continua um diagnóstico dirigido, fora da suíte automatizada de rotina.
## A primeira rota ficava visível para a polícia; a extensão anterior em x=-210
## foi rejeitada pela pré-checagem em z=-1024. O home_03 do DesertLayout cobre x[-220,-206],
## z[-1035.5,-1024.5], o que explica essa obstrução por geometria autoral.
## O corredor revisto x=-228 passou na pré-checagem completa de geometria/props e em 282.4 m de
## movimento real no Main. As duas rodadas anteriores que falharam continuam como evidência histórica;
## esta rota aprovada não certifica rotas de fuga arbitrárias nem todos os níveis.
## O diagnóstico guarda a identidade do colisor e a célula residente de qualquer obstrução nova.
## Usa interação de serviço, corrida normal e resposta policial. Só o posicionamento
## inicial do jogador usa teleporte; nenhum timer de procurado/contato é editado.

func _walk_toward(point: Vector3) -> void:
	var controls := root.get_node("GameInput")
	var direction: Vector3 = point - world.player.global_position
	direction.y = 0
	if direction.length() < .7:
		controls.touch_move = Vector2.ZERO
		return
	var right: Vector3 = world.camera.global_basis.x
	var back: Vector3 = world.camera.global_basis.z
	right.y = 0
	back.y = 0
	direction = direction.normalized()
	controls.touch_move = Vector2(direction.dot(right.normalized()), direction.dot(back.normalized()))
	controls.touch_sprint = true

func _stop_input() -> void:
	var controls := root.get_node("GameInput")
	controls.touch_move = Vector2.ZERO
	controls.touch_sprint = false

func _collision_identity(hit: Dictionary) -> Dictionary:
	var result := {"shape_index":int(hit.get("shape", -1))}
	var collider: Variant = hit.get("collider")
	if not is_instance_valid(collider): return result
	result["class"] = collider.get_class()
	if collider is Node:
		result["name"] = str(collider.name)
		result["path"] = str(collider.get_path())
		var script: Script = collider.get_script()
		result["script"] = script.resource_path if script != null else ""
	if collider is CollisionObject3D and int(result.shape_index) >= 0:
		result["layer"] = collider.collision_layer
		result["mask"] = collider.collision_mask
		var owner_id: int = collider.shape_find_owner(int(result.shape_index))
		var owner: Object = collider.shape_owner_get_owner(owner_id)
		if owner is Node: result["shape_owner_path"] = str(owner.get_path())
		if owner is CollisionShape3D and owner.shape != null:
			result["shape_class"] = owner.shape.get_class()
			result["shape_resource"] = owner.shape.resource_path
			result["shape_transform"] = str(owner.global_transform)
			if owner.shape is BoxShape3D: result["box_size"] = str(owner.shape.size)
	return result

func _preflight_residency(point: Vector3) -> Dictionary:
	var region: Node = world.production.region
	var result := {"region_path":str(region.get_path()), "player":str(world.player.global_position), "sample":str(point)}
	if region.has_method("_cell"):
		var cell: Vector2i = region._cell(point)
		result["sample_cell"] = str(cell)
		result["focus_cell"] = str(region.current_cell)
		result["sample_cell_resident"] = region.chunks.has(cell)
	return result

func _escape_route_clear(route: Array[Vector3]) -> bool:
	# Uma pré-checagem longa vai além da janela de streaming 3x3 atual do jogador.
	# Usa o caminho normal de admissão da região e depois espera seus jobs autorais/de espalhamento;
	# consultar só o piso recém-admitido poderia aprovar falsamente prédios faltando.
	var region: Node = world.production.region
	var cells: Dictionary = {}
	var prior: Vector3 = world.player.global_position
	for target in route:
		var count := maxi(1, ceili(prior.distance_to(target) / 24.0))
		for index in range(count + 1):
			var sample := prior.lerp(target, float(index) / count)
			if not region.prepare_collision_at(sample): return false
			cells[region._cell(sample)] = true
		prior = target
	var deadline := Time.get_ticks_msec() + 15000
	while true:
		var pending := false
		for job in region.build_jobs:
			if cells.has(job.key): pending = true
		if not pending: break
		if Time.get_ticks_msec() >= deadline:
			print("ARMORED_ESCAPE_PREFLIGHT streaming_jobs_pending=", region.build_jobs)
			return false
		await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .32
	capsule.height = 1.7
	query.shape = capsule
	query.collision_mask = 1
	var previous: Vector3 = world.player.global_position
	for target in route:
		var steps := maxi(1, ceili(previous.distance_to(target) / 1.0))
		for sample in range(1, steps + 1):
			var point := previous.lerp(target, float(sample) / steps)
			var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2.0, point + Vector3.DOWN * 3.0, 1))
			if floor_hit.is_empty() or floor_hit.normal.y < .7:
				print("ARMORED_ESCAPE_PREFLIGHT ", JSON.stringify({"reason":"missing_support", "residency":_preflight_residency(point), "floor":_collision_identity(floor_hit)}))
				return false
			point.y = floor_hit.position.y + .08
			query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * .9)
			var hits := space.intersect_shape(query, 8)
			if not hits.is_empty():
				var identities: Array[Dictionary] = []
				for hit in hits: identities.append(_collision_identity(hit))
				print("ARMORED_ESCAPE_PREFLIGHT ", JSON.stringify({"reason":"static_overlap", "residency":_preflight_residency(point), "floor":_collision_identity(floor_hit), "colliders":identities}))
				return false
		previous = target
	for car in convoy.fleet:
		if car.global_position.distance_to(route.back()) <= 85.0: return false
	return true

func _verify_success_wallet(before: Dictionary, truck: int) -> void:
	var wallet = world.session.state.economy
	var after: Dictionary = wallet.snapshot()
	var receipt_id := "armored:%s:truck:%d" % [convoy.data.id, truck]
	var unrelated_income := 0
	var new_transactions: Dictionary = {}
	for key in after.transactions:
		if before.transactions.has(key): continue
		var receipt: Dictionary = after.transactions[key]
		new_transactions[key] = receipt
		if str(key).begins_with("reward:achievement:"):
			var achievement := str(key).trim_prefix("reward:achievement:")
			if ACHIEVEMENTS.CASH_REWARDS.has(achievement) and receipt.kind == "reward" and int(receipt.amount) == int(ACHIEVEMENTS.CASH_REWARDS[achievement]):
				unrelated_income += int(receipt.amount)
	check(wallet.has_reward_receipt(receipt_id) and convoy.data.secured[truck], "natural escape creates the collected truck's persistent reward receipt")
	check(not wallet.has_reward_receipt("armored:%s:truck:%d" % [convoy.data.id, 1 - truck]) and not convoy.data.secured[1 - truck], "the untouched second truck earns no reward")
	check(int(after.balance) - int(before.balance) == 40000 + unrelated_income, "successful robbery adds exactly R$40000 besides independently recorded achievements")
	FileAccess.open(folder.path_join("escape-wallet.json"), FileAccess.WRITE).store_string(JSON.stringify({"before":before, "after":after, "new_transactions":new_transactions, "achievement_income":unrelated_income, "convoy":convoy.data}, "\t"))

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	seed(7102026)
	origin = "desert_bank"
	folder = FIXTURE.output_dir("armored-escape-cobre")
	var bank: Vector3 = PLACES.get_definition(origin).entry_position
	var point := bank + Vector3(4, .08, 1)
	var snapshot := FIXTURE.full_snapshot(point, true)
	snapshot.campaign.aftermath = {"call_complete":true}
	snapshot.region_id = "desert"
	snapshot.world.pedestrian = {"region":"desert", "position":[point.x, point.y, point.z]}
	snapshot.world.moon_day = 3
	snapshot.world.time = 14.0 / 24.0
	var path := FIXTURE.write_fixture(folder, "checkpoint.json", snapshot)
	if not check(not path.is_empty(), "isolated scheduled Cobre checkpoint accepted"): finish(1); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	if not check(world.session != null and world.session.ready_for_play and not world.production.save_invalid, "Main restores the valid isolated checkpoint"): finish(1); return
	var session = world.session
	if session.modal: session.close_menu()
	check(world.production.store.path == path and world.production.no_save, "test keeps personal saves disabled")
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.production.region.set_focus(point)
	for frame in 3: await physics_frame
	if session.position_clear(point): world.player.teleport(point)
	world.dispatch.router.nearest_edge(world.player.global_position)
	check(world.dispatch.router._native != null and world.dispatch.enabled and world.gameplay.dispatch_owned, "native C# routing and normal police dispatch are active")
	convoy = session.armored_transport
	var rear_setup: Dictionary = {}
	deadline = Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if convoy.fleet.size() == 4 and convoy.guards.size() >= 6 and convoy.data.phase == "loading":
			rear_setup = _rear_setup()
			if not rear_setup.is_empty(): break
	if not check(not rear_setup.is_empty(), "real scheduled convoy presents a witnessed service vault"): _trace("admission-failed"); finish(1); return
	world.player.teleport(rear_setup.point)
	world.camera.initialized = false
	world.gameplay.armor = 100
	world.gameplay.npc_gunfire.connect(_npc_fire)
	world.gameplay.crime_reported.connect(_reported)
	world.gameplay.player_died.connect(func(): _death_observed = true)
	for frame in 3: await physics_frame
	# O banco autoral é x[-220,-200], z[-927,-913]. Os fundos dele abrigam a
	# retirada inicial, mas a Rua Digo em z=-980 pode pôr a polícia à vista de novo.
	# Continua além da Digo pelo vão entre as colunas de casas, não por dentro do
	# home_03. Em z=-1030 a casa da esquerda termina em x=-232.8 (com a espessura da parede),
	# o poste externo do quintal da casa da direita começa em x=-221.66. Em z=-1067 o corredor
	# comum mais estreito é x[-233.8,-223.66]. x=-228 passa livre dos dois, incluindo props.
	# Rochas/cactos espalhados de forma determinística ainda exigem a pré-checagem física real.
	var route: Array[Vector3] = [Vector3(-239, 0, -889), Vector3(-239, 0, -939), Vector3(-210, 0, -939), Vector3(-210, 0, -971), Vector3(-228, 0, -971), Vector3(-228, 0, -1105)]
	if not check(await _escape_route_clear(route), "escape route has real floor/static clearance and ends beyond all four vehicles"): finish(1); return
	var before: Dictionary = session.state.economy.snapshot()
	if not check(session.nearest().get("id", "") == "armored_transport" and await session.interact(), "ordinary E interaction steals from the real service vault"): finish(1); return
	check(convoy.data.pending == 40000 and session.state.economy.balance == int(before.balance), "cash is unsecured when escape starts")
	check(convoy.data.hostile and convoy.security_level == 1, "theft triggers the actual armed response and future escalation")
	await photo("escape-start")
	var next := 0
	var max_stars := 0
	var distance_walked := 0.0
	var previous: Vector3 = world.player.global_position
	var anchor: Vector3 = previous
	var progress_time := Time.get_ticks_msec()
	world.player.controlled_automatically = false
	deadline = Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and not _death_observed and convoy.data.pending > 0:
		await physics_frame
		_observe_police()
		max_stars = maxi(max_stars, world.gameplay.stars)
		var current: Vector3 = world.player.global_position
		distance_walked += previous.distance_to(current)
		previous = current
		if next < route.size():
			var offset: Vector3 = route[next] - current
			offset.y = 0
			if offset.length() < .8:
				next += 1
				progress_time = Time.get_ticks_msec()
				anchor = current
			elif current.distance_to(anchor) > 1.5:
				anchor = current
				progress_time = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - progress_time > 12000:
				check(false, "physical sprint route remains traversable")
				break
		if next < route.size(): _walk_toward(route[next])
		else: _stop_input()
		if Time.get_ticks_msec() - _last_trace > 5000:
			_last_trace = Time.get_ticks_msec()
			_trace("escape-leg-%d" % next)
			print("ARMORED_ESCAPE_CONTACT ", JSON.stringify({"contact_age":world.gameplay.contact_age, "hidden_time":world.gameplay.hidden_time, "walked":distance_walked, "escape_seconds":convoy.escape_seconds}))
	_stop_input()
	check(not _death_observed and world.gameplay.health > 0, "Dante survives the escape with finite normal starting armor")
	check(next == route.size() and distance_walked > 240, "ordinary sprint input moves Dante physically around the bank and beyond its approach roads")
	check(convoy.data.reported and _radio_reports == 1 and max_stars >= 2, "real alarm creates a wanted pursuit during escape")
	check(_police_observed and _police_motion > 1.0, "normal dispatcher spawns and physically moves police in pursuit")
	check(max_stars > 0 and world.gameplay.stars == 0, "wanted level naturally falls to zero after police lose contact")
	check(convoy.data.pending == 0 and convoy.data.secured[rear_setup.truck], "normal escape timer secures the collected money")
	if convoy.data.pending == 0 and not _death_observed:
		_verify_success_wallet(before, int(rear_setup.truck))
		var settled: Dictionary = session.state.economy.snapshot()
		for frame in 180: await physics_frame
		check(session.state.economy.snapshot() == settled and convoy.data.pending == 0, "continued live event ticks cannot duplicate the settled reward")
		check(session.save_block_reason().is_empty(), "successful escape releases the normal checkpoint restriction")
	_trace("escape-result")
	await photo("escape-result")
	finish(0 if failures.is_empty() else 1)

func finish(code: int) -> void:
	_stop_input()
	super.finish(code)
