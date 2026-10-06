extends "res://tests/test_mining_machine.gd"
## Native damage while a load is suspended: both rigid blast wrecks and the
## crushed CharacterBody path must release ownership without losing gravity.
const CRUSH := preload("res://gameplay/street_physics/HeavyVehicleCrush.gd")

func _initialize() -> void:
	create_timer(50).timeout.connect(func(): push_error("MINING_DEATH_RELEASE timeout"); quit(3))
	run.call_deferred()

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80,1,80)
	shape.shape = box
	shape.position.y = -.5
	ground.add_child(shape)
	stage.add_child(ground)
	machine = spawn("mining_backhoe",Vector3(0,.08,0))
	controls = machine.get_node("MiningMachine")
	controls.set_physics_process(false)
	await physics_frame
	await death_case(false)
	await death_case(true)
	print("MINING_DEATH_RELEASE ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	stage.queue_free()
	quit(0 if failures.is_empty() else 1)

func death_case(crushed: bool) -> void:
	controls.operate(-1.0,5.0)
	var car := spawn("sedan_classic",controls.cargo_anchor()+Vector3(0,.08,-1.2))
	var original_platform_layers := car.platform_floor_layers
	var original_platform_leave := car.platform_on_leave
	var label := "crushed" if crushed else "rigid"
	if crushed: CRUSH.apply_saved(car,.30)
	await physics_frame
	car.set_physics_process(true)
	check(controls.acquire(car),label+" damage fixture is held by real scoop")
	for i in 65: controls.operate(1.0,1.0/60.0)
	car.receive_damage(car.max_health*3.0)
	check(car.health <= 0 and controls.cargo == null,label+" native destroyed signal releases hydraulic ownership immediately")
	check(not car.has_meta("mining_carried_by"),label+" destroyed load has no stale carrier")
	check(car.has_meta("mining_released_load"),label+" destruction retains settling protection")
	var wreck := car.get_node_or_null("WreckBody") as RigidBody3D
	if crushed:
		check(wreck == null and car.is_physics_processing(),"crushed native hull keeps its character physics")
	else:
		check(wreck != null and not car.is_physics_processing(),"native rigid wreck exclusively owns motion after destruction")
	await physics_frame
	check(car.has_meta("mining_released_load"),label+" support monitor does not disappear just because health is zero")
	machine.position += Vector3.BACK*8
	controls.operate(0.0,0.0)
	for i in 240: await physics_frame
	if crushed:
		check(car.global_position.y > -.1 and car.global_position.y < .2,"crushed hull falls to solid ground after the scoop withdraws")
	elif is_instance_valid(wreck):
		var floor_y := INF
		for part in wreck.get_children():
			if part is CollisionShape3D and part.shape is BoxShape3D:
				var size: Vector3 = part.shape.size
				var bounds: AABB = part.global_transform*AABB(-size*.5,size)
				floor_y = bounds.position.y
		check(floor_y > -.10 and floor_y < .20,"rigid wreck rests on ground with its actual rotated collision hull")
	check(not car.has_node("MiningDroppedLoad") and not car.has_meta("mining_released_load"),label+" support monitor cleans up after grounded wreck")
	check(car.platform_floor_layers == original_platform_layers and car.platform_on_leave == original_platform_leave,label+" platform configuration is restored after landing")
	print("MINING_DEATH_SETTLE ",label," y=",car.global_position.y," health=",car.health," character_physics=",car.is_physics_processing()," monitor=",car.has_node("MiningDroppedLoad"))
	machine.position -= Vector3.BACK*8
	controls.operate(0.0,0.0)
	car.queue_free()
	await physics_frame
