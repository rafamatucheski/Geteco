extends SceneTree
const PARTICLES := preload("res://world/shared/combat/VehicleDamageParticles.gd")
const EXPLOSION := preload("res://world/shared/combat/ExplosionVisual.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	seed(13092026)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.size = Vector2i(1280,720)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = Vector2(320,180)
	camera.zoom = Vector2(2,2)
	var street := Polygon2D.new()
	street.polygon = PackedVector2Array([Vector2(-100,-100),Vector2(900,-100),Vector2(900,600),Vector2(-100,600)])
	street.color = Color(0.18,0.20,0.22)
	street.z_index = -10
	world.add_child(street)
	var traffic = load("res://world/shared/traffic/TrafficVehicle.tscn").instantiate()
	world.add_child(traffic)
	traffic.configure_as_parked()
	traffic.ensure_presentation()
	traffic.position = Vector2(170,220)
	traffic._ensure_smoke_emitter()
	traffic._ensure_flame_particles()
	var player_car = load("res://world/shared/traffic/SavedPlayerCar.tscn").instantiate()
	world.add_child(player_car)
	player_car.position = Vector2(320,220)
	var police = load("res://EmergencyVehicle.tscn").instantiate()
	world.add_child(police)
	police.position = Vector2(470,220)
	for car in [traffic, player_car, police]:
		car.set_process(false)
		car.set_physics_process(false)
		for emitter in [car.smoke_emitter, car.flame_particles]:
			check(emitter != null, str(car.name) + " damage emitter exists")
			if emitter == null: continue
			check(emitter.texture == PARTICLES.texture() and emitter.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR, str(car.name) + " shares smooth filtered texture")
			check(emitter.color_ramp != null and emitter.color_ramp.sample(1.0).a == 0, str(car.name) + " fades to transparent")
			check(emitter.amount <= 20 and emitter.scale_amount_max * 64 <= 32, str(car.name) + " bounded particles and world size")
			emitter.emitting = true
	await create_timer(1.5).timeout
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/combat-vehicles-0913/fire-smoke.png")
	EXPLOSION.spawn(world, Vector2(320,220), 180, true)
	await create_timer(0.22).timeout
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/combat-vehicles-0913/explosion.png")
	await create_timer(3.7).timeout
	check(get_nodes_in_group("explosion_visuals").is_empty(), "explosion releases burst after lifetime")
	world.queue_free()
	await process_frame
	print("VEHICLE_PARTICLES failures=", failures)
	quit(0 if failures.is_empty() else 1)
