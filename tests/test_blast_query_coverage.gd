extends SceneTree
## Servidor físico real + explode/detonate/damage produtivos. Só apresentação é suprimida.
const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
const CANNON := preload("res://gameplay/police_response/ground/TankCannon.gd")

class DamageBody extends StaticBody3D:
	var calls := 0
	var received := 0.0
	var dead := false
	func receive_damage(amount: float, _source: Node) -> void:
		calls += 1
		received += amount

class GameplayProbe extends "res://gameplay/Gameplay.gd":
	func _ready() -> void: pass
	func _sound(_kind: String, _point: Vector3, _base_volume_db: float = NPC_GUNFIRE_DB) -> void: pass
	func _play_stream(_stream: AudioStream, _point: Vector3, _volume_db: float, _pitch: float = 1.0, _reach: float = HEARING_DEFAULT) -> void: pass
	func _hit_effect(_hit: Dictionary, _amount: float, _direction: Vector3) -> void: pass
	func _kick_camera(_strength: float) -> void: pass

var checks := 0
var failures: Array[String] = []
var bodies: Array[DamageBody] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func body(scene: Node3D, point: Vector3, count := 1, layer := 2) -> DamageBody:
	var actor := DamageBody.new()
	actor.collision_layer = layer
	actor.collision_mask = 0
	actor.position = point
	for index in count:
		var collider := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = .03
		collider.shape = shape
		actor.add_child(collider)
	scene.add_child(actor)
	return actor

func shape_query(origin: Vector3, radius: float) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	query.shape = sphere
	query.transform.origin = origin
	query.collision_mask = 6
	return query

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var gameplay := GameplayProbe.new()
	gameplay.state = KIT.CombatState.new()
	gameplay.world = scene
	gameplay.set_physics_process(false)
	scene.add_child(gameplay)
	var origin := Vector3(0,1,0)
	# 130 corpos e um deles com 96 shapes: dedup não pode esconder truncamento.
	for index in 130:
		var point := Vector3(float(index%13-6)*.23,0,float(floori(float(index)/13.0)-4)*.23)
		bodies.append(body(scene,point,96 if index == 0 else 1))
	var outside := body(scene,Vector3(12,0,0))
	var wrong_mask := body(scene,Vector3(.5,0,.5),1,8)
	var protected := body(scene,Vector3(.5,0,-.5))
	protected.set_meta("invulnerable",true)
	var source := body(scene,Vector3(-.5,0,.5))
	var police := body(scene,Vector3(-.5,0,-.5))
	police.set_meta("gameplay_role","police")
	var area := Area3D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	var area_shape := CollisionShape3D.new()
	var area_sphere := SphereShape3D.new()
	area_sphere.radius = .05
	area_shape.shape = area_sphere
	area.add_child(area_shape)
	scene.add_child(area)
	var tank := CharacterBody3D.new()
	tank.position = Vector3(-20,0,0)
	scene.add_child(tank)
	var cannon := CANNON.new()
	cannon.vehicle = tank
	cannon.set_physics_process(false)
	scene.add_child(cannon)
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = scene.get_world_3d().direct_space_state
	var query := shape_query(origin,5.0)
	var limited: Array[Dictionary] = space.intersect_shape(query,64)
	check(limited.size() == 64, "fixture excede a página física antiga de 64 resultados")
	gameplay.explode(origin,5.0,100.0,source,false)
	var all_once := true
	var all_amounts := true
	for actor: DamageBody in bodies:
		all_once = all_once and actor.calls == 1
		var expected: float = 100.0*(1.0-origin.distance_to(actor.global_position+Vector3.UP)/5.0)
		all_amounts = all_amounts and is_equal_approx(actor.received,expected)
	check(all_once, "Gameplay atinge todos os 130 corpos uma única vez, incluindo 96 shapes")
	check(all_amounts, "Gameplay preserva falloff de cada alvo sem limitar alvos")
	check(outside.calls == 0 and wrong_mask.calls == 0 and protected.calls == 0 and source.calls == 0, "Gameplay preserva raio/máscara/proteção/hurt_source=false")
	check(police.calls == 1, "explosão comum não aplica filtro de equipe exclusivo do tanque policial")
	for actor: DamageBody in bodies+[outside,wrong_mask,protected,source,police]:
		actor.calls = 0
		actor.received = 0.0
	cannon._detonate(gameplay,source,{"position":origin,"normal":Vector3.ZERO,"collider":bodies[0]},Vector3.FORWARD,true)
	all_once = true
	all_amounts = true
	for actor: DamageBody in bodies:
		all_once = all_once and actor.calls == 1
		var expected: float = 180.0 if actor == bodies[0] else 100.0*(1.0-origin.distance_to(actor.global_position+Vector3.UP)/5.0)
		all_amounts = all_amounts and is_equal_approx(actor.received,expected)
	check(all_once, "canhão atinge todos os 130 corpos e não repete dano direto no splash")
	check(all_amounts, "canhão preserva dano direto e falloff radial")
	check(outside.calls == 0 and wrong_mask.calls == 0 and protected.calls == 0 and source.calls == 0 and police.calls == 0, "canhão preserva raio/máscara/proteção/source/equipe policial")
	# Load tardio permite executar o mesmo teste contra callers antigos antes da correção.
	var helper: Script = load("res://gameplay/BlastQuery.gd") if FileAccess.file_exists("res://gameplay/BlastQuery.gd") else null
	check(helper != null, "helper completo disponível para controles de consulta")
	if helper != null:
		query.exclude = [source.get_rid(),bodies[3].get_rid()]
		var exclusions: Array[RID] = query.exclude
		var hits: Array[Dictionary] = helper.intersect_bodies(space,query)
		var ids: Dictionary = {}
		for hit: Dictionary in hits: ids[hit.collider_id] = true
		check(hits.size() == 131 and ids.size() == hits.size(), "paginação inclui todos os corpos restantes, um hit por RID")
		check(not ids.has(source.get_instance_id()) and not ids.has(bodies[3].get_instance_id()) and query.exclude == exclusions, "exclusions originais preservadas sem mutar query")
		check(not ids.has(outside.get_instance_id()) and not ids.has(wrong_mask.get_instance_id()) and not ids.has(area.get_instance_id()), "raio/máscara/áreas desativadas mantidos")
		query.collide_with_bodies = false
		query.collide_with_areas = true
		hits = helper.intersect_bodies(space,query)
		check(hits.size() == 1 and hits[0].collider == area, "flags de áreas/corpos preservadas")
		query.collide_with_bodies = true
		query.collide_with_areas = false
		var shape: Shape3D = query.shape as Shape3D
		var rid_query := PhysicsShapeQueryParameters3D.new()
		rid_query.shape_rid = shape.get_rid()
		rid_query.transform = query.transform
		rid_query.collision_mask = query.collision_mask
		rid_query.exclude = query.exclude
		check(helper.intersect_bodies(space,rid_query).size() == 131, "shape RID sem Resource também preservado")
		rid_query.transform.origin = Vector3(100,100,100)
		check(helper.intersect_bodies(space,rid_query).is_empty(), "consulta vazia termina sem hits")
	scene.free()
	print("%s BLAST_QUERY_COVERAGE checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,failures])
	quit(0 if failures.is_empty() else 1)
