extends SceneTree
## Caçamba do caminhão da mina com carga de verdade (HaulBedLoad, 28/10): rocha que cai na caçamba assenta,
## acompanha o caminhão andando e virando, bloqueia o salvamento e sai pela tampa quando a caçamba inclina.
## Física real de RigidBody3D e do casco; não mede desempenho nem dirige pela rampa da cava.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const OPERATION := preload("res://gameplay/mining/MiningOperation.gd")
const BED := preload("res://gameplay/mining/HaulBedLoad.gd")
const STEP := 1.0/60.0
var stage: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("MINING_HAUL_BED timeout"); quit(3))
	run.call_deferred()

func run() -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(120,1,120)
	floor_shape.shape = floor_box
	floor_shape.position.y = -.5
	floor_body.add_child(floor_shape)
	stage.add_child(floor_body)
	var truck := VEHICLE.new()
	truck.archetype = "mining_haul_truck"
	truck.position = Vector3(0,.08,0)
	stage.add_child(truck)
	truck.set_physics_process(false)
	var controls := truck.get_node_or_null("MiningMachine")
	check(controls != null and controls.bed_load != null,"haul truck gets a real bed load")
	if controls == null or controls.bed_load == null: finish(); return
	controls.set_physics_process(false)
	var bed_load: Node = controls.bed_load
	var bed: Node3D = controls._bed
	var operation := OPERATION.new()
	stage.add_child(operation)
	await physics_frame
	var rock := OPERATION.create_rock(0)
	stage.add_child(rock)
	rock.global_position = bed.to_global(Vector3(.4,2.6,-2.2))
	var frames := 0
	while bed_load.loaded() == 0 and frames < 180:
		await physics_frame
		bed_load.step(STEP,0.0)
		frames += 1
	check(bed_load.loaded() == 1 and rock.freeze and rock.has_meta("mining_carried_by"),"rock dropped into the bed is seated")
	for i in 90:
		await physics_frame
		bed_load.step(STEP,0.0)
	var local := bed.to_local(rock.global_position)
	check(absf(local.y-(BED.FLOOR_Y+.58)) < .02,"seated rock rests on bed floor (local y %.2f)" % local.y)
	check(operation.save_block_reason() == "Despeje a caçamba antes de salvar.","loaded bed blocks save")
	truck.global_position += Vector3(6,0,-14)
	truck.rotation.y = .7
	bed_load.step(STEP,0.0)
	var moved := bed.to_local(rock.global_position)
	check(moved.distance_to(local) < .02,"load follows truck translation and yaw")
	var dump := 0.0
	frames = 0
	while bed_load.loaded() > 0 and frames < 600:
		dump = move_toward(dump,1.0,STEP*.42)
		bed.rotation.x = -dump*.72
		await physics_frame
		bed_load.step(STEP,dump)
		frames += 1
	check(bed_load.loaded() == 0,"tilting the bed slides the load out (%.1f s)" % (frames*STEP))
	check(not rock.freeze and not rock.has_meta("mining_carried_by"),"dumped rock is a loose rigid body again")
	check(operation.save_block_reason().is_empty(),"empty bed allows save")
	for i in 150:
		await physics_frame
		bed_load.step(STEP,dump)
	var behind := truck.to_local(rock.global_position)
	check(rock.global_position.y < 1.4 and rock.global_position.y > .2,"dumped rock lands on the ground (y %.2f)" % rock.global_position.y)
	check(behind.z > 3.0,"dumped rock falls behind the tailgate (z %.2f)" % behind.z)
	check(not truck.get_collision_exceptions().has(rock),"hull collision with the dumped rock is restored")
	bed.rotation.x = 0.0
	var second := OPERATION.create_rock(1)
	stage.add_child(second)
	second.global_position = bed.to_global(Vector3(-.5,1.8,-3.0))
	for i in 30:
		await physics_frame
		bed_load.step(STEP,0.0)
	check(bed_load.loaded() == 1,"second load seated")
	truck.health = 0.0
	truck.destroyed.emit()
	check(bed_load.loaded() == 0 and not second.freeze,"destroyed truck drops its load")
	finish()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message); push_error("MINING_HAUL_BED: "+message)

func finish() -> void:
	print("MINING_HAUL_BED ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	stage.queue_free()
	quit(0 if failures.is_empty() else 1)
