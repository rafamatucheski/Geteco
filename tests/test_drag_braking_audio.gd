extends SceneTree
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func run() -> void:
	var ground := StaticBody3D.new()
	ground.set_meta("vehicle_surface","hard")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80,.2,80)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -.1
	root.add_child(ground)
	var car := preload("res://scripts/Vehicle.gd").new()
	car.archetype = "sport_coupe"
	root.add_child(car)
	car.place(Vector3(0,.05,0),0)
	for _i in 8: await physics_frame
	car.set_physics_process(false)
	car.controlled = true
	car.brake_input = true
	car.speed = 20
	car.horizontal_velocity = Vector3(0,0,-20)
	car.set_meta("drag_service_brake_slip",1.0)
	var tires = car.effects.tire_effects
	tires.physics_tick(.1,true)
	check(is_instance_valid(tires.skid_audio) and tires.skid_audio.playing,"real wheel lock produces tire audio")
	if not is_instance_valid(tires.skid_audio): quit(1); return
	car.set_meta("drag_service_brake_slip",.149)
	tires.physics_tick(.016,true)
	check(tires._probe_clock > 0,"regression uses cached contacts between probes")
	check(not tires.skid_audio.playing,"rolling grip stops squeal immediately between probes")
	car.horizontal_velocity = Vector3(8,0,-20)
	tires.physics_tick(.1,true)
	check(tires.skid_audio.playing,"real lateral slide still produces squeal")
	tires.physics_tick(.016,true)
	check(tires.skid_audio.playing,"rolling brake override never silences lateral drift")
	car.free()
	ground.free()
	await process_frame
	print("DRAG_BRAKING_AUDIO checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)
