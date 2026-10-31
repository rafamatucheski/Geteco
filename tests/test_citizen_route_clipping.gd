extends SceneTree
## Física real mais o helper de admissão do ProductionWorld. Sem população do Main,
## renderizador nem afirmação de FPS; os metadados de rua representam a regra de exclusão da pista.
const PRODUCTION := preload("res://runtime/ProductionWorld.gd")
const SESSION := preload("res://runtime/FullSession.gd")
var checks := 0
var failures: Array[String] = []

class PopulationWorld extends Node3D:
	var player := CharacterBody3D.new()

class RoadRegion extends Node3D:
	var roads: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func box(parent: Node3D, at: Vector3, size: Vector3, layer := 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body

func sync_physics() -> void:
	for tick in 2: await physics_frame

func crossing(at: float, width: float) -> Dictionary:
	return {"id": "test_crossing", "points": PackedVector3Array([Vector3(at,0,-10),Vector3(at,0,10)]), "width": width}

func run() -> void:
	var world := PopulationWorld.new()
	root.add_child(world)
	world.add_child(world.player)
	world.player.position = Vector3(0,0,100)
	var region := RoadRegion.new()
	world.add_child(region)
	var production := PRODUCTION.new()
	world.add_child(production)
	production.set_process(false)
	production.world = world
	production.regions = {"harbor": region}
	# Usa a cápsula produtiva da FullSession e as checagens de piso de apoio.
	# Mantém esta sessão fora da árvore para que o _ready de jogo dela não rode.
	var session := SESSION.new()
	session.world = world
	production.session = session
	var floor_body := box(world,Vector3(0,-.1,0),Vector3(60,.2,8))
	await sync_physics()
	var point := Vector3(0,.08,0)
	var start := Vector3(-20,.08,0)
	var finish := Vector3(20,.08,0)
	var route: PackedVector3Array = production._clip_citizen_route(point,start,finish)
	check(route.size()==2 and route[0].is_equal_approx(start) and route[1].is_equal_approx(finish),"clear original 40 m walk retains both endpoints")

	region.roads.assign([crossing(6,4)])
	route = production._clip_citizen_route(point,start,finish)
	check(route.size()==2 and route[0].is_equal_approx(start) and route[1].x<=3.7 and route[1].x>0,"crossing clips only its side before the carriageway")
	if route.size()==2:
		check(production.desert_social_route_clear(route),"clipped walk still passes the productive full-route validator")
	check(not production.desert_social_route_clear(PackedVector3Array([start,finish])),"desert route contract still rejects a full route crossing a road")
	region.roads.assign([crossing(-6,4)])
	route = production._clip_citizen_route(point,start,finish)
	check(route.size()==2 and route[0].x>=-3.7 and route[0].x<0 and route[1].is_equal_approx(finish),"crossing on the opposite side clips that endpoint")
	region.roads.assign([crossing(0,4)])
	check(production._clip_citizen_route(point,start,finish).is_empty(),"spawn point in a carriageway is refused")
	region.roads.assign([crossing(-3.5,3),crossing(3.5,3)])
	check(production._clip_citizen_route(point,start,finish).is_empty(),"a safe remnant shorter than 4 m is refused")
	region.roads.clear()

	var obstacle := box(world,Vector3(6.5,1,0),Vector3(3.2,2,3))
	await sync_physics()
	route = production._clip_citizen_route(point,start,finish)
	check(route.size()==2 and route[0].is_equal_approx(start) and is_equal_approx(route[1].x,4),"real solid clips the walk before the first blocked sample")
	obstacle.free()
	await sync_physics()
	obstacle = box(world,Vector3(0,1,0),Vector3(1,2,1))
	await sync_physics()
	check(production._clip_citizen_route(point,start,finish).is_empty(),"real solid at the spawn point refuses admission")
	obstacle.free()
	await sync_physics()

	# As amostras usam a cápsula comum de ator de .32 m. Um prop fora dessas
	# amostras ainda precisa bloquear a varredura final do envelope de faixa de .72 m.
	obstacle = box(world,Vector3(10,1,.6),Vector3(.1,2,.1))
	await sync_physics()
	check(production._clip_citizen_route(point,start,finish).is_empty(),"final .72 m capsule refuses a prop between the walking lanes")
	obstacle.free()
	await sync_physics()
	obstacle = box(world,Vector3(5,1,0),Vector3(.1,2,3))
	await sync_physics()
	check(production._clip_citizen_route(point,start,finish).is_empty(),"final swept capsule sees a thin wall between 2 m samples")
	obstacle.free()
	await sync_physics()

	var pedestrian := CharacterBody3D.new()
	pedestrian.collision_layer = 2
	pedestrian.collision_mask = 0
	pedestrian.position = Vector3(6,0,0)
	var pedestrian_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.7
	pedestrian_shape.shape = capsule
	pedestrian_shape.position.y = .85
	pedestrian.add_child(pedestrian_shape)
	world.add_child(pedestrian)
	await sync_physics()
	route = production._clip_citizen_route(point,start,finish)
	check(route.size()==2 and route[1].x<5 and route[0].is_equal_approx(start),"a real pedestrian in the route participates in admission")
	pedestrian.free()
	await sync_physics()
	route = production._clip_citizen_route(point,start,finish)
	check(route.size()==2 and route[1].is_equal_approx(finish),"released obstruction restores the original walk without a cache delay")
	check(production._clip_citizen_route(Vector3(80,.08,0),Vector3(60,.08,0),Vector3(100,.08,0)).is_empty(),"unsupported spawn point is refused")

	floor_body.position.y += .12
	await sync_physics()
	point.y += .12
	start.y += .12
	finish.y += .12
	route = production._clip_citizen_route(point,start,finish)
	check(route.size()==2 and route[0].is_equal_approx(start) and route[1].is_equal_approx(finish),"raised paving retains grounded route heights and the full walk")
	session.free()
	world.free()
	print("CITIZEN_ROUTE_CLIPPING ",JSON.stringify({"checks":checks,"failures":failures,"scope":"Functional real physics and productive capsule checks, not gameplay FPS."}))
	quit(0 if failures.is_empty() else 1)
