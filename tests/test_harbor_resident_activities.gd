extends SceneTree
## Rework 15/10/2026: atividades variadas dos moradores (sentar, dormir na
## cama, passear, conversar em dupla) num andar real com móveis e física, e os
## estilos de reação a ameaça (fugir, esconder, ligar, encarar, paralisar,
## implorar) com sorteio ponderado por temperamento. Sem medir desempenho.
const CATALOG := preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const PLACE := preload("res://world/places/harbor_buildings/HarborBuildingPlace.gd")
const CONTENT := preload("res://world/places/harbor_buildings/HarborBuildingContent.gd")
const OCCUPANTS := preload("res://world/places/harbor_buildings/HarborBuildingOccupants.gd")
const RESIDENT := preload("res://world/places/harbor_buildings/HarborBuildingResident.gd")
const REACTION := preload("res://gameplay/civilian_reactions/WorkplaceThreatReaction.gd")
const DIRECTOR := preload("res://gameplay/police_response/PoliceCaseDirector.gd")
var checks := 0
var failures: Array[String] = []

class State extends RefCounted:
	var place_id := "activity_test_room"
	var region_id := "harbor"
	func weapons_allowed() -> bool: return true

class Gameplay extends Node3D:
	signal weapon_fired(id: String, point: Vector3)
	signal npc_gunfire(point: Vector3, direction: Vector3, shooter: Node3D)
	signal explosion_occurred(point: Vector3, radius: float, source: Node)
	signal changed
	var player: Node3D
	var state := State.new()
	var health := 100.0
	var stars := 0
	var contact_age := 0.0
	var world: Node3D
	var police_case: Node
	var aim_active := false
	var weapon := "fists"
	var points := 0
	var emergency: Node
	var direction := Vector3.RIGHT
	func equipped() -> String: return weapon
	func weapon_data(id: String) -> Dictionary: return {"is_melee":id == "fists"}
	func _aim_direction() -> Vector3: return direction
	func report_observed_crime(amount: int, point: Vector3, kind: String, victim: Node3D = null) -> bool:
		return police_case.observe(amount, point, kind, victim)
	func register_crime(amount: int, _point: Vector3, _kind: String, _testimony: Dictionary = {}) -> void:
		points += amount
		stars = 1
	func report_contact(_point: Vector3) -> void: pass

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	print("RESIDENT_ACTIVITY ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
	return value

func solid(parent: Node, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	parent.add_child(body)
	return body

func _bed_floor() -> Dictionary:
	for definition in CATALOG.definitions():
		for floor_index in int(definition.floor_count):
			var spec := CONTENT.floor_spec(definition, floor_index)
			if spec.compact or spec.program not in CONTENT.BED_PROGRAMS or spec.occupants.size() < 2: continue
			return {"definition":definition, "floor":floor_index, "spec":spec}
	return {}

func run() -> void:
	create_timer(240).timeout.connect(func(): print("RESIDENT_ACTIVITY timeout"); quit(3))
	await _styles_are_weighted()
	await _real_floor_activities()
	await _reaction_styles()
	print(JSON.stringify({"test":"harbor_resident_activities", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _styles_are_weighted() -> void:
	var reaction := REACTION.new()
	var weights := {"flee":3.0, "hide":1.0, "freeze":2.0, "beg":4.0}
	reaction.styles = weights
	var counts := {}
	seed(4021)
	for index in 4000:
		reaction._choose_style()
		counts[reaction.style] = int(counts.get(reaction.style, 0)) + 1
	var total := 10.0
	var within := true
	for style in weights:
		var expected: float = weights[style] / total
		var actual := float(counts.get(style, 0)) / 4000.0
		if absf(actual - expected) > .035: within = false
	check(counts.size() == 4 and within, "sorteio por incidente segue os pesos do temperamento %s" % str(counts))
	reaction.styles = {}
	reaction._choose_style()
	check(reaction.style == "flee" and reaction.retreat_distance == REACTION.RETREAT_DISTANCE, "sem pesos mantém o recuo original")
	reaction.free()
	# Pessoas diferentes do mesmo prédio não reagem com os mesmos pesos.
	var profiles := {}
	var temperaments := {}
	for definition in CATALOG.definitions():
		for floor_index in int(definition.floor_count):
			for station in CONTENT.floor_spec(definition, floor_index).occupants:
				profiles[JSON.stringify(station.reactions)] = true
				temperaments[station.temperament] = true
	check(profiles.size() > 60 and temperaments.size() == 4, "perfis de reação variados: %d perfis, temperamentos %s" % [profiles.size(), temperaments.keys()])

func _real_floor_activities() -> void:
	var found := _bed_floor()
	if not check(not found.is_empty(), "existe andar residencial com cama e dois moradores"): return
	var definition: Dictionary = found.definition
	var floor_index: int = found.floor
	var room = PLACE.new()
	room.definition = definition.duplicate(true)
	room.floor_index = floor_index
	root.add_child(room)
	await physics_frame
	await physics_frame
	var floor_room: Node3D = room.floor_room
	var spec: Dictionary = found.spec
	var station: Vector3 = spec.occupants[1].position
	# Dormir: ponto livre ao lado da cama, corpo deitado sobre o colchão.
	var bed: Dictionary = OCCUPANTS._bed_side(floor_room, station)
	if check(not bed.is_empty(), "cama real com lado livre para deitar (%s)" % definition.id):
		var sleeper := RESIDENT.new()
		sleeper.specification = {"id":"sleeper", "identity":11, "activity":"sleep"}
		sleeper.position = bed.point
		sleeper.sleep_bed = floor_room.global_transform * bed.bed
		floor_room.add_child(sleeper)
		sleeper.configure_social(null, null, false)
		for frame in 6: await physics_frame
		await process_frame
		check(floor_room.is_floor_clear(bed.point, .34), "ponto de deitar/levantar fica em piso livre")
		check(sleeper.sleeping and sleeper.collision_layer == 0, "quem dorme não deixa cápsula invisível ao lado da cama")
		var lying: Vector3 = floor_room.to_local(sleeper.visual.global_position)
		var top: Vector3 = (bed.bed as Transform3D).origin
		var on_mattress := false
		for bounds: AABB in floor_room.solid_bounds:
			if Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z).has_point(Vector2(lying.x, lying.z)) and bounds.size.y < 2.0: on_mattress = true
		check(on_mattress and absf(lying.y - top.y - .13) < .05, "corpo deitado sobre o colchão (%s, topo %.2f)" % [str(lying), top.y])
		check(sleeper.visual.global_basis.y.dot(Vector3.UP) < .1, "corpo na horizontal")
		check(not sleeper.test_move(sleeper.global_transform, Vector3.UP * .002), "cápsula ao lado da cama não invade a cama")
		sleeper.wake()
		await physics_frame
		check(not sleeper.sleeping and sleeper.collision_layer == 2 and sleeper.visual.transform.is_equal_approx(Transform3D.IDENTITY), "acordar devolve corpo, colisão e postura de pé")
		check(not sleeper.test_move(sleeper.global_transform, Vector3.UP * .002), "levanta em espaço livre")
		sleeper.free()
	# Sentar: banquinho dentro da cápsula, pose sentada nativa.
	var sitter := RESIDENT.new()
	sitter.specification = {"id":"sitter", "identity":5, "activity":"sit_read"}
	sitter.position = station
	floor_room.add_child(sitter)
	sitter.configure_social(null, null, false)
	await create_timer(1.0).timeout
	var inside := true
	for part in sitter.seat.get_children():
		var local: Vector3 = sitter.to_local(part.global_position)
		var half: Vector3 = part.mesh.size * .5
		if Vector2(absf(local.x) + half.x, absf(local.z) + half.z).length() > .36: inside = false
	check(sitter.resident_model.sit_amount > .9 and sitter.seat.visible and inside, "senta num banquinho dentro da própria cápsula")
	check(not sitter.test_move(sitter.global_transform, Vector3.UP * .002), "sentado não invade móveis")
	sitter.free()
	# Passear: pontos livres, segmentos livres e corpo sempre fora dos móveis.
	var claimed: Array[Vector3] = []
	for occupant in spec.occupants: claimed.append(occupant.position)
	var route := OCCUPANTS._wander_route(floor_room, definition, station, claimed)
	check(route.size() >= 2, "rota de passeio com pelo menos dois pontos livres")
	if route.size() >= 2:
		var walker := RESIDENT.new()
		walker.specification = {"id":"walker", "identity":3, "activity":"wander"}
		walker.position = station
		for local in route: walker.wander_points.append(floor_room.to_global(local))
		floor_room.add_child(walker)
		walker.configure_social(null, null, false)
		var start: Vector3 = walker.global_position
		var farthest := 0.0
		var clear := true
		var deadline := Time.get_ticks_msec() + 14000
		while Time.get_ticks_msec() < deadline:
			await physics_frame
			farthest = maxf(farthest, walker.global_position.distance_to(start))
			if not floor_room.is_floor_clear(floor_room.to_local(walker.global_position), .26): clear = false
		check(farthest > .8, "morador caminha pelo cômodo (%.2f m)" % farthest)
		check(clear, "caminhando nunca entra na pegada de móveis")
		check(walker.is_on_floor() and absf(walker.global_position.y - start.y) < .1, "continua apoiado no piso do andar")
		walker.free()
	# Conversa em dupla: um olha para o outro e a fala alterna.
	var a := RESIDENT.new()
	var b := RESIDENT.new()
	a.specification = {"id":"pair_visitor", "identity":21, "activity":"chat"}
	b.specification = {"id":"pair_partner", "identity":22, "activity":"chat"}
	solid(root, Vector3(30.5, -.1, 30), Vector3(6, .2, 6))
	a.position = Vector3(30, .03, 30)
	b.position = Vector3(31.05, .03, 30)
	root.add_child(a)
	root.add_child(b)
	a.chat_partner = b
	b.chat_partner = a
	b.chat_offset = 3.2
	var overlap := 0
	var a_talked := false
	var b_talked := false
	for sample in 28:
		await create_timer(.25).timeout
		var at := str(a.resident_model.activity) == "talk"
		var bt := str(b.resident_model.activity) == "talk"
		a_talked = a_talked or at
		b_talked = b_talked or bt
		if at and bt: overlap += 1
	var facing: Vector3 = a.visual.global_basis.z
	check(a_talked and b_talked and overlap <= 2, "fala alternada na dupla (sobreposição %d)" % overlap)
	check(facing.dot(Vector3.RIGHT) > .8, "parceiro de conversa olha para o outro")
	a.free()
	b.free()
	room.queue_free()
	await process_frame

func _reaction_styles() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var gameplay := Gameplay.new()
	stage.add_child(gameplay)
	var director := DIRECTOR.new()
	director.configure(gameplay)
	gameplay.police_case = director
	gameplay.add_child(director)
	solid(stage, Vector3(0, -.1, 0), Vector3(40, .2, 40))
	var player := CharacterBody3D.new()
	player.position = Vector3(0, .03, 0)
	stage.add_child(player)
	gameplay.player = player
	var index := 0
	for style in ["flee", "hide", "call", "confront", "freeze", "beg"]:
		index += 1
		director.reset()
		var resident := RESIDENT.new()
		resident.specification = {"id":"style_" + style, "identity":40 + index, "activity":"read"}
		resident.position = Vector3(2.4, .03, 0)
		stage.add_child(resident)
		var reaction := REACTION.install(resident, resident.resident_model, gameplay)
		reaction.styles = {style:1.0}
		resident.configure_social(gameplay, reaction, false)
		gameplay.weapon = "pistol"
		await physics_frame
		await physics_frame
		var start: Vector3 = resident.global_position
		reaction._notice(player.global_position, 12.0)
		check(reaction.active and reaction.style == style, style + ": incidente usa o estilo sorteado")
		for frame in 100: await physics_frame
		var moved: float = resident.global_position.distance_to(start)
		var hands: Array = reaction._shield_hands()
		match style:
			"flee": check(moved > 1.4, "flee: foge de verdade (%.2f m)" % moved)
			"hide": check(moved > 1.0 and resident.resident_model.sit_amount > .8, "hide: corre e se agacha (%.2f m)" % moved)
			"call":
				check(director.pending.size() == 1 and director.pending[0].kind == "intimidation", "call: liga para a polícia uma vez, com testemunho pendente")
				check(hands[0] == null and hands[1] is Vector3 and (hands[1] as Vector3).y - resident.global_position.y > 1.45, "call: telefone na orelha")
			"confront":
				var toward: Vector3 = resident.resident_model.global_basis.z
				check(moved < .05 and toward.dot((player.global_position - resident.global_position).normalized()) > .9, "confront: fica e encara o jogador")
			"freeze": check(moved < .05 and (hands[0] as Vector3).y - resident.global_position.y > 1.8, "freeze: paralisado com as mãos para cima")
			"beg": check(moved < .05 and resident.resident_model.sit_amount > .85, "beg: ajoelha e implora sem sair do lugar")
		check(not resident.test_move(resident.global_transform, Vector3.UP * .002), style + ": corpo continua fora de sólidos")
		gameplay.weapon = "fists"
		reaction.quiet_left = 0.0
		var deadline := Time.get_ticks_msec() + 6000
		while reaction.active and Time.get_ticks_msec() < deadline: await physics_frame
		check(not reaction.active and resident.global_position.distance_to(start) < .1, style + ": volta ao posto depois do susto")
		check(resident.resident_model.sit_amount < .05 or style == "flee", style + ": levanta antes de voltar")
		check(absf(wrapf(resident.resident_model.rotation.y, -PI, PI)) < .01, style + ": devolve a orientação do corpo")
		resident.free()
		await physics_frame
	stage.queue_free()
	await process_frame
