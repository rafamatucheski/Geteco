extends Node3D
## Vida no meio do nada (playtest 18/10: "o deserto é muito vazio"). Casinhas com morador,
## acampamentos de foras-da-lei e cavernas com um achado, espalhados longe das estradas.
## Como o DesertBanditEncounter, cada lugar só existe perto do jogador: monta a ~110 m (um por
## passo, com o streaming parado) e solta a ~150 m. Quem morre volta na próxima visita; o achado
## da caverna sai uma vez por save, com recibo na carteira (ver claim_cave).
## GETECO_DESERT_WILDS=0 desliga tudo (A/B no mesmo export).
const G := preload("res://world/desert/DesertGeometry.gd")
const HM := preload("res://world/desert/DesertTerrainMesh.gd")
const COVER := preload("res://world/desert/DesertGroundCover.gd")
const RESIDENT := preload("res://runtime/desert/DesertVillageResident.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const REWARD_AUDIO := preload("res://gameplay/RewardAudio.gd")
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
## Pontos achados por varredura com as mesmas reservas dos enfeites do deserto
## (DesertRegion._decoration_clear, 22 m, longe de estrada e em chão plano).
const SITES := [
	{"id": "homestead_salt", "kind": "homestead", "center": Vector2(-360, -650), "yaw": 0.4},
	{"id": "homestead_mesa", "kind": "homestead", "center": Vector2(-1040, -770), "yaw": 2.6},
	{"id": "homestead_dry", "kind": "homestead", "center": Vector2(40, -1050), "yaw": -1.2},
	{"id": "homestead_well", "kind": "homestead", "center": Vector2(-1360, -1210), "yaw": 1.5},
	{"id": "outlaws_ridge", "kind": "outlaws", "center": Vector2(-1320, -1810), "yaw": 1.1},
	{"id": "outlaws_wash", "kind": "outlaws", "center": Vector2(40, -1890), "yaw": -0.6},
	{"id": "outlaws_flats", "kind": "outlaws", "center": Vector2(-880, -1130), "yaw": 3.0},
	{"id": "outlaws_dunes", "kind": "outlaws", "center": Vector2(200, -1410), "yaw": 0.3},
	{"id": "cave_coyote", "kind": "cave", "center": Vector2(-1120, -1410), "yaw": 0.9, "loot": "weapon", "weapon": "shotgun",
		"note": "Riscado na pedra: \"O cobre não saiu pela estrada. Desceu o leito seco, para o sul.\""},
	{"id": "cave_vulture", "kind": "cave", "center": Vector2(-600, -1410), "yaw": -2.2, "loot": "cash", "amount": 420,
		"note": "Uma lata enferrujada com dinheiro e um bilhete: \"Se eu não voltar, é seu. — L.\""},
	{"id": "cave_whisper", "kind": "cave", "center": Vector2(-360, -1690), "yaw": 1.8, "loot": "cash", "amount": 260,
		"note": "Marcas de giz contam dias. Alguém morou aqui por muito tempo."},
	{"id": "cave_sun", "kind": "cave", "center": Vector2(-280, -810), "yaw": 0.2, "loot": "weapon", "weapon": "smg",
		"note": "Uma caixa de munição militar, sem número de série."},
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
	if not enabled(): return false
	for site in SITES:
		if (site.center as Vector2).distance_to(point) < SITE_RADIUS + radius: return true
	return false

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
	if session.world.gameplay.has_signal("weapon_fired"): session.world.gameplay.weapon_fired.connect(_gunfire)

func _outside() -> bool:
	return is_instance_valid(session) and session.ready_for_play and session.state.region_id == "desert" and session.state.place_id.is_empty()

func _process(delta: float) -> void:
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
		elif not built_one and distance < BUILD_DISTANCE and is_instance_valid(region) and region.is_streaming_idle():
			if not region.prepare_collision_at(ground(site.center)): continue
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

func _cave(root: Node3D, record: Dictionary, site: Dictionary) -> void:
	# Morro de pedra com um salão de ~7 x 8 m por dentro; a boca fica na frente (+z). Pedras grandes
	# usam a mesma malha facetada do chão do deserto (sem shader novo); a colisão é por caixa.
	var stone: Mesh = COVER.meshes()[2]
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash(site.id))
	var ring := 14
	for i in ring:
		var angle := float(i) / float(ring) * TAU
		# Deixa a boca aberta em torno de +z (ângulo PI/2 no círculo xz).
		if absf(wrapf(angle - PI * .5, -PI, PI)) < .42: continue
		var radius := 4.6 + rng.randf_range(-.3, .4)
		var at := Vector3(cos(angle) * radius, 1.4, sin(angle) * radius)
		var size := Vector3(rng.randf_range(2.6, 3.4), rng.randf_range(3.4, 4.2), rng.randf_range(2.2, 2.8))
		_rock(root, stone, at, size, angle, rng)
	# Teto e topo do morro: lajes por cima do salão, pedras soltas em cima para o contorno.
	# A laje fica escondida dentro das pedras do topo; só a colisão e a sombra do salão contam.
	G.box(root, "CaveCeiling", Vector3(0, 3.3, 0), Vector3(7.6, .6, 7.6), Color("5d5245"), true)
	for i in 9:
		var angle := float(i) / 9.0 * TAU + rng.randf_range(-.2, .2)
		_rock(root, stone, Vector3(cos(angle) * 3.6, 3.7, sin(angle) * 3.6), Vector3(3.6, 2.4, 3.2), angle, rng)
	for i in 4:
		var angle := float(i) * 1.57 + .4
		_rock(root, stone, Vector3(cos(angle) * 1.5, 4.3, sin(angle) * 1.5), Vector3(3.4, 2.2, 3.2), angle, rng)
	_rock(root, stone, Vector3(0, 5.0, 0), Vector3(4.0, 2.4, 3.8), 0.0, rng)
	# Ombreiras da boca, mais altas, para ler como entrada de longe.
	for side in [-1.0, 1.0]: _rock(root, stone, Vector3(side * 1.9, 1.6, 4.6), Vector3(1.8, 3.8, 2.2), side, rng)
	G.box(root, "CaveFloor", Vector3(0, .03, -.5), Vector3(7.6, .06, 7.6), Color("5d5245"))
	# O achado no fundo: caixote, lampião apagado e ossos de animal.
	var crate := G.box(root, "HiddenCrate", Vector3(0, .35, -2.6), Vector3(1.0, .7, .7), Color("5f4a33"), true)
	G.box(crate, "CrateLid", Vector3(0, .38, 0), Vector3(1.05, .06, .75), Color("4e3c29"))
	G.cylinder(root, "OldLantern", Vector3(.85, .2, -2.4), .1, .32, Color("3f3a33"))
	for i in 3: G.box(root, "Bone", Vector3(-1.6 + float(i) * .3, .05, -1.4 + float(i) * .2), Vector3(.45, .06, .08), Color("cfc4a8")).rotation.y = float(i) * .9
	record.loot_point = root.global_transform * Vector3(0, .1, -1.8)
	record.claimed = cave_claimed(session.state.economy, site)

func _rock(root: Node3D, mesh: Mesh, at: Vector3, size: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var rock := MeshInstance3D.new()
	rock.name = "CaveRock"
	rock.mesh = mesh
	rock.material_override = COVER.material()
	rock.position = at
	rock.rotation = Vector3(rng.randf_range(-.12, .12), yaw + rng.randf_range(-.3, .3), rng.randf_range(-.12, .12))
	# A malha tem ~1,2 m de diâmetro e 0,9 m de altura.
	rock.scale = Vector3(size.x / 1.2, size.y / .9, size.z / 1.05)
	root.add_child(rock)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size * .82
	shape.shape = box
	body.add_child(shape)
	body.position = at
	body.rotation.y = rock.rotation.y
	root.add_child(body)

# --- Ciclo de vida --------------------------------------------------------------------------

func _release(id: String) -> void:
	var record: Dictionary = sites.get(id, {})
	sites.erase(id)
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
