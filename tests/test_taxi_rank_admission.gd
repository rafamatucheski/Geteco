extends SceneTree
## Obstrução de física real mais o laço real de nova tentativa/admissão do ponto.
## O espião de spawn constrói um Vehicle real para conferir o contrato do casco em cache.
const RANK := preload("res://runtime/TaxiRank.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []
var checks := 0

class RankWorld extends Node3D:
	var player := Node3D.new()
	var driving := {"car":null}
	var gameplay: Node = null

class SpawnSpy extends RefCounted:
	var world: Node3D
	var vehicles: Array[CharacterBody3D] = []
	var calls := 0
	func spawn_vehicle(id: String, point: Vector3, yaw: float) -> CharacterBody3D:
		calls += 1
		var car := VEHICLE.new()
		car.archetype = id
		car.position = point
		car.rotation.y = yaw
		world.add_child(car)
		car.set_physics_process(false)
		vehicles.append(car)
		return car

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func box(world: Node3D, point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.position = point
	world.add_child(body)
	return body

func run() -> void:
	var world := RankWorld.new()
	root.add_child(world)
	world.add_child(world.player)
	world.player.position = RANK.CENTER
	var controller := SpawnSpy.new()
	controller.world = world
	var rank := RANK.new()
	rank.configure({"session":{"ready_for_play":true,"state":{"region_id":"harbor","place_id":""},"world":world,"controller":controller},"used_bays":{1:true,2:true,3:true}})
	world.add_child(rank)
	rank.set_process(false)
	box(world,Vector3(160,-.1,73),Vector3(40,.2,20))
	# Com yaw PI/2 o casco longo se estende ao longo de X; isto não pega num casco sem rotação.
	var obstacle := box(world,RANK.SLOTS[0]+Vector3(1.9,.6,0),Vector3(.3,.8,.3))
	for i in 2: await physics_frame
	check(rank._slot_occupied(RANK.SLOTS[0]),"rotated taxi footprint sees a real solid")
	rank._process(.5)
	rank._process(.5)
	check(controller.calls==0 and rank.cars.is_empty(),"blocked retries never construct a vehicle")
	check(rank.elapsed==.5,"blocked bay preserves retry cadence")
	obstacle.set_meta("vehicle_ramp_structure",true)
	check(not rank._slot_occupied(RANK.SLOTS[0]),"ramp exception matches production clearance")
	obstacle.remove_meta("vehicle_ramp_structure")
	# Toda camada usada por vehicle_position_clear precisa bloquear a admissão.
	for layer in [1,2,4]:
		obstacle.collision_layer = layer
		for i in 2: await physics_frame
		check(rank._slot_occupied(RANK.SLOTS[0]),"collision layer %d blocks the bay" % layer)
	obstacle.queue_free()
	for i in 2: await physics_frame
	check(not rank._slot_occupied(RANK.SLOTS[0]),"released bay becomes clear")
	rank._process(.49)
	check(controller.calls==0,"clear bay waits for existing retry timer")
	rank._process(.02)
	check(controller.calls==1 and rank.cars.has(0) and rank.drivers.has(0),"next retry admits real taxi and driver")
	if rank.cars.has(0):
		var car: CharacterBody3D = rank.cars[0]
		var actual_shape: CollisionShape3D = car.get("shape")
		var actual_hull := actual_shape.shape as BoxShape3D
		var query_hull := rank._admission_query.shape as BoxShape3D
		check(query_hull.size.is_equal_approx(actual_hull.size),"preflight bounds match Vehicle's actual taxi hull")
		var expected := Transform3D(car.basis,car.position+car.basis*actual_shape.position)
		check(rank._admission_query.transform.is_equal_approx(expected),"preflight center and yaw match real hull transform")
		rank._process(.5)
		check(controller.calls==1 and rank.cars.size()==1,"occupied rank slot does not duplicate admitted taxi")
	world.free()
	print("TAXI_RANK_ADMISSION ",checks," checks failures=",failures)
	quit(0 if failures.is_empty() else 1)
