extends SceneTree
## Main real, C# e física ativos; tiros pelo Gameplay e carros pela direção externa.
const ACTOR := preload("res://scripts/Actor.gd")
const DANGER := preload("res://gameplay/civilian_reactions/PedestrianVehicleDanger.gd")
var world
var director
var failures: Array[String] = []
var checks := 0
var folder := "res://evidence/auditoria-viaria/2026-10-10-fuga-pedestres"

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String, detail := "") -> void:
	checks += 1
	print("PEDESTRIAN_ESCAPE ", "PASS " if ok else "FAIL ", label, " ", detail)
	if not ok: failures.append(label)
func seconds(duration: float) -> void:
	var deadline := Time.get_ticks_msec() + int(duration * 1000)
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		world.gameplay.health = 100
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder + "/" + label + ".png")
func ground(point: Vector3) -> Vector3:
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 3, point - Vector3.UP * 3, 1))
	return hit.position + Vector3.UP * 0.08 if not hit.is_empty() else point
func person(point: Vector3, identity: int = 0) -> CharacterBody3D:
	var actor := ACTOR.new()
	actor.identity = identity
	world.add_child(actor)
	actor.global_position = ground(point)
	world.people.append(actor)
	return actor
func discard(actor: Node) -> void:
	world.people.erase(actor)
	actor.queue_free()

func vehicle_case(reverse: bool, blocked_side: bool) -> void:
	var center := Vector3(-313, 0, 23.5)
	var witness := person(center)
	var wall: StaticBody3D
	if blocked_side:
		wall = StaticBody3D.new()
		wall.collision_layer = 1
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(12, 3, 0.4)
		collider.shape = shape
		wall.add_child(collider)
		world.add_child(wall)
		wall.global_position = ground(center) + Vector3(0, 1.5, 1.4)
	await seconds(0.3)
	var start := witness.global_position
	var car = world.production.spawn_vehicle("union_sedan", ground(center + Vector3.RIGHT * 18), -PI * 0.5 if reverse else PI * 0.5)
	check(is_instance_valid(car), "carro físico na calçada " + str(reverse))
	if not is_instance_valid(car): discard(witness); return
	car.set_external_driver(true)
	car.speed = -8 if reverse else 10
	car.horizontal_velocity = Vector3.LEFT * absf(car.speed)
	car.velocity = car.horizontal_velocity
	car.throttle_input = -0.35 if reverse else 0.35
	car.brake_input = false
	check(not DANGER.assess(car, start).is_empty(), "detecta aproximação " + ("em ré" if reverse else "de frente"))
	check(DANGER.assess(car, start + Vector3.BACK * 8).is_empty(), "carro na pista vizinha não assusta")
	check(DANGER.assess(car, car.position + Vector3.RIGHT * 8).is_empty(), "carro que se afasta não assusta")
	check(DANGER.assess(car, start + Vector3.UP * 8).is_empty(), "outra altura não assusta")
	var reacted := false
	var side_shift := 0.0
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		reacted = reacted or director.reactors.has(witness.get_instance_id())
		side_shift = maxf(side_shift, absf(witness.position.z - start.z))
		if car.position.x < start.x - 6: break
	check(reacted, "percebe carro sem buzina")
	check(side_shift > 2, "sai lateralmente da trajetória", "desvio=%.2f" % side_shift)
	check(witness.health == 100 and not witness.has_meta("street_down"), "evita atropelamento físico")
	if blocked_side:
		check(witness.position.z < start.z - 2, "parede faz escolher o outro lado")
	await capture("02_re" if reverse else "01_carro_calcada")
	car.queue_free()
	if wall != null: wall.queue_free()
	director.reset_population()
	discard(witness)
	await seconds(0.2)

func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(180).timeout.connect(func(): quit(124))
	DirAccess.make_dir_recursive_absolute(folder)
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play, "Main pronta")
	if world.session == null or not world.session.ready_for_play: world.free(); quit(1); return
	check(world.dispatch.router._native_graph() != null, "backend C# ativo")
	world.dispatch.enabled = false
	world.player.teleport(ground(Vector3(-313, 0, 31)))
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.target_size = 42
	world.camera.initialized = false
	world.production.region.prepare_collision_at(Vector3(-313, 0, 23.5))
	await seconds(4)
	director = world.production.civilian_reactions
	# Isola apenas a população para medir trajetórias de fixtures na rua real.
	world.production.set_process(false)
	director.reset_population()
	for actor in world.people: actor.set_physics_process(false)
	world.people.clear()
	await vehicle_case(false, false)
	await vehicle_case(true, true)
	var witnesses: Array = []
	for identity in [0, 11, 15, 18]:
		var actor := person(Vector3(-321 + witnesses.size() * 5, 0, 23.5), identity)
		actor.route = PackedVector3Array([actor.position, actor.position + Vector3.RIGHT * 10])
		witnesses.append({"actor": actor, "start": actor.position})
	var protected := person(Vector3(-312, 0, 27))
	protected.set_meta("invulnerable", true)
	var owned := person(Vector3(-310, 0, 27))
	owned.controlled_automatically = true
	world.production.state.grant_weapon("pistol")
	world.production.state.equip_weapon("pistol")
	check(world.gameplay.fire_at(world.player.position + Vector3.BACK * 20), "disparo real aceito")
	await seconds(0.1)
	for record in witnesses:
		var state: Dictionary = director.reactors.get(record.actor.get_instance_id(), {})
		check(not state.is_empty() and state.phase == "panic" and record.actor.automatic_direction.length() > 0.5, "tiro inicia corrida, temperamento=" + str(record.actor.identity))
	check(not director.reactors.has(protected.get_instance_id()), "protegido permanece intacto")
	check(not director.reactors.has(owned.get_instance_id()), "respeita dono de movimento")
	await seconds(1.5)
	for record in witnesses:
		check(record.actor.position.distance_to(record.start) > 3, "fuga desloca civil=" + str(record.actor.identity), str(record.actor.position.distance_to(record.start)))
	await capture("03_tiro_fuga")
	world.gameplay.clear_wanted()
	await seconds(15)
	for record in witnesses:
		check(not director.reactors.has(record.actor.get_instance_id()) and not record.actor.controlled_automatically and is_equal_approx(record.actor.speed, 1.6), "retoma rotina civil=" + str(record.actor.identity))
	check(protected.health == 100 and not protected.dead, "proteção de dano preservada")
	print("PEDESTRIAN_ESCAPE checks=", checks, " failures=", failures.size())
	FileAccess.open(folder + "/result.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "stats": director.stats}, "\t"))
	world.free()
	quit(0 if failures.is_empty() else 1)
