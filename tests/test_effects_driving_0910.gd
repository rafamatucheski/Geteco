extends SceneTree
const ENGINE := preload("res://audio/VehicleEngineSound.gd")
const SAFETY := preload("res://VehicleMotionSafety.gd")
const BLAST := preload("res://world/shared/combat/ExplosionVisual.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(50.0).timeout.connect(func(): quit(2))
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var fx := WeaponEffects.new()
	world.add_child(fx)
	var player := preload("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	player.set_physics_process(false)
	var hp: int = player.health
	player.get_run_over(Vector2(30,0))
	check(player.health == hp and not player.is_recovering,"walking bump causes no injury or blood")
	player.get_run_over(Vector2(100,0))
	check(player.health < hp and player.is_recovering,"real moving vehicle still injures Dante")
	var blood_count := 0
	for node in world.get_children():
		if node is CPUParticles2D:
			blood_count += 1
			check(node.scale_amount_max * node.texture.get_width() <= 5.01,"blood particles are at most five world pixels")
		check(node.name != "3DBloodPuddle","nonfatal contact does not create death puddle")
	check(blood_count == 1,"one compact burst per injury")
	fx.spawn_shell(Vector2.ZERO,Vector2.RIGHT)
	var shell = fx.get_child(fx.get_child_count()-1)
	shell.set_process(false)
	for i in 70: shell._process(1.0/60.0)
	check(shell.bounces == 2 and shell.height == 0 and shell.velocity.length() < 1,"casing bounces twice then settles")
	shell.set_process(true)
	for id in ["sedan_classic","sport_coupe","summit_suv","courier_van","ranch_single","boxrunner"]:
		var car = ModernTrafficFactory.spawn_parked_vehicle(world,"Damage_"+id,Vector2(2000,2000),0,id,0,Color.RED)
		car.ensure_presentation()
		var model = car.body_model
		check(not model.lamp_sources.is_empty(),id+" has independently tracked lamps after batching")
		var front := Vector3.ZERO
		var rear := Vector3.ZERO
		for node in model.lamp_sources:
			check(is_instance_valid(node),id+" lamp survives batching")
			var data: Dictionary = model.lamp_sources[node]
			if data.front and data.index == 0: front = data.position
			elif not data.front and data.index == 0: rear = data.position
		model.apply_impact(front,Vector3.BACK,15)
		check(model.broken_lamps[0],id+" front contact breaks headlamp")
		check(not model.broken_tail_lamps[0],id+" front contact leaves rear lamps intact")
		model.apply_impact(rear,Vector3.FORWARD,15)
		check(model.broken_tail_lamps[0],id+" rear contact breaks tail lamp")
		check(model.max_deformation() > 0 and model.max_deformation() <= 0.14001,id+" local dent stays bounded")
		car.set_headlights(true)
		car._process(0.016)
		check(not car.headlight.visible,id+" broken headlight stays off during traffic updates")
		car._explode()
		check(model.is_charred and model.broken_lamps == [true,true],id+" explosion chars entire shell and kills lamps")
		car.repair_vehicle()
		check(not model.is_charred and model.max_deformation() == 0 and model.broken_tail_lamps == [false,false],id+" repair restores shell and lamps")
		car.take_damage(car.max_health)
		check(car.is_broken and car.max_speed == 0,id+" fatal damage disables driving")
		car.repair_vehicle()
		check(car.max_speed > 0 and not car.is_exploding,id+" repairing during combustion restores driving")
		car.queue_free()
		await process_frame
	check(SAFETY.collision_damage(160) == 0 and SAFETY.collision_damage(300) < 10,"scrapes harmless and normal crashes survivable")
	check(is_equal_approx(ENGINE.road_top_speed(500),280),"driven top speed reduced by thirty percent")
	var engine := ENGINE.new()
	var speed := 0.0
	for i in 60: speed += 880.0 * engine.drive_force(speed,490) / 60.0
	check(speed < 175 and speed > 100,"first second of acceleration remains controllable")
	var previous_bursts := get_nodes_in_group("explosion_visuals").size()
	var grenade := preload("res://GrenadeProjectile.gd").new()
	world.add_child(grenade)
	grenade.global_position = Vector2(5000,5000)
	grenade.explode()
	var rocket = preload("res://Bullet.tscn").instantiate()
	world.add_child(rocket)
	rocket._trigger_explosion(Vector2(6000,6000))
	rocket.queue_free()
	check(get_nodes_in_group("explosion_visuals").size() == previous_bursts + 2,"real grenade and rocket use the shared explosion effect")
	for i in 40: BLAST.spawn(world,Vector2.ZERO,140)
	check(get_nodes_in_group("explosion_visuals").size() == BLAST.MAX_BURSTS,"chain explosions have a fixed visual budget")
	# Vehicle smoke lasts 3.6s; ordinary blasts last 2.4s.
	await create_timer(3.8).timeout
	check(get_nodes_in_group("explosion_visuals").is_empty(),"explosion effects clean themselves up")
	check(fx._live_effects == 0,"casing budget released after fade")
	print("EFFECTS_DRIVING failures=",failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
