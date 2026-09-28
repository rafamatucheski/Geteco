extends Node3D
## Four curbside bays east of the coach terminal; no interior or extra light rig.
const SLOTS := [Vector3(148,.16,74),Vector3(158,.16,74),Vector3(166,.16,74),Vector3(174,.16,74)]
const CENTER := Vector3(161,0,72)
var service
var cars: Dictionary = {}
var drivers: Dictionary = {}
var elapsed := 0.0
var dressing: Node3D

func configure(owner_service) -> void: service = owner_service

func _process(delta: float) -> void:
	elapsed -= delta
	if elapsed > 0 or service.session == null or not service.session.ready_for_play: return
	elapsed = .5
	var session = service.session
	var near: bool = session.state.region_id == "harbor" and session.state.place_id.is_empty() and session.world.player.position.distance_to(CENTER) < 95
	if not near:
		if session.world.player.position.distance_to(CENTER) > 135 or session.state.region_id != "harbor": _unload()
		return
	if not is_instance_valid(dressing): _build()
	for index in SLOTS.size():
		if is_instance_valid(cars.get(index)):
			var vehicle = cars[index]
			if vehicle.health <= 0: _close_slot(index)
			continue
		var id := "taxi_rank_"+str(index)
		var existing: bool = is_instance_valid(session.world.driving.car) and session.world.driving.car.vehicle_id == id
		for vehicle in session.controller.vehicles:
			if is_instance_valid(vehicle) and vehicle.vehicle_id == id: existing = true
		if existing: continue
		# Used bays stay empty during this visit, avoiding replacement in front of the player.
		if service.used_bays.has(index): continue
		var vehicle = session.controller.spawn_vehicle("taxi_yellow",SLOTS[index],PI/2)
		if vehicle == null: continue
		vehicle.vehicle_id = id
		vehicle.set_meta("taxi_rank",true)
		vehicle.set_meta("taxi_service",true)
		cars[index] = vehicle
		var driver = preload("res://runtime/TaxiRankDriver.gd").new()
		driver.configure("taxi",["Joel","Sérgio","Nivaldo","Paulo"][index],[Color("d3c9b4"),Color("6b8797"),Color("d5d9dc"),Color("747660")][index])
		driver.set_meta("persistent_id",id+"_driver")
		driver.position = SLOTS[index]+Vector3(0,0,-2.5)
		add_child(driver)
		driver.bind_combat(session.world.gameplay)
		driver.threatened.connect(func(_actor): _close_slot(index))
		driver.died.connect(func(_actor): _close_slot(index))
		drivers[index] = driver
		break # One car/actor construction per streaming tick.

func _close_slot(index: int) -> void:
	var vehicle = cars.get(index)
	if is_instance_valid(vehicle):
		vehicle.set_meta("taxi_unattended",true)
		service.light(vehicle,false)

func depart(vehicle, stolen: bool) -> void:
	for index in cars.keys():
		if cars[index] != vehicle: continue
		service.used_bays[index] = true
		vehicle.remove_meta("taxi_rank")
		var driver = drivers.get(index)
		if is_instance_valid(driver):
			if stolen: driver.flee(vehicle.position)
			else: driver.queue_free()
		cars.erase(index)
		return

func _unload() -> void:
	for index in cars:
		var vehicle = cars[index]
		if is_instance_valid(vehicle) and vehicle != service.transport.car and vehicle != service.session.world.driving.car: vehicle.queue_free()
	cars.clear()
	for driver in drivers.values():
		if is_instance_valid(driver): driver.queue_free()
	drivers.clear()
	if is_instance_valid(dressing): dressing.queue_free()
	dressing = null
	service.used_bays.clear()

func _build() -> void:
	dressing = Node3D.new(); dressing.name = "TaxiBays"; add_child(dressing)
	for point in SLOTS:
		for x in [-2.9,2.9]: _box(Vector3(.07,.012,2.35),point+Vector3(x,-.085,.1),Color("dabd55"))
		_box(Vector3(5.8,.012,.07),point+Vector3(0,-.085,1.25),Color("dabd55"))
	_box(Vector3(.09,2.65,.09),Vector3(155,1.4,71.5),Color("555f66"),true)
	_box(Vector3(1.4,.62,.10),Vector3(155,2.65,71.5),Color("e8bd40"),true)
	for back in [false,true]:
		var label := Label3D.new()
		label.text = "TÁXI"; label.font_size = 48; label.pixel_size = .006
		label.outline_size = 0; label.modulate = Color("242c33")
		label.position = Vector3(155,2.65,71.56 if back else 71.44)
		label.rotation.y = 0 if back else PI
		dressing.add_child(label)

func _box(size: Vector3, point: Vector3, color: Color, solid := false) -> void:
	var mesh := MeshInstance3D.new(); var box := BoxMesh.new(); box.size = size; mesh.mesh = box
	var material := StandardMaterial3D.new(); material.albedo_color = color; material.roughness = .8
	mesh.material_override = material; mesh.position = point; dressing.add_child(mesh)
	if solid:
		var body := StaticBody3D.new(); body.position = point; body.collision_layer = 1
		var collision := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = size; collision.shape = shape
		body.add_child(collision); dressing.add_child(body)
