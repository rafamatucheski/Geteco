extends SceneTree
## Contratos centrais sem carregar o mundo (segundos, não minutos): recuperação de save,
## achados das cavernas do deserto e a tabela de vítimas do crime. É o primeiro passo de
## tools/run_core_suite.sh; quebrou aqui, o resto da suíte nem precisa rodar.
## Uso: "$GODOT" --headless --path . --script res://tests/test_core_contracts.gd
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const WILDS := preload("res://runtime/desert/wilds/DesertWilds.gd")
const VICTIMS := preload("res://gameplay/police_response/CrimeVictims.gd")
const PENALTY := preload("res://runtime/RecoveryPenalty.gd")
const BALANCE := preload("res://data/catalogs/EconomyBalance.gd")
const STORY_PAY := preload("res://systems/campaign/StoryPay.gd")
const MISSIONS := preload("res://data/campaign/HarborMissions.gd")
const TOWS := preload("res://data/catalogs/TowJobs.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const ARCS := preload("res://runtime/JournalArcs.gd")
const ROADSIDE := preload("res://runtime/desert/roadside/RoadsideLayout.gd")
const ROADSIDE_STATE := preload("res://runtime/desert/roadside/RoadsideState.gd")
const ROADSIDE_SECRETS := preload("res://runtime/desert/roadside/RoadsideSecrets.gd")
const DESERT_LAYOUT := preload("res://world/desert/DesertLayout.gd")

class IsolatedLaunch extends "res://runtime/SessionLaunch.gd":
	var folder := ""
	func slot_path(id: String) -> String:
		return folder.path_join(id + ".json") if id in ["progress"] + SLOT_IDS else ""

class RecordingGameplay extends "res://gameplay/Gameplay.gd":
	var reported: Array = []
	func report_observed_crime(points: int, _point: Vector3, kind: String = "theft", _victim: Node3D = null) -> bool:
		reported.append("%s:%d" % [kind, points])
		return true

class FakeState extends RefCounted:
	var place_id := ""
	func weapons_allowed() -> bool: return true

class FakePerson extends CharacterBody3D:
	var health := 100.0
	var dead := false
	func _init(role: String) -> void:
		if not role.is_empty(): set_meta("gameplay_role", role)
	func receive_damage(amount: float, _source: Node = null) -> void:
		if dead or amount <= 0.0: return
		health = maxf(0.0, health - amount)
		dead = health <= 0.0

class FakeVehicle extends Node:
	func is_player_damage_source() -> bool: return true

var checks := 0
var failures: Array[String] = []
var folder := ""

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): failures.append("watchdog 60 s"); finish())
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	print("CORE_CONTRACTS ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func run() -> void:
	folder = "user://tests/core_contracts_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	save_recovery()
	slot_recovery()
	desert_caves()
	recovery_penalty()
	economy_balance()
	journal_arcs()
	desert_roadside()
	await crime_victims()
	finish()

# --- Save que um bloco quebrado não pode mais tornar inabrível -------------------------------

func save_recovery() -> void:
	var base: Dictionary = STATE.new().snapshot()
	base.economy.balance = 1234
	var clean: Dictionary = STORE.recover_snapshot(base)
	check(not clean.is_empty() and clean.dropped.is_empty(), "save válido não perde nada")
	var one := base.duplicate(true)
	one.world.ashbend_secret_car_claimed = "sim"
	check(not STATE.new().restore_snapshot(one), "fixture: bloco inválido derruba a validação estrita")
	var plan: Dictionary = STORE.recover_snapshot(one)
	check(not plan.is_empty() and plan.dropped == ["ashbend_secret_car_claimed"], "um bloco quebrado: só ele volta ao padrão")
	check(not plan.is_empty() and int(plan.data.economy.balance) == 1234, "carteira sobrevive à recuperação")
	check(not plan.is_empty() and STATE.new().restore_snapshot(plan.data), "snapshot recuperado passa na validação estrita")
	var two := one.duplicate(true)
	two.world.remote_coal_secret_revealed = 7
	plan = STORE.recover_snapshot(two)
	var dropped: Array = plan.get("dropped", [])
	dropped.sort()
	check(dropped == ["ashbend_secret_car_claimed", "remote_coal_secret_revealed"], "dois blocos quebrados: só os dois saem (%s)" % [dropped])
	var moved := base.duplicate(true)
	moved.place_id = "lugar_que_nao_existe_mais"
	plan = STORE.recover_snapshot(moved)
	check(plan.get("dropped", []) == [STORE.RECOVERY_LOCATION] and str(plan.data.place_id).is_empty(), "lugar removido do catálogo: volta ao ponto de retorno")
	var core := base.duplicate(true)
	core.economy = {"version": 1}
	check(STORE.recover_snapshot(core).is_empty(), "carteira corrompida não é 'recuperada' por descarte")

	var path := folder.path_join("slot.json")
	var broken_text := JSON.stringify(one)
	write(path, broken_text)
	var store = STORE.new()
	store.path = path
	check(not store.load_into(STATE.new()).get("ok", false), "fixture: slot quebrado não carrega sem recuperação")
	plan = STORE.recovery_plan(path)
	check(not plan.is_empty() and plan.source == path, "plano lê o arquivo principal")
	check(store.publish_recovery(plan) == OK, "recuperação publica o save")
	var restored = STATE.new()
	check(store.load_into(restored).get("ok", false) and restored.economy.balance == 1234, "slot recuperado carrega com a carteira")
	var originals: Array[String] = []
	for name_value in DirAccess.get_files_at(folder):
		if name_value.begins_with("slot.json.pre-recovery."): originals.append(name_value)
	check(originals.size() == 1 and FileAccess.get_file_as_string(folder.path_join(originals[0])) == broken_text, "bytes originais guardados ao lado (.pre-recovery)")

func slot_recovery() -> void:
	var launch := IsolatedLaunch.new()
	launch.folder = folder.path_join("slots")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(launch.folder))
	var broken: Dictionary = STATE.new().snapshot()
	broken.world.ashbend_secret_car_claimed = "sim"
	write(launch.slot_path("slot_01"), JSON.stringify(broken))
	write(launch.slot_path("slot_02"), "{ não é JSON")
	var row := {}
	for item in launch.list_slots():
		if item.id == "slot_01": row = item
	check(row.get("valid", false) and row.get("recoverable", false), "menu oferece o slot como recuperável")
	var label := str(row.get("label", ""))
	check(row.get("recovery_dropped", []) == ["ashbend_secret_car_claimed"] and (label.contains("Recuperável") or label.contains("Recoverable")), "rótulo diz o que volta ao padrão (%s)" % label.replace("\n", " "))
	check(launch.latest_slot().is_empty(), "Continuar não recupera às cegas")
	check(launch.prepare("slot_02", false) == ERR_FILE_CORRUPT, "arquivo ilegível continua recusado")
	check(launch.prepare("slot_01", false) == OK, "escolher o slot recupera")
	check(not STORE.read_valid(launch.slot_path("slot_01")).is_empty(), "slot vira um save estritamente válido")
	check(not launch.recovery_notice.is_empty(), "sessão recebe o aviso do que foi redefinido")
	launch.free()

# --- Cavernas do deserto: recibo na carteira, sem teto de dinheiro solto ---------------------

func site(id: String) -> Dictionary:
	for candidate in WILDS.SITES:
		if candidate.id == id: return candidate
	return {}

func desert_caves() -> void:
	var cash := site("cave_vulture")
	var wallet = ECONOMY.new()
	check(int(cash.amount) > 300 and not wallet.collect_loose_cash(int(cash.amount)), "fixture: R$ %d não cabe no dinheiro solto" % int(cash.amount))
	var first: Dictionary = WILDS.claim_cave(wallet, cash)
	check(first.ok and wallet.balance == int(cash.amount), "lata da caverna paga R$ %d inteiros" % int(cash.amount))
	var again: Dictionary = WILDS.claim_cave(wallet, cash)
	check(again.ok and not again.changed and wallet.balance == int(cash.amount), "segunda visita não paga de novo")
	var reloaded = ECONOMY.new()
	check(reloaded.restore_snapshot(wallet.snapshot()) and WILDS.cave_claimed(reloaded, cash), "achado continua pego depois de salvar e carregar")
	var weapon := site("cave_coyote")
	var armed: Dictionary = WILDS.claim_cave(wallet, weapon)
	check(armed.ok and wallet.owns_weapon(str(weapon.weapon)), "caverna entrega a arma")
	check(WILDS.claim_cave(wallet, weapon).ok and not WILDS.claim_cave(wallet, weapon).changed, "arma não sai duas vezes")
	var veteran = ECONOMY.new()
	var repeated := site("cave_sun")
	veteran.grant_weapon(str(repeated.weapon))
	var before := int(veteran.get_ammo(str(repeated.weapon)).reserve)
	var ammo: Dictionary = WILDS.claim_cave(veteran, repeated)
	check(ammo.ok and ammo.reason == "ammo" and int(veteran.get_ammo(str(repeated.weapon)).reserve) == before + WILDS.CAVE_AMMO, "arma repetida vira munição")
	check(WILDS.cave_claimed(veteran, repeated), "munição também marca o achado")
	var state = STATE.new()
	state.economy = wallet
	check(STATE.new().restore_snapshot(state.snapshot()), "recibos das cavernas passam na validação do save")

# --- Morte e prisão custam: conta, multa e munição apreendida --------------------------------

func recovery_penalty() -> void:
	check(PENALTY.fee(0) == 0 and PENALTY.fee(999) == 99 and PENALTY.fee(50000) == PENALTY.CAP, "conta: 10%% do dinheiro, teto R$ %d" % PENALTY.CAP)
	check(PENALTY.place_for("harbor", false) == PENALTY.HOSPITAL and PENALTY.place_for("harbor", true) == PENALTY.PRECINCT and PENALTY.place_for("desert", false).is_empty(), "Harbor volta pelo hospital ou pela delegacia; deserto pelo ponto da região")
	for id in [PENALTY.HOSPITAL, PENALTY.PRECINCT]:
		check(not preload("res://world/places/PlaceCatalog.gd").get_definition(id).is_empty(), "%s existe no catálogo" % id)
	var wallet = ECONOMY.new()
	wallet.grant_reward("test_recovery_wallet", 5000)
	var death: Dictionary = PENALTY.apply(wallet, false)
	check(death.amount == 500 and wallet.balance == 4500 and death.ammo == 0, "morte cobra a conta e não mexe na munição")
	check(wallet.buy_weapon("pistol"), "fixture: pistola comprada com recibo")
	var loaded: Dictionary = wallet.get_ammo("pistol")
	var before_arrest: int = wallet.balance
	var arrest: Dictionary = PENALTY.apply(wallet, true)
	check(arrest.amount == PENALTY.fee(before_arrest) and wallet.balance == before_arrest - arrest.amount and arrest.ammo == int(loaded.magazine) + int(loaded.reserve) and arrest.ammo > 0, "prisão cobra a multa e leva a munição (%s)" % [arrest])
	check(wallet.owns_weapon("pistol") and int(wallet.get_ammo("pistol").magazine) == 0 and int(wallet.get_ammo("pistol").reserve) == 0, "a arma comprada fica, vazia")
	check(ECONOMY.validate_snapshot(wallet.snapshot()), "carteira continua válida depois do confisco")
	var broke = ECONOMY.new()
	check(PENALTY.apply(broke, true).amount == 0 and broke.balance == 0, "sem dinheiro, sem dívida")
	var grid = ECONOMY.new()
	grid.enable_grid_inventory()
	grid.grant_weapon("smg")
	grid.add_ammo("smg", 120)
	var carried := int(grid.get_ammo("smg").magazine) + int(grid.get_ammo("smg").reserve)
	var taken: int = grid.confiscate_carried_ammo()
	check(taken == carried and taken > 0 and int(grid.get_ammo("smg").reserve) == 0, "inventário em grade: bolsos e arma esvaziados (%d de %d)" % [taken, carried])
	check(grid.owns_weapon("smg") and ECONOMY.validate_snapshot(grid.snapshot()), "inventário em grade continua válido")
	var cheat = ECONOMY.new()
	cheat.cheat_infinite_money = true
	check(PENALTY.apply(cheat, false).amount == 0, "modo desenvolvedor com dinheiro infinito não paga")

# --- Economia: a história paga e libera o guincho; nada quebra save antigo -------------------

func economy_balance() -> void:
	var story_total := 0
	for id in MISSIONS.ORDER: story_total += STORY_PAY.total(id)
	check(story_total == 21500, "história do Harbor paga R$ 21.500 no total (%d)" % story_total)
	var wallet = ECONOMY.new()
	var paid: int = STORY_PAY.settle({"claimed_rewards": ["primeiro_giro", "cobra_contact", "missao_inexistente"]}, wallet)
	check(paid == BALANCE.STORY_BONUS.primeiro_giro + BALANCE.STORY_BONUS.cobra_contact and wallet.balance == paid, "bônus sai para cada missão recebida")
	check(STORY_PAY.settle({"claimed_rewards": ["primeiro_giro", "cobra_contact"]}, wallet) == 0, "bônus não sai duas vezes")
	var saved: Dictionary = FIXTURE.full_snapshot(Vector3.ZERO, true)
	var state = STATE.new()
	if check(state.restore_snapshot(saved), "fixture: save com o Harbor concluído"):
		# Como MissionWorld faz ao concluir: recebe a recompensa base antes do bônus.
		for id in state.campaign.snapshot().pending_rewards.keys(): state.campaign.claim_reward(state.economy, id)
		var claimed: Array = state.campaign.snapshot().claimed_rewards
		var back_pay: int = STORY_PAY.settle(state.campaign.snapshot(), state.economy)
		var expected := 0
		for id in claimed: expected += int(BALANCE.STORY_BONUS.get(str(id), 0))
		check(back_pay == expected and back_pay > 0, "save antigo recebe o retroativo uma vez (R$ %d)" % back_pay)
		check(STATE.new().restore_snapshot(state.snapshot()), "recibos de bônus passam na validação do save")
	check(TOWS.unlocked([]).size() == 1 and TOWS.unlocked([])[0] == 0 and TOWS.next_index(7, []) == 0, "guincho começa só com o reboque simples")
	check(TOWS.unlocked(MISSIONS.ORDER).size() == TOWS.JOBS.size(), "fim do Harbor libera todas as faixas")
	var cycle := 0
	for job in TOWS.JOBS: cycle += int(job.reward)
	check(cycle == 7100, "rodada completa do guincho paga R$ 7.100 (%d)" % cycle)
	check(TOWS.reward_accepted(4, 6000) and TOWS.reward_accepted(4, 2400) and not TOWS.reward_accepted(4, 999), "contrato de guincho antigo continua válido")
	check(preload("res://gameplay/armored/ArmoredSchedule.gd").CASH_PER_TRUCK == 20000, "carro-forte paga R$ 20.000")

# --- Diário: toda história em andamento aparece, de qualquer região --------------------------

func journal_arcs() -> void:
	var fresh_campaign: Dictionary = STATE.new().campaign.snapshot()
	var fresh: Array[String] = ARCS.lines({}, fresh_campaign)
	check(fresh.size() == 1 and fresh[0] == TranslationServer.translate(preload("res://activities/mountain_story/MountainStory.gd").journal_line({})), "jogo novo: só a pista da serra (%s)" % [fresh])
	var world := {"blade_forge": {"version": 1, "stage": "seek_hermit"}, "urban_operations": {"truckers_village": {"version": 1, "started": true, "belt": true, "crank": false, "completed": false}}}
	var some: Array[String] = ARCS.lines(world, fresh_campaign)
	check(some.size() == 3, "Forja da Serra e Tonico entram no diário (%s)" % [some])
	check(ARCS.lines({"urban_operations": {"truckers_village": {"started": true, "completed": true}}, "blade_forge": {"version": 1, "stage": "done"}}, fresh_campaign).size() == 1, "história terminada sai do diário")
	var saved: Dictionary = FIXTURE.full_snapshot(Vector3.ZERO, true)
	var finished = STATE.new()
	if check(finished.restore_snapshot(saved), "fixture: Harbor concluído para o deserto"):
		var desert_lines: Array[String] = ARCS.lines(finished.world_state, finished.campaign.snapshot())
		var desert_prefix := String(TranslationServer.translate("Deserto")) + " · "
		check(desert_lines.any(func(line): return line.begins_with(desert_prefix)), "depois do Harbor, o ato 2 do deserto aparece (%s)" % [desert_lines])
		var done_world: Dictionary = finished.world_state.duplicate(true)
		var story: Dictionary = preload("res://runtime/desert/DesertStoryState.gd").data(done_world)
		story.delivered = true
		done_world.desert_story = story
		check(not ARCS.lines(done_world, finished.campaign.snapshot()).any(func(line): return line.begins_with(desert_prefix)), "ato 2 entregue sai do diário")

# --- Tabela de vítimas: arma e atropelamento contam igual ------------------------------------

# --- Beira de estrada do deserto (fase 1, 19/10) ----------------------------------------------

func road_distance(point: Vector2) -> Dictionary:
	var best := {"distance": INF, "toward": Vector2.ZERO, "id": ""}
	for road in DESERT_LAYOUT.roads():
		var points: PackedVector3Array = road.points
		for i in range(1, points.size()):
			var closest := Geometry2D.get_closest_point_to_segment(point, Vector2(points[i - 1].x, points[i - 1].z), Vector2(points[i].x, points[i].z))
			if closest.distance_to(point) < best.distance: best = {"distance": closest.distance_to(point), "toward": (closest - point).normalized(), "id": str(road.id)}
	return best

func desert_roadside() -> void:
	ROADSIDE._enabled = 1
	for definition in ROADSIDE.SITES:
		var center: Vector2 = definition.center
		var road := road_distance(center)
		# Fora da pista (cabe o lugar inteiro) e perto o bastante para ser visto de quem passa.
		check(road.distance >= 14.0 and road.distance <= 32.0, "%s a %.1f m da %s" % [definition.id, road.distance, road.id])
		var front := Basis(Vector3.UP, float(definition.yaw)) * Vector3.BACK
		check(Vector2(front.x, front.z).dot(road.toward) > .9, "%s de frente para a estrada" % definition.id)
		check(DESERT_LAYOUT.BOUNDS.grow(-40).has_point(center), "%s dentro do deserto" % definition.id)
		check(DESERT_LAYOUT.drag_reservation_clear(center, 8.0), "%s fora da reserva da arrancada" % definition.id)
		for site in WILDS.SITES:
			check((site.center as Vector2).distance_to(center) > ROADSIDE.SITE_RADIUS + WILDS.SITE_RADIUS + 20.0, "%s longe de %s" % [definition.id, site.id])
		for building in DESERT_LAYOUT.buildings():
			check(Vector2(building.position.x, building.position.z).distance_to(center) > 60.0, "%s longe de %s" % [definition.id, building.id])
		check(ROADSIDE.reserved(center), "%s reservado contra enfeite" % definition.id)
		# A linha de luz (DesertUtilityLines) não consulta reservas: o lugar desvia dos postes.
		var nearest_pole := INF
		for record in preload("res://world/desert/DesertUtilityLines.gd").records():
			if record.kind == "utility_pole": nearest_pole = minf(nearest_pole, Vector2(record.position.x, record.position.z).distance_to(center))
		check(nearest_pole > 16.0, "%s longe dos postes (%.1f m)" % [definition.id, nearest_pole])
	for stretch in ROADSIDE.EVENT_STRETCHES:
		check(road_distance(stretch.a).distance < 1.0 and road_distance(stretch.b).distance < 1.0, "trecho %s em cima da estrada" % stretch.id)
	# Ponto de evento: à frente de quem dirige no trecho; nada fora dele nem colado na ponta.
	var south := ROADSIDE.event_point(Vector2(342.5, -905), Vector2(0, -1), 120.0)
	check(not south.is_empty() and south.stretch == "route66_north" and absf(south.point.y - -1025.0) < .5 and south.direction.dot(Vector2(0, -1)) > .99, "evento nasce 120 m à frente na Route 66 (%s)" % [south])
	check(ROADSIDE.event_point(Vector2(342.5, -905), Vector2(0, 1), 120.0).is_empty(), "dirigindo para fora do trecho: sem evento")
	check(ROADSIDE.event_point(Vector2(380, -950), Vector2(0, -1), 60.0).is_empty(), "fora da pista: sem evento")
	check(ROADSIDE.event_point(Vector2(342.5, -950), Vector2.ZERO).is_empty(), "parado: sem evento")
	check(ROADSIDE.event_point(Vector2(342.5, -1000), Vector2(1, 0), 60.0).is_empty(), "cruzando a estrada de lado: sem evento")
	# Todo trecho recebe evento na distância padrão (240 m) para quem chega pela mesma estrada, nos
	# dois sentidos. Antes os trechos de 180 m (as duas pontas da Route 66) nunca recebiam.
	for stretch in ROADSIDE.EVENT_STRETCHES:
		var a: Vector2 = stretch.a
		var b: Vector2 = stretch.b
		var direction: Vector2 = (b - a).normalized()
		var middle: Vector2 = (a + b) * .5
		var forward := ROADSIDE.event_point(middle - direction * 240.0, direction)
		var backward := ROADSIDE.event_point(middle + direction * 240.0, -direction)
		check(forward.get("stretch", "") == stretch.id and (forward.point as Vector2).distance_to(middle) < .5 and backward.get("stretch", "") == stretch.id and (backward.point as Vector2).distance_to(middle) < .5, "trecho %s recebe evento nos dois sentidos" % stretch.id)
	for route in ROADSIDE.COURIER_ROUTES:
		check(int(BALANCE.ROADSIDE_COURIER.get(str(route.id), 0)) > 0, "entrega %s tem pagamento na tabela" % route.id)
	check(BALANCE.ROADSIDE_TRUCK_CASHBOX.y <= 300 and BALANCE.ROADSIDE_ROADBLOCK_LOOT.y <= 300, "dinheiro solto dos eventos cabe no teto de 300")
	# Estado salvo: opcional, inválido volta ao padrão, recibo sempre novo.
	var world := {}
	check(ROADSIDE_STATE.data(world) == ROADSIDE_STATE.defaults(), "save antigo sem beira de estrada")
	var first := ROADSIDE_STATE.next_receipt(world, "repair")
	check(first == "desert_roadside:repair:1" and ROADSIDE_STATE.next_receipt(world, "courier") == "desert_roadside:courier:2", "recibos em sequência (%s)" % first)
	world[ROADSIDE_STATE.KEY] = {"version": 1, "revealed": "x", "serial": -1}
	check(ROADSIDE_STATE.data(world) == ROADSIDE_STATE.defaults(), "bloco inválido volta ao padrão")
	world = {}
	var wallet := ECONOMY.new()
	var all := ROADSIDE_SECRETS.missing(world, wallet)
	check(all.size() == 10, "torre conhece 10 achados (%d)" % all.size())
	var tower: Dictionary = ROADSIDE.site("radio_tower")
	var origin := Vector3(tower.center.x, 0, tower.center.y)
	var seen := ROADSIDE_SECRETS.nearest(world, wallet, origin, 3)
	check(seen.size() == 3 and ROADSIDE_STATE.reveal(world, seen.map(func(entry): return entry.id)).size() == 3, "torre revela os três mais perto")
	check(ROADSIDE_STATE.reveal(world, [seen[0].id]).is_empty(), "revelar de novo não duplica")
	var next := ROADSIDE_SECRETS.nearest(world, wallet, origin, 3, ROADSIDE_STATE.data(world).revealed)
	check(next.size() == 3 and next.all(func(entry): return not seen.any(func(old): return old.id == entry.id)), "segunda subida aponta outros três")
	check(ROADSIDE_SECRETS.map_markers(world, wallet).size() == ROADSIDE.SITES.size() + 3, "mapa: lugares mais os três avistados")
	ROADSIDE_STATE.reveal(world, ["cave:cave_sun"])
	var with_cave := ROADSIDE_SECRETS.map_markers(world, wallet).size()
	WILDS.claim_cave(wallet, site("cave_sun"))
	check(ROADSIDE_SECRETS.map_markers(world, wallet).size() == with_cave - 1 and not ROADSIDE_SECRETS.missing(world, wallet).any(func(entry): return entry.id == "cave:cave_sun"), "achado pego sai do mapa e da torre")
	ROADSIDE._enabled = 0
	check(not ROADSIDE.reserved(ROADSIDE.SITES[0].center) and ROADSIDE_SECRETS.map_markers(world, wallet).is_empty(), "GETECO_DESERT_ROADSIDE=0 tira reserva e marcadores")
	ROADSIDE._enabled = 1

func classify_role(role: String) -> String:
	var person := FakePerson.new(role)
	var result := VICTIMS.classify(person)
	person.free()
	return result

func crime_victims() -> void:
	check(classify_role("urban_routine") == VICTIMS.PERSON, "morador de prédio é pessoa")
	check(classify_role("cobra") == VICTIMS.HOSTILE, "Cobra é gangue em combate")
	check(classify_role("police") == VICTIMS.POLICE, "policial é policial")
	check(classify_role("") == VICTIMS.OTHER, "sem papel continua 'outro'")
	check(classify_role("angler") == VICTIMS.PERSON and classify_role("meet_guest") == VICTIMS.PERSON, "pescador e convidado do encontro contam como pessoa")
	var guard := FakePerson.new("security")
	guard.set_meta("local_security", true)
	check(VICTIMS.classify(guard) == VICTIMS.OWNER_HANDLED, "segurança do comboio: o dono atribui o crime")

	var gameplay := RecordingGameplay.new()
	var world := Node3D.new()
	var player := CharacterBody3D.new()
	root.add_child(world)
	world.add_child(player)
	gameplay.configure(world, player, null, FakeState.new())
	world.add_child(gameplay)
	gameplay.set_physics_process(false)
	await physics_frame
	var resident := FakePerson.new("urban_routine")
	world.add_child(resident)
	gameplay._damage(resident, 10.0, player)
	check(gameplay.reported == ["assault:12"], "ferir morador a tiro é agressão (%s)" % [gameplay.reported])
	gameplay.reported.clear()
	gameplay._damage(resident, 500.0, player)
	check(gameplay.reported == ["civilian_killed:30"], "matar morador a tiro é homicídio, como atropelar (%s)" % [gameplay.reported])
	gameplay.reported.clear()
	var unknown := FakePerson.new("")
	world.add_child(unknown)
	gameplay._damage(unknown, 500.0, player)
	check(not gameplay.reported.has("civilian_killed:30"), "alvo sem papel nunca vira homicídio (%s)" % [gameplay.reported])
	gameplay.reported.clear()
	var car := FakeVehicle.new()
	world.add_child(car)
	var cobra := FakePerson.new("cobra")
	world.add_child(cobra)
	cobra.dead = true
	gameplay.report_vehicle_assault(cobra, car)
	check(gameplay.reported.is_empty(), "atropelar Cobra não é homicídio de civil (%s)" % [gameplay.reported])
	world.add_child(guard)
	guard.dead = true
	gameplay.report_vehicle_assault(guard, car)
	check(gameplay.reported.is_empty(), "atropelar segurança do comboio fica com o comboio (%s)" % [gameplay.reported])
	var walker := FakePerson.new("civilian")
	world.add_child(walker)
	walker.dead = true
	gameplay.report_vehicle_assault(walker, car)
	check(gameplay.reported == ["civilian_killed:30"], "atropelar pedestre continua homicídio (%s)" % [gameplay.reported])
	world.queue_free()
	await process_frame
	await physics_frame

func _remove_tree(path: String) -> void:
	for name_value in DirAccess.get_files_at(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(name_value)))
	for name_value in DirAccess.get_directories_at(path): _remove_tree(path.path_join(name_value))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func finish() -> void:
	# Só apaga a pasta temporária criada por este teste.
	if folder.begins_with("user://tests/core_contracts_") and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)): _remove_tree(folder)
	print("CORE_CONTRACTS checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
