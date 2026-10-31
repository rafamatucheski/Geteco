extends SceneTree
## Ações de pedal pelo veículo real, chão físico e efeitos de pneu/áudio.
const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func frames(count: int) -> void:
	for tick in count: await physics_frame

func release() -> void:
	for action in ["accelerate","brake","move_up","move_down","handbrake"]: Input.action_release(action)

func run() -> void:
	var input := root.get_node("GameInput")
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.set_meta("vehicle_surface", "hard")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80,.2,80)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -.1
	root.add_child(ground)
	var car := VEHICLE.new()
	car.archetype = "sport_coupe"
	root.add_child(car)
	car.place(Vector3(0,.05,0),0)
	car.controlled = true
	await frames(5)
	var tires = car.effects.tire_effects
	for combo in [["accelerate","brake"],["move_up","move_down"],["move_up","handbrake"]]:
		release()
		input.using_gamepad = combo[0] == "accelerate"
		car.place(Vector3(0,.05,0),0)
		await frames(5)
		var origin := car.position
		Input.action_press(combo[0])
		Input.action_press(combo[1])
		await frames(45)
		check(car.burnout_strength() > .9, str(combo)+": simultaneous inputs engage burnout")
		check(car.position.distance_to(origin) < .15 and absf(car.speed) < .05, str(combo)+": brake holds chassis")
		check(tires.last_modes == ["smoke","smoke"], str(combo)+": both rear contacts emit smoke at rest")
		check(tires.skid_audio != null and tires.skid_audio.playing, str(combo)+": held tire squeal plays")
		check(car.handling.drive.rpm > car.handling.drive.redline*.65, str(combo)+": engine revs under load")
		var rear: Node3D
		var front: Node3D
		for wheel in car.wheels:
			if wheel.get_meta("front",false): front = wheel
			else: rear = wheel
		var rear_angle := rear.rotation.x
		var front_angle := front.rotation.x
		await frames(4)
		check(absf(angle_difference(rear_angle,rear.rotation.x)) > .2 and absf(angle_difference(front_angle,front.rotation.x)) < .02, "only driven rear tires turn at rest")
		release()
		await frames(8)
		check(not tires.emitters[0].emitting and not tires.emitters[1].emitting and not tires.skid_audio.playing, "release stops continuous smoke and squeal")
	# Light accelerator noise alone must not trigger a burnout.
	Input.action_press("brake")
	Input.action_press("accelerate", .1)
	check(input.vehicle_burnout_throttle() == 0.0, "analog noise below threshold is ignored")
	release()
	input.using_gamepad = true
	Input.action_press("accelerate", .7)
	Input.action_press("brake", .6)
	await frames(30)
	check(car.burnout_strength() > .6, "unequal analog pedals still engage burnout")
	# A seleção de superfície precisa seguir os contatos reais; patinar na terra não é fumaça de borracha.
	for kind in ["grass","dirt","snow","water","hard"]:
		ground.set_meta("vehicle_surface", kind)
		await frames(8)
		check(tires.last_modes == (["smoke","smoke"] if kind == "hard" else (["lake","lake"] if kind == "water" else [kind,kind])), "stationary spin respects " + kind)
		check(tires.skid_audio.playing == (kind == "hard"), "rubber squeal restricted to hard contact: " + kind)
	var emitter_ids: Array = tires.emitters.map(func(e): return e.get_instance_id())
	check(tires.emitters.size() == 2 and tires.emitters[0].amount <= 36, "two bounded smoke emitters")
	for flag in ["input_locked","engine_disabled","external_input"]:
		car.set(flag, true)
		await frames(8)
		check(car.burnout_strength() == 0.0 and not tires.emitters[0].emitting and not tires.skid_audio.playing, flag+": no held burnout")
		car.set(flag, false)
		await frames(8)
	car.throttle_input = 0.0
	car.brake_input = true
	car.controlled = false
	await frames(8)
	check(car.burnout_strength() == 0.0 and not tires.emitters[0].emitting, "leaving the driver seat stops burnout")
	car.controlled = true
	await frames(12)
	car.set_physics_process(false)
	await frames(8)
	check(not tires.emitters[0].emitting and not tires.skid_audio.playing, "frozen vehicle cannot leave a looping burnout behind")
	car.set_physics_process(true)
	await frames(8)
	car.effects.presentation_enabled = false
	await frames(8)
	check(not tires.emitters[0].emitting and not tires.skid_audio.playing, "suspended presentation stops burnout")
	car.effects.presentation_enabled = true
	await frames(8)
	check(tires.emitters.map(func(e): return e.get_instance_id()) == emitter_ids, "repeated activation reuses emitter nodes")
	# Airborne rear wheels have no road contact and produce no surface effect.
	car.position.y = 8
	car.velocity = Vector3.ZERO
	await frames(8)
	check(car.burnout_strength() == 0.0 and not tires.emitters[0].emitting and not tires.skid_audio.playing, "airborne car has no ground smoke or squeal")
	car.place(Vector3(0,.05,0),0)
	await frames(15)
	Input.action_release("brake")
	await frames(35)
	check(car.speed > .5 and car.burnout_strength() == 0.0, "releasing brake launches normally")
	release()
	Input.action_press("brake")
	await frames(90)
	check(car.speed < -.05 and car.burnout_strength() == 0.0, "brake alone still allows reverse")
	release()
	car.speed = 12
	car.horizontal_velocity = Vector3(0,0,-12)
	Input.action_press("accelerate")
	Input.action_press("brake")
	await frames(10)
	check(car.speed < 12 and car.speed > .75 and car.burnout_strength() == 0.0, "both pedals at speed brake before stationary spin")
	release()
	car.free()
	# A frota tem tanto a dirigibilidade original quanto o trem de força de rua completo.
	for id in ["police_cruiser", "desert_faisca"]:
		car = VEHICLE.new()
		car.archetype = id
		root.add_child(car)
		car.place(Vector3(0,.05,0),0)
		car.controlled = true
		await frames(5)
		Input.action_press("accelerate", .35)
		Input.action_press("brake", .7)
		await frames(35)
		check(car.burnout_strength() > .3 and absf(car.speed) < .05, id+": partial pedals hold stationary burnout")
		check(car.effects.tire_effects.last_modes == ["smoke","smoke"], id+": original and full handling reach tire effects")
		car.archetype = "army_tank"
		check(car.burnout_strength() == 0.0, "tank tracks do not burn rubber")
		release()
		car.free()
	ground.free()
	await process_frame
	print("VEHICLE_BURNOUT checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
