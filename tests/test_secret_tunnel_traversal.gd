extends SceneTree
## Contrato fisico isolado para a rota secreta.
##
## Usa as capsulas reais de Actor e consultas do PhysicsServer. Os pontos abaixo
## sao a rota de aceitacao autorada; nao sao derivados dos solidos do tunel.
## O teste nao cria viewport, camera de captura ou evidencia renderizada.

const ACTOR := preload("res://scripts/Actor.gd")
const TUNNEL := preload("res://gameplay/urban_v1/SecretTunnel3D.gd")
const PASSAGE := preload("res://gameplay/urban_v1/TruckersVillageSecretPassage.gd")
const PROGRESSION := preload("res://runtime/SecretNetworkProgression.gd")

const TUNNEL_ROUTE := [
	Vector3(0, 4.55, 7.25),
	Vector3(0, 4.55, 6.05),
	Vector3(0, 0.04, -2.15),
	Vector3(0, 0.04, -11.65),
	Vector3(3.35, 0.04, -12.0),
	Vector3(35.55, 0.04, -12.0),
	Vector3(36.0, 0.04, -8.65),
	Vector3(36.0, 0.04, 1.55),
	Vector3(40.0, 0.04, 2.0),
	Vector3(50.85, 0.04, 2.0),
	Vector3(51.25, 0.04, 2.60),
	Vector3(54.50, 0.04, 2.60),
	Vector3(54.50, 0.04, -3.80),
	Vector3(58.0, 0.04, -3.80),
]

const CELLAR_STAIR_ROUTE := [
	Vector3(0, 0.08, -4.72),
	Vector3(0, -1.04, -5.98),
	Vector3(0, -2.12, -7.20),
	Vector3(0, -3.20, -8.43),
	Vector3(0, -4.27, -9.63),
]

class WorldMock extends Node3D:
	var player: CharacterBody3D

class SessionMock extends Node:
	var world: WorldMock
	var ready_for_play := false

class HomesMock extends Node3D:
	var homes: Array[Dictionary] = []

class VillageMock extends Node3D:
	var homes: HomesMock

var checks := 0
var failures: Array[String] = []
var scene: Node3D
var world: WorldMock
var session: SessionMock
var tunnel: Node3D
var passage: Node3D
var progression: RefCounted
var actors: Array[CharacterBody3D] = []


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	print("SECRET_TRAVERSAL ", "PASS " if condition else "FAIL ", label)
	if not condition:
		failures.append(label)


func frames(count := 4) -> void:
	for _index in count:
		await physics_frame


func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	scene = Node3D.new()
	root.add_child(scene)
	world = WorldMock.new()
	scene.add_child(world)
	session = SessionMock.new()
	session.world = world
	scene.add_child(session)

	var player := _actor(true, Vector3(0, 20, 0))
	var npc := _actor(false, Vector3(4, 20, 0))
	world.player = player
	actors = [player, npc]

	tunnel = TUNNEL.new()
	world.add_child(tunnel)
	tunnel.configure(session)
	tunnel.set_process(false)
	tunnel.set_enabled(true)

	progression = PROGRESSION.new()
	progression.receive_dossier()
	progression.discover_house()
	for id in PROGRESSION.KEYPAD_CLUE_IDS:
		progression.discover_keypad_clue(id)
	progression.unlock_keypad()
	passage = _build_passage_fixture()
	passage.set_process(false)
	# Passage.configure() suspende o destino remoto quando o jogador ainda esta
	# na superficie; o contrato abaixo testa sua geometria explicitamente ativa.
	tunnel.set_enabled(true)
	await frames()

	var tunnel_supports := _support_rids(tunnel)
	var cellar_supports := _support_rids(passage)
	check(not tunnel_supports.is_empty(), "tunel expoe pisos e rampas fisicos")
	check(not cellar_supports.is_empty(), "porao expoe piso e rampa fisicos")

	for actor in actors:
		var who := "jogador" if bool(actor.get("is_player")) else "npc"
		_verify_path(actor, passage.home, CELLAR_STAIR_ROUTE, cellar_supports, who + " desce a escada casa-porao")
		_verify_path(actor, tunnel, TUNNEL_ROUTE, tunnel_supports, who + " percorre escada, cantos e entrada do QG")
		var transition_supports := tunnel_supports.duplicate()
		transition_supports.append_array(cellar_supports)
		check(_sweep_clear(actor,passage.cellar_root.to_global(Vector3(-3.05,.04,.15)),tunnel.entry_global(),transition_supports),who + " atravessa a estante ate o patamar externo")
		_verify_functional_points(actor, who, tunnel_supports)
		_verify_blockers(actor, who)

	print("SECRET_TRAVERSAL_RESULT checks=", checks, " failures=", failures.size())
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _actor(is_player: bool, point: Vector3) -> CharacterBody3D:
	var actor: CharacterBody3D = ACTOR.new()
	actor.is_player = is_player
	actor.controlled_automatically = true
	actor.position = point
	world.add_child(actor)
	actor.set_physics_process(false)
	return actor


func _build_passage_fixture() -> Node3D:
	var village := VillageMock.new()
	world.add_child(village)
	var homes := HomesMock.new()
	homes.name = "VillageHomesFixture"
	village.add_child(homes)
	village.homes = homes
	var home := Node3D.new()
	home.name = "Home1"
	homes.add_child(home)
	# Production Casa 1 is rotated: testing an identity house hid the old
	# stair-to-bookshelf orientation error despite isolated routes being clear.
	home.position = Vector3(-403,0,87)
	home.rotation.y = PI*.5
	var roof := Node3D.new()
	roof.name = "Roof"
	home.add_child(roof)
	var upper := Node3D.new()
	upper.name = "UpperWalls"
	home.add_child(upper)
	homes.homes.append({"root":home, "roof":roof, "upper":upper})
	var result := PASSAGE.new()
	world.add_child(result)
	check(result.configure(session, village, progression, tunnel), "passagem configura com Casa 1 fisica")
	return result


func _shape_info(actor: CharacterBody3D) -> Dictionary:
	for child in actor.get_children():
		if child is CollisionShape3D and child.shape != null:
			return {"shape":child.shape, "offset":child.position}
	return {}


func _support_rids(owner: Node) -> Array[RID]:
	var result: Array[RID] = []
	var bodies: Variant = owner.get("solids")
	if not bodies is Array:
		return result
	for body in bodies:
		if not is_instance_valid(body):
			continue
		var id := str(body.get_meta("interior_solid_id", ""))
		if id.ends_with("Floor") or id.ends_with("StairRamp") or id.ends_with("EntryLanding"):
			result.append(body.get_rid())
	return result


func _verify_path(actor: CharacterBody3D, owner: Node3D, local_points: Array, support_rids: Array[RID], label: String) -> void:
	var first_bad_clearance := ""
	var first_bad_support := ""
	for index in local_points.size() - 1:
		var start: Vector3 = owner.to_global(local_points[index])
		var finish: Vector3 = owner.to_global(local_points[index + 1])
		if first_bad_clearance.is_empty() and not _sweep_clear(actor, start, finish, support_rids):
			first_bad_clearance = "segmento %d %s -> %s" % [index, start, finish]
		var distance := start.distance_to(finish)
		var samples := maxi(2, ceili(distance / .65))
		for sample in samples + 1:
			var foot := start.lerp(finish, float(sample) / float(samples))
			if first_bad_clearance.is_empty() and not _capsule_clear(actor, foot, support_rids):
				first_bad_clearance = "corpo em %s" % foot
			if first_bad_support.is_empty() and not _has_support(foot, actor):
				first_bad_support = "sem piso em %s" % foot
	check(first_bad_clearance.is_empty(), label + " sem paredes/moveis no corpo" + (" · " + first_bad_clearance if not first_bad_clearance.is_empty() else ""))
	check(first_bad_support.is_empty(), label + " com apoio continuo" + (" · " + first_bad_support if not first_bad_support.is_empty() else ""))


func _sweep_clear(actor: CharacterBody3D, start: Vector3, finish: Vector3, excluded_supports: Array[RID]) -> bool:
	var info := _shape_info(actor)
	if info.is_empty():
		return false
	var shape: Shape3D = info.get("shape")
	var shape_offset: Vector3 = info.get("offset", Vector3.ZERO)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, start + shape_offset)
	query.motion = finish - start
	query.margin = .015
	query.collision_mask = 1
	query.exclude = excluded_supports.duplicate()
	query.exclude.append(actor.get_rid())
	var travel := scene.get_world_3d().direct_space_state.cast_motion(query)
	return not travel.is_empty() and float(travel[0]) >= .995


func _capsule_clear(actor: CharacterBody3D, foot: Vector3, excluded_supports: Array[RID]) -> bool:
	var info := _shape_info(actor)
	if info.is_empty():
		return false
	var shape: Shape3D = info.get("shape")
	var shape_offset: Vector3 = info.get("offset", Vector3.ZERO)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, foot + shape_offset)
	query.margin = .01
	query.collision_mask = 1
	query.exclude = excluded_supports.duplicate()
	query.exclude.append(actor.get_rid())
	return scene.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _has_support(foot: Vector3, actor: CharacterBody3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(foot + Vector3.UP * .32, foot + Vector3.DOWN * .72, 1, [actor.get_rid()])
	var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or float(hit.get("position", foot).y) > foot.y + .12:
		return false
	var collider: Variant = hit.get("collider")
	if not is_instance_valid(collider):
		return false
	var id := str(collider.get_meta("interior_solid_id", ""))
	return id.ends_with("Floor") or id.ends_with("StairRamp") or id.ends_with("EntryLanding")


func _verify_functional_points(actor: CharacterBody3D, who: String, tunnel_supports: Array[RID]) -> void:
	# Posicoes de pe independentes dos centros dos moveis. Ambas permanecem no
	# alcance usado pela interacao, mas precisam acomodar a capsula inteira.
	var network_foot := tunnel.to_global(Vector3(58.0, .04, -3.80))
	var route_foot := tunnel.to_global(Vector3(63.0, .04, 1.20))
	check(_capsule_clear(actor, network_foot, tunnel_supports), who + " cabe diante do quadro principal")
	check(network_foot.distance_to(tunnel.network_console_global()) <= 2.0, who + " alcanca o quadro principal do ponto livre")
	check(_capsule_clear(actor, route_foot, tunnel_supports), who + " cabe diante do console de rotas")
	check(route_foot.distance_to(tunnel.route_console_global()) <= 2.0, who + " alcanca o console de rotas do ponto livre")


func _verify_blockers(actor: CharacterBody3D, who: String) -> void:
	_check_blocker(actor, tunnel, Vector3(58.0, .04, -5.34), Vector3(0, 0, -1.35), "SealedGate", who + " nao atravessa o gate selado")
	_check_blocker(actor, tunnel, Vector3(58.0, .04, 5.15), Vector3(0, 0, -3.2), "MapTable", who + " nao atravessa a mesa de mapas")
	_check_blocker(actor, tunnel, Vector3(55.0, .04, 7.55), Vector3(-2.2, 0, 0), "OldGenerator", who + " nao atravessa o gerador antigo")
	_check_blocker(actor, tunnel, Vector3(60.8, .04, 6.75), Vector3(2.4, 0, 0), "FieldCot", who + " nao atravessa a cama de campanha")
	_check_blocker(actor, tunnel, Vector3(54.35, .04, 0.0), Vector3(-3.0, 0, 0), "SupplyShelf", who + " nao atravessa a estante de suprimentos")
	_check_blocker(actor, tunnel, Vector3(61.65, .04, -.10), Vector3(3.0, 0, 0), "RadioDesk", who + " nao atravessa a bancada de radio")
	_check_blocker(actor, tunnel, Vector3(56.35, .04, -10.40), Vector3(2.0, 0, 0), "OldGurney", who + " nao atravessa a maca no setor selado")
	_check_blocker(actor, passage.cellar_root, Vector3(1.75, .04, -1.70), Vector3(2.5, 0, 0), "StorageRack", who + " nao atravessa a estante do porao")
	_check_blocker(actor, passage.cellar_root, Vector3(.95, .04, 2.75), Vector3(2.5, 0, 0), "CellarCrates", who + " nao atravessa as caixas do porao")
	_check_blocker(actor, passage.cellar_root, Vector3(-1.20, .04, 2.35), Vector3(0, 0, 2.0), "CellarWorkbench", who + " nao atravessa a bancada do porao")


func _check_blocker(actor: CharacterBody3D, owner: Node3D, local_start: Vector3, local_motion: Vector3, expected_id: String, label: String) -> void:
	actor.global_position = owner.to_global(local_start)
	actor.velocity = Vector3.ZERO
	var global_motion := owner.global_basis * local_motion
	var collision := actor.move_and_collide(global_motion, true)
	var id := ""
	if collision != null and is_instance_valid(collision.get_collider()):
		id = str(collision.get_collider().get_meta("interior_solid_id", ""))
	check(collision != null and id.ends_with(expected_id), label + (" · colidiu com " + id if collision != null else " · sem colisao"))
