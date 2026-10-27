extends Node3D
## Vida no meio do nada (playtest 18/10: "o deserto é muito vazio"). Casinhas com morador,
## acampamentos de foras-da-lei e cavernas com um achado, espalhados longe das estradas.
## Como o DesertBanditEncounter, cada lugar só existe perto do jogador: monta a ~110 m (um por
## passo, sem trecho de chão na fila) e solta a ~150 m. Quem morre volta na próxima visita; o achado
## da caverna sai uma vez por save, com recibo na carteira (ver claim_cave).
## GETECO_DESERT_WILDS=0 desliga tudo (A/B no mesmo export).
const G := preload("res://world/desert/DesertGeometry.gd")
const HM := preload("res://world/desert/DesertTerrainMesh.gd")
const RESIDENT := preload("res://runtime/desert/DesertVillageResident.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const REWARD_AUDIO := preload("res://gameplay/RewardAudio.gd")
const BUILD := preload("res://runtime/desert/roadside/RoadsideBuild.gd")
const ART := preload("res://runtime/desert/roadside/RoadsideArt.gd")
const CAVE := preload("res://runtime/desert/wilds/CaveBuild.gd")
const LETTERS := preload("res://data/catalogs/VicenteLetters.gd")
const FLEET_STATE := preload("res://runtime/FleetState.gd")
const GARAGE_STATE := preload("res://runtime/desert/DesertGarageState.gd")
const ADAPTER := preload("res://gameplay/desert_cars/DesertCarAdapter.gd")
## Caixa de munição de cada caverna (20/10): repõe uma vez por dia de jogo, para cada arma de fogo
## que o jogador tem. Explosivos e lança-chamas ficam de fora (são achados de outro tipo).
const AMMO_REFILL := {"pistol": 24, "magnum": 12, "pistol_suppressed": 30, "smg": 60, "smg_compact": 48, "smg_tactical": 48, "shotgun": 12, "sawed_off": 8, "shotgun_auto": 16, "ak47": 60, "m4a1": 60, "hunting_rifle": 10}
const AMMO_REACH := 2.0
const CAVE_AMMO := 24
const CLAIM_FAILURES := {"inventory_full": "Inventário cheio.", "ammo_full": "Munição no limite.", "wallet_full": "Carteira cheia."}
const BUILD_DISTANCE := 110.0
const RELEASE_DISTANCE := 150.0
const AGGRO_DISTANCE := 26.0
const LEASH_DISTANCE := 48.0
const GUNFIRE_DISTANCE := 70.0
const LOOT_DISTANCE := 2.2
## Raio de reserva: flora e chão povoado não nascem dentro do lugar.
const SITE_RADIUS := 16.0
## A caverna de 20/10 é um morro de ~22 x 20 m com pedras soltas em volta.
const CAVE_RADIUS := 19.0
## Pontos achados por varredura com as mesmas reservas dos enfeites do deserto
## (DesertRegion._decoration_clear, 22 m, longe de estrada e em chão plano).
const SITES := [
	{"id": "homestead_salt", "kind": "homestead", "center": Vector2(-360, -485), "yaw": 0.4},
	{"id": "homestead_mesa", "kind": "homestead", "center": Vector2(-900, -485), "yaw": 2.6},
	{"id": "homestead_dry", "kind": "homestead", "center": Vector2(0, -710), "yaw": -1.2},
	{"id": "homestead_well", "kind": "homestead", "center": Vector2(-1240, -850), "yaw": 1.5},
	{"id": "outlaws_ridge", "kind": "outlaws", "center": Vector2(-1180, -1130), "yaw": 1.1},
	{"id": "outlaws_wash", "kind": "outlaws", "center": Vector2(12, -1180), "yaw": -0.6},
	{"id": "outlaws_flats", "kind": "outlaws", "center": Vector2(-600, -470), "yaw": 3.0},
	{"id": "outlaws_dunes", "kind": "outlaws", "center": Vector2(-370, -1170), "yaw": 0.3},
	{"id": "cave_coyote", "kind": "cave", "center": Vector2(-1210, -940), "yaw": 0.9, "loot": "weapon", "weapon": "shotgun",
		"note": "Riscado na pedra: \"O cobre não saiu pela estrada. Desceu o leito seco, para o sul.\""},
	{"id": "cave_vulture", "kind": "cave", "center": Vector2(-480, -865), "yaw": -2.2, "loot": "cash", "amount": 420,
		"note": "Uma lata enferrujada com dinheiro e um bilhete: \"Se eu não voltar, é seu. — L.\""},
	{"id": "cave_whisper", "kind": "cave", "center": Vector2(-360, -1010), "yaw": 1.8, "loot": "cash", "amount": 260,
		"note": "Marcas de giz contam dias. Alguém morou aqui por muito tempo."},
	{"id": "cave_sun", "kind": "cave", "center": Vector2(-280, -470), "yaw": 0.2, "loot": "weapon", "weapon": "smg",
		"note": "Uma caixa de munição militar, sem número de série."},
	# Cratera do meteoro (26/10, carta do mundo 2.0): a caverna fica no meio de um anel de rocha
	# queimada (CaveBuild._crater), que pede uma reserva maior. Ponto achado por
	# tests/tools/sweep_desert_wilds_site.gd no oeste vazio; boca virada para a arrancada.
	{"id": "cave_crater", "kind": "cave", "center": Vector2(-980, -790), "yaw": 1.3, "loot": "cash", "amount": 650, "radius": 27.0, "title": "Cratera",
		"note": "Você solta da rocha queimada um punhado de cristais azuis. Valem R$ 650."},
	# A caverna do Vicente (20/10): fora do mapa e da torre até a décima carta; dentro, sob a lona,
	# o Coyote 440 dos irmãos. "Ao sul do leito seco", como diz o risco na caverna do coiote.
	{"id": "cave_brother", "kind": "cave", "center": Vector2(-1030, -1050), "yaw": 0.3, "loot": "car", "secret": true,
		"note": "No chaveiro, uma foto gasta: dois meninos na mureta do canal. Atrás, a letra do Vicente: \"Ele ainda acelera do mesmo jeito. Cuida dele.\""},
]
var session
var sites: Dictionary = {}
var _clock := 0.0
static var _enabled := -1

static func enabled() -> bool:
	if _enabled < 0: _enabled = 0 if OS.get_environment("GETECO_DESERT_WILDS") == "0" else 1
	return _enabled == 1

## Usado por DesertRegion._decoration_clear para não pôr cacto dentro de casa ou caverna.
static func reserved(point: Vector2, radius := 0.0) -> bool:
	# Os lugares da beira de estrada usam a mesma reserva (e têm o próprio interruptor).
	if preload("res://runtime/desert/roadside/RoadsideLayout.gd").reserved(point, radius): return true
	if not enabled(): return false
	for site in SITES:
		if (site.center as Vector2).distance_to(point) < site_radius(site) + radius: return true
	return false

static func site_radius(site: Dictionary) -> float:
	return float(site.get("radius", CAVE_RADIUS if str(site.kind) == "cave" else SITE_RADIUS))

static func ground(point: Vector2) -> Vector3:
	return Vector3(point.x, HM.surface_height(point), point.y)

## O achado passa pelo contrato de recompensa do mundo (Economy.grant_world_reward), como os
## cofres do deserto. Antes ele caía como saque solto: a lata de R$ 420 passava do teto de
## dinheiro solto (300) e era recusada em silêncio, e o "já pegou" era uma variável estática
## perdida a cada abertura do jogo, então o resto voltava sempre (revisão cruzada 18/10).
static func cave_reward(site: Dictionary) -> Dictionary:
	if str(site.get("kind", "")) != "cave": return {}
	var id := "desert_wilds_" + str(site.id)
	if str(site.get("loot", "")) == "weapon": return {"id": id, "kind": "weapon", "item": str(site.weapon), "ammo": CAVE_AMMO}
	if str(site.get("loot", "")) == "car": return {"id": id, "kind": "car"}
	return {"id": id, "kind": "cash", "amount": int(site.amount)}

static func cave_claimed(economy, site: Dictionary) -> bool:
	var reward := cave_reward(site)
	return not reward.is_empty() and economy.has_reward_receipt(str(reward.id))

## Arma que o jogador já tem vira munição (como o saque do chão); o recibo de valor zero
## marca o achado do mesmo jeito. Falha (bolso cheio, munição no limite) não marca nada:
## o jogador pode voltar depois.
static func claim_cave(economy, site: Dictionary) -> Dictionary:
	var reward := cave_reward(site)
	if reward.is_empty(): return {"ok": false, "reason": "invalid_reward", "changed": false}
	var result: Dictionary = economy.grant_world_reward(reward)
	if result.ok or str(result.get("reason", "")) != "already_owned": return result
	if economy.has_reward_receipt(str(reward.id)): return {"ok": true, "reason": "already_applied", "changed": false}
	if not economy.add_ammo(str(reward.item), CAVE_AMMO): return {"ok": false, "reason": "ammo_full", "changed": false}
	if not economy.grant_reward(str(reward.id), 0): return {"ok": false, "reason": "grant_failed", "changed": false}
	return {"ok": true, "reason": "ammo", "changed": true}

func configure(owner_session) -> void:
	session = owner_session
	name = "DesertWilds"
	# Antes do deserto no quadro: no quadro em que um lugar monta, o enfeite dele pode ceder a vez.
	process_priority = -1
	if session.world.gameplay.has_signal("weapon_fired"): session.world.gameplay.weapon_fired.connect(_gunfire)

func _outside() -> bool:
	return is_instance_valid(session) and session.ready_for_play and session.state.region_id == "desert" and session.state.place_id.is_empty()

func _process(delta: float) -> void:
	_cave_roofs()
	_clock += delta
	if _clock < .3: return
	_clock = 0.0
	if not enabled() or not _outside():
		release_all()
		return
	var player: Vector3 = session.world.player.global_position
	var planar := Vector2(player.x, player.z)
	var region: Node3D = session.controller.regions.get("desert")
	var built_one := false
	for site in SITES:
		var id: String = site.id
		var distance := planar.distance_to(site.center)
		if sites.has(id):
			if distance > RELEASE_DISTANCE: _release(id)
			else: _update_site(site, sites[id], planar)
		# Espera só as superfícies, não o enfeite fatiado: com is_streaming_idle(), a 60 fps os
		# foras-da-lei de outlaws_flats (perto da arrancada) nasciam até ~27 s depois da chegada.
		elif not built_one and distance < BUILD_DISTANCE and is_instance_valid(region) and region.surfaces_idle():
			if not region.prepare_collision_at(ground(site.center)): continue
			region.yield_dressing_this_frame()
			var trace := STALL_WORK.begin()
			sites[id] = _build(site)
			STALL_WORK.finish_slow("desert.wilds.build", trace, 2000)
			built_one = true

func _build(site: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = "Wilds_" + str(site.id)
	root.position = ground(site.center)
	root.rotation.y = float(site.yaw)
	add_child(root)
	var record := {"root": root, "actors": [], "engaged": false}
	match str(site.kind):
		"homestead": _homestead(root, record, site)
		"outlaws": _outlaws(root, record, site)
		"cave": _cave(root, record, site)
	G.batch_repeated_meshes(root)
	return record

# --- Casinha -------------------------------------------------------------------------------

func _homestead(root: Node3D, record: Dictionary, site: Dictionary) -> void:
	var wall := Color("a48a68")
	var trim := Color("6e5a43")
	# Casa de 6 x 5 m de adobe, porta na frente (+z) e telhado de chapa com beiral.
	G.box(root, "BackWall", Vector3(0, 1.4, -2.5), Vector3(6.2, 2.8, .3), wall, true)
	for side in [-1.0, 1.0]:
		G.box(root, "SideWall", Vector3(side * 3.0, 1.4, 0), Vector3(.3, 2.8, 5.0), wall.darkened(.06), true)
		G.box(root, "FrontWall", Vector3(side * 1.95, 1.4, 2.5), Vector3(2.3, 2.8, .3), wall, true)
		G.box(root, "Window", Vector3(side * 1.9, 1.55, 2.66), Vector3(.9, .7, .04), Color("2c3236"))
		G.box(root, "WindowFrame", Vector3(side * 1.9, 1.15, 2.68), Vector3(1.05, .08, .06), trim)
	G.box(root, "Lintel", Vector3(0, 2.55, 2.5), Vector3(1.6, .5, .3), wall, true)
	G.box(root, "DoorShadow", Vector3(0, 1.15, 2.36), Vector3(1.1, 2.3, .05), Color("1f1c19"))
	G.box(root, "Roof", Vector3(0, 2.95, .3), Vector3(7.2, .14, 6.6), Color("7d7468"), true)
	# Varanda: esteios, banco e tonel de água; varal com roupa ao lado.
	for x in [-3.2, 3.2]: G.box(root, "PorchPost", Vector3(x, 1.45, 3.4), Vector3(.14, 2.9, .14), trim, true)
	G.box(root, "PorchBench", Vector3(-1.9, .45, 3.3), Vector3(1.6, .12, .45), trim, true)
	G.cylinder(root, "WaterTank", Vector3(4.4, .8, -1.6), .7, 1.6, Color("6f7468"), true)
	for x in [5.0, 9.0]: G.cylinder(root, "LinePole", Vector3(x, 1.0, 2.0), .05, 2.0, trim, true)
	for i in 3: G.box(root, "Laundry", Vector3(5.8 + float(i) * 1.1, 1.55, 2.0), Vector3(.7, .6, .03), [Color("b8483c"), Color("d9cfb0"), Color("4a6d8c")][i])
	G.box(root, "Firewood", Vector3(-4.2, .35, -1.0), Vector3(.9, .7, 1.8), Color("6a5136"), true)
	# Dois moradores: um lê na varanda, outro cozinha no fogareiro do quintal.
	var identity := absi(hash(site.id))
	_admit_resident(root, record, Vector3(-1.9, 0, 4.0), PI, "read", identity)
	G.box(root, "Stove", Vector3(2.0, .45, 5.4), Vector3(.8, .9, .6), Color("3d3a36"), true)
	_admit_resident(root, record, Vector3(2.0, 0, 4.6), 0.0, "cook", identity + 1)

func _admit_resident(root: Node3D, record: Dictionary, local: Vector3, yaw: float, activity: String, identity: int) -> void:
	var world_point := root.global_transform * local
	world_point.y = HM.surface_height(Vector2(world_point.x, world_point.z)) + .06
	var resident := RESIDENT.new()
	resident.specification = {"name": "Morador", "activity": activity, "appearance": {"variant": 20000 + identity % 9000,
		"female": identity % 2 == 0, "coat": ["8a6a4c", "5f6f5a", "9a5d45", "6c6a63"][identity % 4], "pants": "4a4238"}}
	root.add_child(resident)
	resident.global_position = world_point
	resident.rotation.y = root.rotation.y + yaw
	record.actors.append(resident)

# --- Foras-da-lei ----------------------------------------------------------------------------

func _outlaws(root: Node3D, record: Dictionary, site: Dictionary) -> void:
	# Lona esticada, caixas roubadas, fogueira apagada e uma moto encostada: acampamento de passagem.
	for x in [-3.0, 3.0]:
		for z in [-2.0, 2.0]: G.cylinder(root, "TarpPole", Vector3(x, 1.25, z), .06, 2.5, Color("5c4d3b"), true)
	G.box(root, "Tarp", Vector3(0, 2.5, 0), Vector3(6.6, .05, 4.6), Color("7c6a4e"))
	for row in [Vector3(-2.0, .45, -1.2), Vector3(-1.0, .45, -1.4), Vector3(-1.5, 1.35, -1.3)]:
		G.box(root, "StolenCrate", row, Vector3(.95, .9, .85), Color("6f5a40"), true)
	G.cylinder(root, "FirePit", Vector3(1.2, .1, 1.2), .65, .2, Color("38332e"), true)
	for i in 4: G.box(root, "Log", Vector3(1.2 + cos(float(i) * 1.6) * .9, .18, 1.2 + sin(float(i) * 1.6) * .9), Vector3(.9, .25, .25), Color("5a4430"), true).rotation.y = float(i) * 1.6
	G.box(root, "Bedroll", Vector3(2.2, .1, -1.0), Vector3(.8, .2, 1.8), Color("4f5a4c"))
	for i in 3:
		var angle := float(i) * TAU / 3.0 + .5
		var local := Vector3(cos(angle) * 5.0, 0, sin(angle) * 5.0)
		var world_point := root.global_transform * local
		world_point.y = HM.surface_height(Vector2(world_point.x, world_point.z)) + .06
		var actor := Outlaw.new()
		actor.coordinator = self
		actor.site_id = str(site.id)
		actor.configure(session.world.gameplay, i)
		actor.uniform_tones = [Color(0.52, 0.42, 0.30), Color(0.40, 0.36, 0.30), Color(0.33, 0.30, 0.28)]
		root.add_child(actor)
		actor.global_position = world_point
		actor.rotation.y = angle + PI
		record.actors.append(actor)

func _update_site(site: Dictionary, record: Dictionary, planar: Vector2) -> void:
	match str(site.kind):
		"outlaws":
			var target: Node3D = session.world.gameplay.pursuit_target()
			var center: Vector2 = site.center
			var target_planar := Vector2(target.global_position.x, target.global_position.z)
			if center.distance_to(target_planar) > LEASH_DISTANCE: record.engaged = false
			elif not record.engaged:
				for actor in record.actors:
					if is_instance_valid(actor) and not actor.dead and actor.global_position.distance_to(target.global_position) <= AGGRO_DISTANCE and session.world.gameplay.police_can_see(actor):
						record.engaged = true
						break
			for actor in record.actors:
				if is_instance_valid(actor) and not actor.dead:
					actor.engaged = record.engaged
					if record.engaged: actor.alerted = true
		"cave":
			if str(site.get("loot", "")) == "car":
				_update_brother(site, record, planar)
				return
			if record.get("claimed", false) or not record.has("loot_point"): return
			var at: Vector3 = record.loot_point
			if Vector2(at.x, at.z).distance_to(planar) > LOOT_DISTANCE:
				record.notified = false
				return
			# Uma tentativa (e um aviso de falha) por aproximação, não a cada tique.
			if record.get("notified", false) or session.world.gameplay.health <= 0: return
			record.notified = true
			var result := claim_cave(session.state.economy, site)
			if not result.ok:
				session.show_message(str(CLAIM_FAILURES.get(str(result.get("reason", "")), "Não foi possível concluir a coleta.")))
				return
			record.claimed = true
			if result.get("changed", false): REWARD_AUDIO.play(session, REWARD_AUDIO.kind_for_reward(str(cave_reward(site).kind)))
			session.show_message(str(site.note))
			session.save_game()

func _gunfire(_weapon: String, origin: Vector3) -> void:
	if not _outside(): return
	for site in SITES:
		if site.kind != "outlaws" or not sites.has(site.id): continue
		if (site.center as Vector2).distance_to(Vector2(origin.x, origin.z)) < GUNFIRE_DISTANCE: sites[site.id].engaged = true

func save_block_reason() -> String:
	for record in sites.values():
		if not record.engaged: continue
		for actor in record.actors:
			if is_instance_valid(actor) and not actor.dead: return "Afaste-se dos foras-da-lei antes de salvar."
	return ""

# --- Caverna ---------------------------------------------------------------------------------

## Morro da caverna some com o jogador dentro (a câmera de cima vê o salão em corte); todo quadro,
## como os cômodos da Estrada do Sal, para a troca não atrasar ao passar pela boca.
func _cave_roofs() -> void:
	if sites.is_empty() or not is_instance_valid(session) or not session.ready_for_play: return
	var player: Vector3 = session.world.player.global_position
	for record in sites.values():
		var roofs: Node3D = record.get("roofs")
		if not is_instance_valid(roofs): continue
		var local := (record.root as Node3D).to_local(player)
		var inside := false
		if local.y < CAVE.CEILING:
			for rect: Rect2 in roofs.get_meta("walk_in", []):
				if rect.grow(.4).has_point(Vector2(local.x, local.z)):
					inside = true
					break
		if roofs.visible == inside: roofs.visible = not inside

func _cave(root: Node3D, record: Dictionary, site: Dictionary) -> void:
	# Morro de arenito com túnel, salão e salão dos fundos (CaveBuild, assado uma vez por caverna,
	# sob a cortina pelo pré-aquecimento da beira de estrada). O morro vai num nó próprio que some
	# com o jogador dentro; a fogueira tem a luz da beira de estrada (só à noite, no LightBudget).
	var kind := "cave:" + str(site.id)
	ART.instantiate(root, BUILD.baked(kind))
	var roofs := Node3D.new()
	roofs.name = "CaveMass"
	root.add_child(roofs)
	ART.instantiate(roofs, BUILD._baked[kind + ":roofs"])
	roofs.set_meta("walk_in", CAVE.cavity(str(site.id)))
	record.roofs = roofs
	BUILD._lamp(root, CAVE.fire_point(str(site.id)) + Vector3(0, .4, 0), Color("ffb46a") if CAVE.garage(str(site.id)) else Color("ff9a4a"), 9.0, 2.2)
	if CAVE.garage(str(site.id)) and not cave_claimed(session.state.economy, site):
		# Lona por cima do carro, presa com corrente: some quando as dez cartas estão achadas.
		var tarp := G.box(root, "VicenteTarp", CAVE.CAR_POINT + Vector3(0, .7, 0), Vector3(2.2, 1.4, 4.9), Color("4d5a3c"), true)
		G.box(tarp, "TarpFold", Vector3(0, .72, 0), Vector3(1.7, .06, 4.2), Color("3f4a31"))
		record.tarp = tarp
	record.loot_point = root.global_transform * CAVE.loot_point(str(site.id))
	record.claimed = cave_claimed(session.state.economy, site)

## Caverna do Vicente: sem as dez cartas, só a lona com cadeado (e um aviso por aproximação); com
## elas, a lona sai e o Coyote fica ali parado. Entrar nele é o achado: vira carro do jogador (frota
## do deserto, mesma via do Supra do Takeshi) com as peças que o Vicente deixou montadas.
func _update_brother(site: Dictionary, record: Dictionary, planar: Vector2) -> void:
	if record.get("claimed", false): return
	var letters := LETTERS.complete(session.state.economy.snapshot().collectibles)
	var root: Node3D = record.root
	var spot: Vector3 = root.global_transform * CAVE.CAR_POINT
	if not letters:
		if Vector2(spot.x, spot.z).distance_to(planar) > 3.6:
			record.notified = false
			return
		if record.get("notified", false): return
		record.notified = true
		session.show_message("Uma lona sobre algo do tamanho de um carro, presa com corrente e cadeado. Riscados na pedra, dez traços.")
		return
	var car: Variant = record.get("car")
	if not is_instance_valid(car):
		if is_instance_valid(record.get("tarp")): record.tarp.queue_free()
		car = session.controller.spawn_vehicle(LETTERS.CAR_ARCHETYPE, spot + Vector3(0, .15, 0), root.rotation.y + CAVE.CAR_YAW)
		if not is_instance_valid(car): return
		car.paint_color = Color(LETTERS.CAR_PAINT)
		car.set_meta("vicente_gift", true)
		record.car = car
		return
	if not session.world.driving.occupied or session.world.driving.car != car: return
	if not session.state.economy.grant_reward(LETTERS.CAR_RECEIPT, 0): return
	car.vehicle_id = LETTERS.CAR_ID
	var world: Dictionary = session.state.world_state
	if not world.has("desert_fleet"): world.desert_fleet = {}
	world.desert_fleet[LETTERS.CAR_ID] = FLEET_STATE.capture(car, session.state.region_id)
	var garage: Dictionary = GARAGE_STATE.data(world)
	garage.vehicles[LETTERS.CAR_ID] = {"archetype": LETTERS.CAR_ARCHETYPE, "parts": LETTERS.CAR_PARTS.duplicate(), "owned": LETTERS.CAR_PARTS.values(), "presets": {}, "vicente_gift": true}
	world.desert_garage = garage
	ADAPTER.attach(car, LETTERS.CAR_PARTS)
	if session.desert != null and session.desert.has_method("_track_owned"): session.desert._track_owned(car)
	record.claimed = true
	REWARD_AUDIO.play(session, "collectible")
	session.show_dialogue([{"speaker": "Coyote 440 do Vicente", "message": str(site.note)}])
	session.save_game()

## Caixa de munição das cavernas (a pé, perto da pilha de caixotes do acampamento).
func nearest_action() -> Dictionary:
	if sites.is_empty() or not is_instance_valid(session) or session.modal or session.world.driving.occupied: return {}
	var player: Vector3 = session.world.player.global_position
	for site in SITES:
		if str(site.kind) != "cave" or CAVE.garage(str(site.id)) or not sites.has(site.id): continue
		var record: Dictionary = sites[site.id]
		var crate: Vector3 = (record.root as Node3D).global_transform * CAVE.ammo_point(str(site.id))
		if Vector2(crate.x, crate.z).distance_to(Vector2(player.x, player.z)) <= AMMO_REACH and absf(player.y - crate.y) < 2.0:
			return {"id": "desert_roadside", "target": "cave_ammo:" + str(site.id), "label": "Pegar munição da caixa", "provider": self}
	return {}

func perform(action: Dictionary) -> bool:
	var target := str(action.get("target", ""))
	if not target.begins_with("cave_ammo:") or nearest_action().get("target", "") != target: return false
	return take_ammo(target.trim_prefix("cave_ammo:"))

func take_ammo(id: String) -> bool:
	var day: int = session.weather.moon_day()
	var world: Dictionary = session.state.world_state
	var state: Dictionary = world.get("desert_cave_ammo", {}).duplicate()
	if int(state.get(id, -1)) == day:
		session.show_message("A caixa está vazia. Alguém repõe de madrugada.")
		return true
	var economy = session.state.economy
	var got: Array[String] = []
	for weapon in AMMO_REFILL:
		if not economy.snapshot().weapons.has(weapon): continue
		if economy.add_ammo(weapon, int(AMMO_REFILL[weapon])): got.append("%s +%d" % [weapon, int(AMMO_REFILL[weapon])])
	if got.is_empty():
		session.show_message("Munição de vários calibres, mas nenhuma serve: você não tem arma de fogo ou já está no limite.")
		return true
	state[id] = day
	world.desert_cave_ammo = state
	REWARD_AUDIO.play(session, "pickup")
	session.show_message(String(TranslationServer.translate("Munição da caixa: %s.")) % ", ".join(got))
	session.save_game()
	return true

# --- Ciclo de vida --------------------------------------------------------------------------

func _release(id: String) -> void:
	var record: Dictionary = sites.get(id, {})
	sites.erase(id)
	# Coyote ainda não levado volta para debaixo da lona na próxima visita.
	var car: Variant = record.get("car")
	if is_instance_valid(car) and not record.get("claimed", false) and not (is_instance_valid(session) and session.world.driving.car == car): car.queue_free()
	for actor in record.get("actors", []):
		if is_instance_valid(actor):
			actor.set_physics_process(false)
			actor.collision_layer = 0
			actor.collision_mask = 0
	if is_instance_valid(record.get("root")): record.root.queue_free()

func release_all() -> void:
	for id in sites.keys(): _release(id)

func _exit_tree() -> void:
	release_all()

class Outlaw extends "res://gameplay/CobraAgent.gd":
	var coordinator: Node3D
	var site_id := ""

	func _ready() -> void:
		super._ready()
		add_to_group("desert_outlaws")
		set_meta("region_id", "desert")
		set_meta("character_name", "Fora-da-lei")
		engaged = false
