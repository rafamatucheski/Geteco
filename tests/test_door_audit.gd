extends SceneTree
## Auditoria das portas (15/10/2026). O usuário jogando: "portas que não abrem, ou
## abrem e não te colocam dentro do prédio" e "no parque tem porta que nem abre".
## Para CADA entrada do jogo (porto, serra, deserto, parque e lugares especiais):
## nasce ~3 m à frente da porta, ANDA até ela (direção automática do Actor, a mesma
## que o controle usa; nada de teleporte para dentro) e confere
##   (a) a porta/vão abre quando o jogador chega,
##   (b) o jogador entra de verdade (session.state.place_id muda),
##   (c) consegue sair andando (ou pela ação de saída, onde o lugar é por interação).
## Entradas por interação (bueiro, escotilha de mina, poço) não têm folha: a coluna
## (a) fica "n/a" e a entrada é feita pela ação "Entrar" ao chegar, como o jogador faz.
##
## Uso (com tela, nunca --headless):
##   "$GODOT" --path . --script res://tests/test_door_audit.gd -- --no-save [--only=id,id] [--system=building|walkup|special|interact] [--region=harbor|mountain|desert]
## Saída: tabela PASS/FAIL no terminal, evidence/door-audit-20261015/door-audit.json e
## PNG das falhas na mesma pasta (fora do Git).
const CATALOG := preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const SEWERS := preload("res://world/places/sewers/SewerNetwork.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const HOMES := preload("res://data/catalogs/ResidenceCatalog.gd")
const FOLDER := "res://evidence/door-audit-20261015"
const APPROACH := 3.0

var world
var rows: Array[Dictionary] = []
var inventory: Array[Dictionary] = []
var only: PackedStringArray = []
var system_filter := ""
var region_filter := ""

func _initialize() -> void: run.call_deferred()

func run() -> void:
	create_timer(5400).timeout.connect(func(): push_error("DOOR_AUDIT tempo esgotado"); _finish(3))
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("DOOR_AUDIT exige --no-save para não tocar no save do usuário.")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=").split(",")
		if arg.begins_with("--system="): system_filter = arg.trim_prefix("--system=")
		if arg.begins_with("--region="): region_filter = arg.trim_prefix("--region=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	# Campanha completa (deserto liberado, casa do Takeshi aberta) num save isolado;
	# com --no-save nada é gravado de volta, nem nele nem no save pessoal.
	var start := Vector3(170.0, .08, 120.0)
	var snapshot := FIXTURE.full_snapshot(start, true)
	snapshot.campaign.aftermath = {"call_complete":true}
	var fixture_path := FOLDER.path_join("fixture-save.json")
	var file := FileAccess.open(fixture_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshot, "\t"))
	file.close()
	if STORE.read_valid(fixture_path).is_empty():
		push_error("DOOR_AUDIT fixture inválida")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("skip_dispatch", true)
	world.set_meta("menu_save_path", fixture_path)
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 240000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.production != null and world.production.ready_for_play and world.session != null and world.session.ready_for_play: break
	if not (world.session != null and world.session.ready_for_play):
		push_error("DOOR_AUDIT o jogo não ficou pronto")
		_finish(3)
		return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	world.driving.set_process_unhandled_input(false)
	inventory = _inventory()
	_print_inventory()
	# Casas trancadas (DoorLockpick, 29/10): a auditoria confere a geometria de abre/entra/sai,
	# então arromba tudo antes; o contrato da trava está em test_door_lockpick_rule.gd.
	var picked := {}
	for door in inventory:
		var id := str(door.get("id", "")) if door is Dictionary else ""
		if not id.is_empty() and preload("res://runtime/DoorLockpick.gd").requires_lockpick(id): picked[id] = true
	world.session.state.world_state["door_lockpicks"] = picked
	for region in ["harbor", "mountain", "desert"]:
		if not region_filter.is_empty() and region != region_filter: continue
		var pending := inventory.filter(func(e): return e.region == region and _selected(e))
		if pending.is_empty(): continue
		if not await _go_region(region):
			for e in pending: rows.append(_row(e, "não conseguiu viajar para a região " + region))
			continue
		for e in pending:
			if e.mode == "scripted":
				var skipped := _row(e, "entrada por roteiro de missão; sem porta no mundo")
				skipped.result = "SKIP"
				rows.append(skipped)
				continue
			rows.append(await _audit(e))
		_audit_painted_doors(region)
	_finish()

func _selected(e: Dictionary) -> bool:
	if not only.is_empty() and not (e.id in only or e.place_id in only): return false
	if not system_filter.is_empty() and e.mode != system_filter: return false
	return true

## ---------------------------------------------------------------- inventário
func _inventory() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var covered := {}
	for d in CATALOG.definitions():
		var basis := Basis(Vector3.UP, float(d.exterior_rotation))
		list.append({"id":d.id, "place_id":d.id, "region":d.region, "mode":"building", "system":"HarborBuildingRuntime (+ExteriorAccess/PaintedFacadeKit)",
			"name":str(d.get("original_name", d.source_id)), "source":str(d.source_id), "kind":str(d.building_kind),
			"door":d.exterior_position + basis * Vector3(d.entrance_local), "inward":basis * Vector3.FORWARD})
		covered[d.id] = true
	var walk = world.session.weapon_shop_entrance
	for id in walk.IDS:
		var d: Dictionary = walk._definition_for(id)
		if d.is_empty(): continue
		list.append({"id":id, "place_id":str(d.get("place_id", id)), "region":str(d.region), "mode":"walkup", "system":"WeaponShopEntrance (+WalkupFacadeDoor)",
			"name":str(d.get("original_name", id)), "source":str(d.get("source_id", "")), "kind":PLACES.walkup_family(id),
			"door":walk._door_position(id, d), "inward":walk._inward(id)})
		covered[str(d.get("place_id", id))] = true
	var special = world.session.special_place_entrance
	for id in ["santa_mare_hold", "mountain_mystery_cave", "desert_under_culvert"]:
		var d: Dictionary = special.definitions[id]
		list.append({"id":id, "place_id":id, "region":str(d.region), "mode":"special", "system":"SpecialPlaceEntrance",
			"name":str(d.original_name), "source":"", "kind":"culvert" if id == "desert_under_culvert" else id,
			"door":special._door(id), "inward":Vector3.FORWARD})
		covered[id] = true
	for d in PLACES.definitions():
		if covered.has(d.id): continue
		var scripted: bool = d.get("hidden_access", false)
		var system := "FullSession.nearest (ação Entrar)"
		if SEWERS.is_manhole(d.id): system = "FullSession.nearest + SewerHatchDescent (tampa)"
		if scripted: system = "roteiro de missão"
		list.append({"id":d.id, "place_id":d.id, "region":str(d.region), "mode":"scripted" if scripted else "interact", "system":system,
			"name":str(d.get("original_name", d.id)), "source":str(d.get("source_id", "")), "kind":str(d.get("service", "")),
			"door":Vector3(d.entry_position), "inward":Vector3.FORWARD})
	return list

func _print_inventory() -> void:
	var counts := {}
	for e in inventory:
		var key: String = e.region + " / " + e.system
		counts[key] = int(counts.get(key, 0)) + 1
	print("DOOR_INVENTORY total=", inventory.size())
	var keys := counts.keys()
	keys.sort()
	for key in keys: print("DOOR_INVENTORY ", key, ": ", counts[key])

## ---------------------------------------------------------------- região
func _go_region(region: String) -> bool:
	if world.session.state.region_id == region: return true
	var production = world.production
	if not production.travel(region): return false
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if not production.travel_busy and world.session.ready_for_play and world.session.state.region_id == region: break
	for frame in 60: await process_frame
	return world.session.state.region_id == region

func _settle_at(point: Vector3) -> void:
	var region = world.production.region
	region.set_focus(point, true)
	if region.has_method("prepare_collision_at"): region.prepare_collision_at(point)
	var deadline := Time.get_ticks_msec() + 20000
	var frames := 0
	while Time.get_ticks_msec() < deadline:
		await process_frame
		frames += 1
		if frames > 30 and region.is_streaming_idle(): break

## Chão sob o ponto: raio de cima; fica com o acerto mais perto da altura pedida.
func _ground(point: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var best := Vector3.INF
	var excluded: Array[RID] = []
	for layer in 6:
		var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, point.y + 40.0, point.z), Vector3(point.x, point.y - 60.0, point.z), 1)
		query.exclude = excluded
		var hit := space.intersect_ray(query)
		if hit.is_empty(): break
		excluded.append(hit.rid)
		# Ignora telhados/marquises: o chão da porta fica perto da altura da soleira.
		if hit.position.y > point.y + 2.5: continue
		if not best.is_finite() or absf(hit.position.y - point.y) < absf(best.y - point.y): best = hit.position
	return (best if best.is_finite() else point) + Vector3.UP * .08

## ---------------------------------------------------------------- uma entrada
func _row(e: Dictionary, note := "") -> Dictionary:
	return {"id":e.id, "place_id":e.place_id, "region":e.region, "system":e.system, "mode":e.mode, "name":e.name,
		"door":[snappedf(e.door.x, .01), snappedf(e.door.y, .01), snappedf(e.door.z, .01)],
		"door_kind":"", "opened":"n/a", "entered":false, "exited":false, "result":"FAIL", "notes":[] if note.is_empty() else [note], "photos":[]}

func _gates(e: Dictionary) -> Array:
	var session = world.session
	var notes := []
	# A auditoria passa pelo porto restrito e esbarra em gente: estrela de procurado
	# fecharia as lojas (ShopSafety) e contaminaria as entradas seguintes.
	if world.gameplay.stars > 0:
		notes.append("procurado (%d estrelas) zerado antes do teste" % world.gameplay.stars)
		world.gameplay.clear_wanted()
	if HOMES.PROPERTIES.has(e.place_id):
		session.activities.residence.data.active_home = e.place_id
	if e.place_id == "port_boss_garage":
		session.state.world_state.time = 2.0 / 24.0
		session.weather.time_of_day = 2.0 / 24.0
	if e.mode == "building" and CATALOG.find(e.place_id).get("port_building", false):
		session.urban_operations.security.restore_snapshot({"version":1, "authorized_entry":false, "authorized_visit":true, "exiting_port":false})
	return notes

func _audit(e: Dictionary) -> Dictionary:
	var r := _row(e)
	var session = world.session
	var player = world.player
	r.notes.append_array(_gates(e))
	var door: Vector3 = e.door
	var inward: Vector3 = e.inward
	await _settle_at(door)
	door = _ground(door) - Vector3.UP * .08
	var entered := false
	var probe_found := false
	var opened_max := 0.0
	# Caminho reto de 3 m; se um obstáculo (aquecedor, muro) barra antes da porta,
	# tenta de novo a 1,6 m, como o jogador que contorna e chega de perto.
	# Por último chega pelo lado, rente à fachada (portas atrás de muro/portão).
	for attempt in [[APPROACH, 0.0], [1.6, 0.0], [0.9, -3.0], [0.9, 3.0]]:
		var distance: float = attempt[0]
		var walked: Array = await _approach(e, r, door, inward, distance, attempt[1])
		entered = walked[0]
		probe_found = probe_found or walked[1]
		opened_max = maxf(opened_max, walked[2])
		if entered or session.state.place_id == e.place_id: break
		if _flat(player.global_position - door) < 1.0: break
		r.notes.append(("lado %+.0f " % attempt[1] if attempt[1] != 0.0 else "") + "a %.1f m: parou em %s (dist %.2f m)%s" % [distance, _v(player.global_position), _flat(player.global_position - door), (" bloqueado por " + _blocker()) if not _blocker().is_empty() else ""])
	player.automatic_direction = Vector3.ZERO
	if not entered:
		# Pode estar na transição (fade/zoom) ainda.
		var t := Time.get_ticks_msec() + 4000
		while Time.get_ticks_msec() < t and session.state.place_id != e.place_id: await physics_frame
		entered = session.state.place_id == e.place_id
	r.door_kind = _door_kind(e)
	if e.mode == "interact": r.opened = "n/a"
	elif not probe_found: r.opened = "n/a"
	else: r.opened = opened_max > .5
	r.entered = entered
	if not entered:
		r.notes.append("parou em %s (porta %s, dist %.2f m)" % [_v(player.global_position), _v(door), _flat(player.global_position - door)])
		var blocker := _blocker()
		if not blocker.is_empty(): r.notes.append("bloqueado por " + blocker)
		if e.mode == "building":
			var access = session.building_entrance.facade
			if is_instance_valid(access):
				for leaf in _walk_in_leaves(access.facade):
					if leaf._area != null: r.notes.append("zona da folha: sobrepostos=%d aberta=%.2f" % [leaf._area.get_overlapping_bodies().size(), leaf.open_amount])
		r.photos.append(await _photo(e.id + "-nao-entrou"))
	else:
		var settle := Time.get_ticks_msec() + 8000
		while Time.get_ticks_msec() < settle and (session.is_transition_blocked() or player.input_locked): await physics_frame
		for frame in 20: await physics_frame
		r.exited = await _exit(e, r)
		if not r.exited: r.photos.append(await _photo(e.id + "-nao-saiu"))
	var ok: bool = r.entered and r.exited and (typeof(r.opened) == TYPE_STRING or r.opened == true)
	if r.has("aligned") and r.aligned == false: ok = false
	if typeof(r.opened) == TYPE_BOOL and r.opened == false and r.entered and r.photos.is_empty():
		r.notes.append("entrou sem a porta abrir")
	r.result = "PASS" if ok else "FAIL"
	print("DOOR_AUDIT ", r.result, " ", e.id, " abriu=", r.opened, " entrou=", r.entered, " saiu=", r.exited, " ", r.notes)
	# Afasta da porta antes da próxima para nenhuma folha ficar aberta pelo jogador.
	if session.state.place_id.is_empty():
		player.automatic_direction = Vector3.ZERO
		player.teleport(_ground(door - inward * 6.0))
		for frame in 10: await physics_frame
	return r

## Nasce `distance` metros à frente da porta e anda até ela. Devolve [entrou, achou folha, abertura máxima].
func _approach(e: Dictionary, r: Dictionary, door: Vector3, inward: Vector3, distance: float, lateral := 0.0) -> Array:
	var session = world.session
	var player = world.player
	var across := Vector3(-inward.z, 0, inward.x)
	var start := _ground(door - inward * distance + across * lateral)
	player.teleport(start)
	player.automatic_direction = Vector3.ZERO
	await _settle_at(start)
	for frame in 20: await physics_frame
	if lateral != 0.0: await _walk_to(door - inward * distance, 5000)
	if e.mode == "building":
		var runtime = session.building_entrance
		var ready_end := Time.get_ticks_msec() + 15000
		while Time.get_ticks_msec() < ready_end and (not is_instance_valid(runtime.staged) or runtime.staged.definition.id != e.id or runtime.preparing): await physics_frame
		if not (is_instance_valid(runtime.staged) and runtime.staged.definition.id == e.id):
			r.notes.append("sala não ficou preparada a 3 m da porta")
	# Alinhamento: a folha visível (pintada) tem de estar na entrada de verdade.
	_check_alignment(e, r, door)
	var opened_max := 0.0
	var probe_found := false
	var entered := false
	var target: Vector3 = door + inward * 2.2
	var walk_end := Time.get_ticks_msec() + 14000
	var stuck_since := Time.get_ticks_msec()
	var last: Vector3 = player.global_position
	while Time.get_ticks_msec() < walk_end:
		if session.state.place_id == e.place_id:
			entered = true
			break
		if not player.input_locked:
			var to: Vector3 = target - player.global_position
			to.y = 0
			player.automatic_direction = to.normalized() if to.length() > .15 else inward
		var amount: Variant = _door_amount(e)
		if amount != null:
			probe_found = true
			opened_max = maxf(opened_max, float(amount))
		if player.global_position.distance_to(last) > .05:
			last = player.global_position
			stuck_since = Time.get_ticks_msec()
		# Entrada por interação: ao chegar no ponto, aperta "Entrar" como o jogador.
		if e.mode == "interact" and Time.get_ticks_msec() - stuck_since > 600 or (e.mode == "interact" and player.global_position.distance_to(door) < 1.2):
			var action: Dictionary = session.nearest()
			if action.get("id", "") == "enter":
				player.automatic_direction = Vector3.ZERO
				r.notes.append("entrou pela ação Entrar (%s)" % action.get("label", ""))
				await session.interact()
				var t := Time.get_ticks_msec() + 15000
				while Time.get_ticks_msec() < t and session.state.place_id != e.place_id: await physics_frame
				entered = session.state.place_id == e.place_id
				if not entered and is_instance_valid(session.notice) and not session.notice.text.is_empty(): r.notes.append("aviso: " + session.notice.text)
				break
		if Time.get_ticks_msec() - stuck_since > 2500 and not player.input_locked and not session.is_transition_blocked():
			break
		await physics_frame
	player.automatic_direction = Vector3.ZERO
	return [entered, probe_found, opened_max]

func _exit(e: Dictionary, r: Dictionary) -> bool:
	var session = world.session
	var player = world.player
	var room = session.room
	if not is_instance_valid(room):
		r.notes.append("sem sala ativa depois de entrar")
		return false
	# A descida (bueiro, poço) ainda está pousando o jogador: medir distância à saída
	# antes disso pulava o "afastar e voltar" e a saída nunca armava.
	var landing := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < landing and (session.is_transition_blocked() or player.input_locked): await physics_frame
	for i in 10: await physics_frame
	var target: Vector3
	var mode: String = e.mode
	# Bueiros e poços: entra-se pela ação, sai-se andando até a escada (SpecialPlaceEntrance).
	if mode == "interact" and session.special_place_entrance.handles_place(e.place_id): mode = "special"
	match mode:
		"building":
			target = room.to_global(Vector3(room.definition.entrance_local) + Vector3(0, 0, 2.4))
		"walkup":
			target = room.exit_position + Vector3(0, 0, 1.5)
		"special":
			# O retorno só arma depois de afastar 1,3 m da saída.
			if _flat(player.global_position - room.exit_position) < 1.5:
				var away: Vector3 = room.exit_position + (player.global_position - room.exit_position).normalized() * 1.8
				if (player.global_position - room.exit_position).length() < .1: away = room.exit_position + Vector3(0, 0, -1.8)
				var before: Vector3 = player.global_position
				await _walk_to(away, 4000)
				if _flat(player.global_position - before) < .3:
					r.notes.append("não afastou da saída: %s → %s; velocidade %s; bloqueio %s" % [_v(before), _v(player.global_position), _v(player.velocity), _blocker()])
			target = room.exit_position + (room.exit_position - player.global_position).normalized() * .6
		_:
			target = room.exit_position
	var end := Time.get_ticks_msec() + 15000
	var stuck_since := Time.get_ticks_msec()
	var last: Vector3 = player.global_position
	while Time.get_ticks_msec() < end and not session.state.place_id.is_empty():
		if mode == "interact" and _flat(player.global_position - room.exit_position) < 1.2:
			player.automatic_direction = Vector3.ZERO
			var action: Dictionary = session.nearest()
			if action.get("id", "") == "exit":
				await session.interact()
				var t := Time.get_ticks_msec() + 15000
				while Time.get_ticks_msec() < t and not session.state.place_id.is_empty(): await physics_frame
				break
		if not player.input_locked:
			var to: Vector3 = target - player.global_position
			to.y = 0
			player.automatic_direction = to.normalized() if to.length() > .1 else Vector3.ZERO
		if player.global_position.distance_to(last) > .05:
			last = player.global_position
			stuck_since = Time.get_ticks_msec()
		if Time.get_ticks_msec() - stuck_since > 3000 and not player.input_locked and not session.is_transition_blocked(): break
		await physics_frame
	player.automatic_direction = Vector3.ZERO
	var t2 := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < t2 and not session.state.place_id.is_empty(): await physics_frame
	var settle := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < settle and (session.is_transition_blocked() or player.input_locked): await physics_frame
	if not session.state.place_id.is_empty():
		r.notes.append("não saiu: parado em %s (saída %s)" % [_v(player.global_position), _v(room.exit_position if is_instance_valid(room) else Vector3.ZERO)])
		var special = session.special_place_entrance
		if special.handles_place(e.place_id):
			r.notes.append("jogador: automático=%s física=%s intenção=%s vel=%s dist_saída=%.2f proc=%s" % [player.controlled_automatically, player.is_physics_processing(), _v(player.automatic_direction), _v(player.velocity), _flat(player.global_position - room.exit_position), player.can_process()])
			r.notes.append("estado: armada=%s bloqueado=%s vida=%s travado=%s modal=%s transição=%s na_parede=%s" % [special.exit_armed, special._blocked(), world.gameplay.health, player.input_locked, session.modal, session.is_transition_blocked(), player.is_on_wall()])
		var blocker := _blocker()
		if not blocker.is_empty(): r.notes.append("bloqueado por " + blocker)
		# Libera para a próxima entrada sem contaminar: sai pelo caminho do jogo.
		await session.leave_place()
		for frame in 30: await physics_frame
		return false
	return true

func _walk_to(point: Vector3, ms: int) -> void:
	var player = world.player
	var end := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		var to: Vector3 = point - player.global_position
		to.y = 0
		if to.length() < .2: break
		player.automatic_direction = to.normalized()
		await physics_frame
	player.automatic_direction = Vector3.ZERO

## Quanto a porta visível abriu (0..1), ou null se a entrada não tem folha.
func _door_amount(e: Dictionary) -> Variant:
	var session = world.session
	match e.mode:
		"building":
			var access = session.building_entrance.facade
			if not is_instance_valid(access) or str(access.get_meta("place_id", "")) != e.id: return null
			var leaves := _walk_in_leaves(access.facade)
			if not leaves.is_empty():
				var best := 0.0
				for leaf in leaves: best = maxf(best, leaf.open_amount)
				return best
			if _painted(access.facade): return 0.0
			# Fachada de caixas: o vão é cortado e a folha de metal aparece aberta.
			return 1.0 if access.access_ready else 0.0
		"walkup":
			if e.id in ["maciota", "port_boss_garage"]: return null
			var walk = session.weapon_shop_entrance
			if not is_instance_valid(walk._facade) or walk._facade_id != e.id: return null
			# Fachada pintada da serra: a folha visível é a do kit.
			var leaves := _walk_in_leaves(_walkup_art(walk._facade))
			if not leaves.is_empty():
				var best := 0.0
				for leaf in leaves: best = maxf(best, leaf.open_amount)
				return minf(best, float(walk._facade.open_amount))
			return float(walk._facade.open_amount)
		"special":
			var special = session.special_place_entrance
			if e.id == "mountain_mystery_cave": return null
			if is_instance_valid(special.hatch) and special.hatch_id == e.id: return float(special.hatch.get("open_amount"))
			return null
	return null

func _door_kind(e: Dictionary) -> String:
	var session = world.session
	match e.mode:
		"building":
			var access = session.building_entrance.facade
			if is_instance_valid(access) and is_instance_valid(access.facade) and _painted(access.facade): return "folha pintada (PaintedFacadeKit)"
			return "vão cortado + folha de metal"
		"walkup":
			if e.id in ["maciota", "port_boss_garage"]: return "portão já aberto"
			var walk = session.weapon_shop_entrance
			# Quartel pintado: baia aberta, sem portão para empurrar (WeaponShopEntrance não a segue).
			if e.id == "harbor_fire_station" and walk._painted(e.id): return "vão pintado sem folha (baia aberta)"
			if is_instance_valid(walk._facade) and _painted(_walkup_art(walk._facade)):
				if _walk_in_leaves(_walkup_art(walk._facade)).is_empty(): return "vão pintado sem folha"
				return "folha pintada (kit) + dobradiça invisível"
			return "folha com dobradiça (empurrar)"
		"special":
			if e.id == "mountain_mystery_cave": return "boca de caverna"
			return "escotilha"
	if SEWERS.is_manhole(e.id): return "tampa (ação)"
	return "ação Entrar (sem folha)"

## O adaptador WalkupDoor fica dentro da arte do lugar; as outras fachadas de
## acesso (banco, loja) são a própria arte.
func _walkup_art(facade: Node) -> Node:
	return facade.get_parent() if str(facade.name) == "WalkupDoor" else facade

func _painted(node: Node) -> bool:
	return node != null and not node.find_children("PaintedFacade_*", "", true, false).is_empty()

func _walk_in_leaves(node: Node) -> Array:
	var result := []
	if node == null: return result
	for anchor in node.find_children("Doorway_front*", "Node3D", true, false):
		if anchor.has_meta("walk_in") and anchor.has_node("Door"): result.append(anchor.get_node("Door"))
	return result

func _check_alignment(e: Dictionary, r: Dictionary, door: Vector3) -> void:
	var art: Node = null
	if e.mode == "building":
		var access = world.session.building_entrance.facade
		if is_instance_valid(access) and str(access.get_meta("place_id", "")) == e.id: art = access.facade
	elif e.mode == "walkup":
		for candidate in get_nodes_in_group("v2_walkin_facade"):
			if str(candidate.get_meta("place_id", "")) == e.id: art = _walkup_art(candidate)
	if art == null or not _painted(art): return
	var leaves := _walk_in_leaves(art)
	if leaves.is_empty():
		_check_leafless_opening(art, r, door)
		return
	var best := INF
	for center in _walk_in_openings(art): best = minf(best, _flat(center - door))
	r.alignment_m = snappedf(best, .01)
	for leaf in leaves:
		if leaf._area != null: r["leaf_zone"] = {"monitoring":leaf._area.monitoring, "processing":leaf.can_process(), "in_tree":leaf._area.is_inside_tree(), "mask":leaf._area.collision_mask, "zone_origin":_v(leaf._area.get_child(0).global_position)}
	r.aligned = best <= .35
	if not r.aligned: r.notes.append("vão pintado a %.2f m da entrada real" % best)

## Fachada pintada sem folha walk_in: vale se a entrada real cai num vão que a pintura
## desenhou SEM folha (style.json "leaf": false), onde não há folha para coincidir com ela.
## O vão inteiro é a porta: alinhado se a entrada fica dentro da largura dele e a até
## DOOR_REACH (o alcance em que uma folha pintada abre) do plano dele. Casos de 19/10:
## quartel (baia da direita aberta, a do portão de enrolar antigo; a folha pintada da
## lateral é outra porta, e o vestíbulo de PaintedFireStation fica na baia) e Bay Medical
## (recuo pintado da porta de vidro de correr 3D, 0,36 m à frente do plano, sob a marquise).
## Folha pintada removida ou entrada ao lado do vão continuam falhando.
func _check_leafless_opening(art: Node, r: Dictionary, door: Vector3) -> void:
	var best := {}
	for anchor in art.find_children("Doorway_front*", "Node3D", true, false):
		if not anchor.has_meta("leafless"): continue
		var size: Vector2 = anchor.get_meta("opening_size")
		var left: Vector3 = anchor.global_transform * Vector3.ZERO
		var right: Vector3 = anchor.global_transform * Vector3(size.x, 0, 0)
		var across := Vector2(right.x - left.x, right.z - left.z)
		var outward := Vector2(anchor.global_basis.z.x, anchor.global_basis.z.z).normalized()
		var to_door := Vector2(door.x - left.x, door.z - left.z)
		var t := to_door.dot(across) / across.length_squared()
		var row := {"lateral_m":absf(t - .5) * across.length(), "half_m":across.length() * .5,
			"depth_m":to_door.dot(outward), "inside":t >= 0.0 and t <= 1.0}
		if best.is_empty() or (row.inside and not best.inside) or (row.inside == best.inside and absf(row.depth_m) < absf(best.depth_m)): best = row
	if best.is_empty():
		r.aligned = false
		r.notes.append("fachada pintada sem folha de entrada (walk_in) nem vão sem folha na porta real")
		return
	r.painted_opening = {"leafless":true, "lateral_m":snappedf(best.lateral_m, .01), "half_width_m":snappedf(best.half_m, .01), "depth_m":snappedf(best.depth_m, .01)}
	r.aligned = best.inside and absf(best.depth_m) <= PaintedFacadeKit.DOOR_REACH
	if not r.aligned: r.notes.append("vão pintado sem folha não contém a entrada real (%.2f m do meio, meia largura %.2f m, %.2f m do plano)" % [best.lateral_m, best.half_m, best.depth_m])

## Centro visível de cada vão de entrada: o meio das folhas fechadas (porta dupla: as
## duas), no quad pintado com a escala que ele tem no mundo. Antes media só a folha
## esquerda, a meia largura do quad sem escala a partir da dobradiça: porta dupla dava
## 1/4 do vão de erro mesmo centrada, e no prédio esticado pelo editor (a folha é pivô
## rígido, o quad estica) a delegacia 18x10 m dava 1,11 m com o vão a 0,01 m da entrada
## em x e o jogador cruzando no meio dele (sonda de 18/10).
func _walk_in_openings(node: Node) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if node == null: return result
	for anchor in node.find_children("Doorway_front*", "Node3D", true, false):
		if not anchor.has_meta("walk_in"): continue
		var sum := Vector3.ZERO
		var count := 0
		for leaf in anchor.get_children():
			if not leaf is PaintedFacadeKit.PaintedDoor: continue
			var quad: Node3D = leaf.hinge.get_child(0)
			# Posição fechada: sem o giro da dobradiça, a folha pode estar abrindo.
			sum += leaf.global_transform * (leaf.hinge.position + quad.position)
			count += 1
		if count > 0: result.append(sum / float(count))
	return result

## Portas pintadas no mundo: só a entrada de verdade reage ao jogador.
func _audit_painted_doors(region: String) -> void:
	var reacting := 0
	var closed := 0
	var orphans: Array[String] = []
	for node in _all(root):
		if not node is PaintedFacadeKit.PaintedDoor: continue
		if node._area != null:
			reacting += 1
			if not node.get_parent().has_meta("walk_in"): orphans.append(str(node.get_path()))
		else: closed += 1
	print("DOOR_AUDIT_PAINTED ", region, " reagem=", reacting, " fechadas=", closed, " reagem_sem_interior=", orphans.size())
	rows.append({"id":"painted_doors_" + region, "place_id":"", "region":region, "system":"PaintedFacadeKit", "mode":"painted_scan",
		"name":"portas pintadas carregadas", "door":[], "door_kind":"folhas pintadas", "opened":"n/a", "entered":"n/a", "exited":"n/a",
		"result":"PASS" if orphans.is_empty() else "FAIL", "notes":["reagem=%d fechadas=%d (amostra dos trechos carregados)" % [reacting, closed]] + orphans, "photos":[]})

func _all(node: Node) -> Array:
	var list := [node]
	for child in node.get_children(): list.append_array(_all(child))
	return list

func _blocker() -> String:
	var player = world.player
	var parts: Array[String] = []
	for index in player.get_slide_collision_count():
		var collision = player.get_slide_collision(index)
		var collider = collision.get_collider()
		if is_instance_valid(collider) and collision.get_normal().y < .5: parts.append(str(collider.get_path()).right(90))
	return ", ".join(parts)

func _photo(label: String) -> String:
	if DisplayServer.get_name() == "headless": return ""
	await process_frame
	await RenderingServer.frame_post_draw
	var path := FOLDER.path_join(label + ".png")
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	return path

func _flat(v: Vector3) -> float: return Vector2(v.x, v.z).length()
func _v(v: Vector3) -> String: return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]

func _finish(code := -1) -> void:
	var failures := rows.filter(func(row): return row.result == "FAIL")
	var inv := []
	for e in inventory: inv.append({"id":e.id, "place_id":e.place_id, "region":e.region, "system":e.system, "mode":e.mode, "name":e.name, "kind":e.kind})
	var report := {"date":"2026-10-15", "tested":rows.size(), "failures":failures.size(), "inventory":inv, "rows":rows,
		"filters":{"only":Array(only), "system":system_filter, "region":region_filter}}
	var name := "door-audit.json" if only.is_empty() and system_filter.is_empty() and region_filter.is_empty() else "door-audit-partial.json"
	var file := FileAccess.open(ProjectSettings.globalize_path(FOLDER.path_join(name)), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t"))
	print("")
	print("%-48s %-9s %-8s %-6s %-6s %s" % ["entrada", "região", "abriu", "entrou", "saiu", "resultado"])
	for row in rows:
		print("%-48s %-9s %-8s %-6s %-6s %s" % [str(row.id).left(48), row.region, str(row.opened), str(row.entered), str(row.exited), row.result])
	print("DOOR_AUDIT total=", rows.size(), " falhas=", failures.size(), " json=", ProjectSettings.globalize_path(FOLDER.path_join(name)))
	if is_instance_valid(world): world.queue_free()
	quit((0 if failures.is_empty() else 1) if code < 0 else code)
