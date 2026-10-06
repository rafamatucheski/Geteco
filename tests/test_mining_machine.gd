extends SceneTree
## Physics contracts with real fleet vehicles, colliders and hydraulic component.
## This fixture does not claim rendered FPS or the production journey to the mine.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const FLEET := preload("res://gameplay/mining/MiningFleet.gd")
const OPERATION := preload("res://gameplay/mining/MiningOperation.gd")
var stage: Node3D
var machine: CharacterBody3D
var controls: Node
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(50).timeout.connect(func(): push_error("MINING_MACHINE timeout"); quit(3))
	run.call_deferred()

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(80,1,80)
	floor_shape.shape = floor_box
	floor_shape.position.y = -.5
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)
	machine = spawn("mining_backhoe",Vector3(0,.08,0))
	controls = machine.get_node_or_null("MiningMachine")
	check(controls != null,"native vehicle installs mining adapter")
	if controls == null: finish(); return
	controls.set_physics_process(false)
	await physics_frame
	for id in FLEET.IDS:
		var definition := preload("res://runtime/FleetCatalog.gd").spec(id)
		check(not definition.is_empty(),id+" exists in production fleet")
		check(preload("res://runtime/FleetState.gd").validate({"archetype":id,"vehicle_id":"mine_test","region":"desert","position":[0,0,0],"yaw":0,"health":float(definition.get("durability",1))}),id+" round-trips fleet validation")
		check(not preload("res://data/catalogs/VehicleDoorSpecs.gd").row(id).is_empty(),id+" has authored boarding cabin")
	var rock := OPERATION.create_rock(0)
	rock.position = controls.cargo_anchor()+Vector3(0,.65,-.55)
	stage.add_child(rock)
	await physics_frame
	check(controls.acquire(rock),"scoop can capture a real loose ore rock")
	check(rock.freeze and rock.collision_layer == 1,"rock is constrained without removing its collider")
	var low: float = rock.global_position.y
	for i in 70: controls.operate(1.0,1.0/60.0)
	check(rock.global_position.y > low+.7,"hydraulic arm physically raises rock")
	controls.release_cargo()
	check(not rock.freeze and not rock.has_meta("mining_carried_by"),"release restores rigid physics and clears ownership")
	# A released object can rest on the solid scoop. Withdraw that support first;
	# expecting it to pass through the bucket would certify broken collision.
	machine.position += Vector3.BACK*8
	controls.operate(0.0,0.0)
	for i in 100: await physics_frame
	check(rock.global_position.y < low+.25 and rock.global_position.y > .35,"released rock falls and rests on solid floor")
	machine.position -= Vector3.BACK*8
	controls.operate(0.0,0.0)
	rock.queue_free()
	await physics_frame
	for id in ["sedan_classic","bike_urban"]: await vehicle_load_case(id)
	var blocked := spawn("sedan_classic",controls.cargo_anchor()+Vector3(0,.05,-1.5))
	blocked.controlled = true
	check(not controls.eligible(blocked),"occupied or controlled vehicles cannot be lifted")
	blocked.controlled = false
	blocked.external_input = true
	check(not controls.eligible(blocked),"NPC controlled vehicles cannot be lifted")
	blocked.external_input = false
	blocked.traffic = true
	check(not controls.eligible(blocked),"traffic with its driver cannot be lifted")
	blocked.queue_free()
	await physics_frame
	await obstacle_case()
	finish()

func spawn(id: String, at: Vector3) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = id
	car.position = at
	stage.add_child(car)
	car.set_physics_process(false)
	return car

func vehicle_load_case(id: String) -> void:
	controls.operate(-1.0,5.0)
	var car := spawn(id,controls.cargo_anchor()+Vector3(0,.08,-1.20))
	await physics_frame
	car.set_physics_process(true)
	var initial_layer := car.collision_layer
	check(controls.acquire(car),"empty "+id+" can be captured")
	check(not car.is_physics_processing() and not car.is_in_group("drivable"),"suspended "+id+" cannot drive or be boarded")
	var initial: float = car.global_position.y
	for i in 65: controls.operate(1.0,1.0/60.0)
	check(car.global_position.y > initial+.6,id+" moves with articulated scoop")
	controls.release_cargo()
	check(car.is_physics_processing() and car.is_in_group("drivable") and car.collision_layer == initial_layer,"release restores "+id+" simulation, entry and collision")
	var released_y := car.global_position.y
	machine.position += Vector3.BACK*8
	controls.operate(0.0,0.0)
	for i in 100: await physics_frame
	print("MINING_SETTLE ",id," released_y=",released_y," final_y=",car.global_position.y," vy=",car.velocity.y," floor=",car.is_on_floor()," monitor=",car.has_node("MiningDroppedLoad")," forced_gravity=",car.has_meta("mining_released_load"))
	check(car.global_position.y < .2 and car.global_position.y > -.12,id+" settles on ground after release (y=%.3f, vy=%.3f, floor=%s)" % [car.global_position.y,car.velocity.y,str(car.is_on_floor())])
	check(car.get_node_or_null("MiningDroppedLoad") == null,id+" removes temporary support monitor after landing")
	machine.position -= Vector3.BACK*8
	controls.operate(0.0,0.0)
	car.queue_free()
	await physics_frame

func obstacle_case() -> void:
	controls.operate(-1.0,5.0)
	var rock := OPERATION.create_rock(1)
	rock.position = controls.cargo_anchor()+Vector3(0,.65,-.5)
	stage.add_child(rock)
	await physics_frame
	check(controls.acquire(rock),"obstacle case captures rock")
	var ceiling := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8,.35,8)
	shape.shape = box
	ceiling.add_child(shape)
	ceiling.position = rock.global_position+Vector3.UP*1.35
	stage.add_child(ceiling)
	await physics_frame
	for i in 150: controls.operate(1.0,1.0/60.0)
	check(rock.global_position.y+.58 < ceiling.global_position.y-.1,"load stops below solid ceiling instead of clipping through it")
	controls.queue_free()
	await physics_frame
	check(not rock.freeze and not rock.has_meta("mining_carried_by"),"controller cleanup always restores cargo physics")
	ceiling.queue_free()
	rock.queue_free()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message); push_error("MINING_MACHINE: "+message)

func finish() -> void:
	print("MINING_MACHINE ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	stage.queue_free()
	quit(0 if failures.is_empty() else 1)
