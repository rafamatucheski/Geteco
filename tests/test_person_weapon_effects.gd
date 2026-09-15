extends SceneTree
var failures := 0
var world: Node2D
var output := "D:/geteco/artifacts/person-weapon-effects"

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func frames(count: int) -> void:
	for i in count: await physics_frame

func person(point: Vector2) -> Node2D:
	var body = load("res://characters/AnimatedPedestrian3D.gd").new()
	body.position = point
	world.add_child(body)
	body.ensure_presentation()
	body.set_physics_process(false)
	return body

func flame_at(point: Vector2) -> Node2D:
	var flame = load("res://guns/FlameJet.tscn").instantiate()
	flame.position = point
	world.add_child(flame)
	flame.setup(point, Vector2.RIGHT, null)
	return flame

func screenshot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func run() -> void:
	create_timer(35).timeout.connect(func(): quit(2))
	DirAccess.make_dir_recursive_absolute(output)
	root.get_node("SaveManager")._save_dir = output.path_join("test-saves") + "/"
	root.size = Vector2i(1000, 650)
	RenderingServer.set_default_clear_color(Color("30383b"))
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera2D.new()
	camera.position = Vector2(160, 80)
	camera.zoom = Vector2(3, 3)
	world.add_child(camera)
	var burning = person(Vector2(135, 70))
	var untouched = person(Vector2(230, 150))
	await frames(3)
	var initial: int = burning.health
	flame_at(Vector2(80, 70))
	await frames(12)
	check(burning.health < initial and burning.has_node("PersonBurning"), "Actual flame overlap ignites person")
	check(not untouched.has_node("PersonBurning"), "Out-of-cone person stays unburned")
	var fire: Node2D = burning.get_node_or_null("PersonBurning")
	if fire == null:
		quit(1)
		return
	var after_hit: int = burning.health
	await create_timer(0.8).timeout
	check(burning.health < after_hit, "Damage continues after jet disappears")
	check(burning.is_scared, "Burning civilian panics")
	burning.position += Vector2(15, 0)
	await frames(2)
	check(fire.global_position.distance_to(burning.global_position) < 0.1, "Flames follow moving victim")
	flame_at(burning.position - Vector2(55, 0))
	await frames(10)
	check(burning.get_node("PersonBurning") == fire and fire.remaining > 5.5, "Repeated hits renew one fire without stacking statuses")
	await screenshot("burning-person")
	# Finite status expiration, without waiting on wall-clock time.
	# Keep the victim alive while exercising the final smoke-tail boundary.
	burning.health = 1000
	for i in 12: fire._physics_process(0.5)
	check(not fire.flames.emitting, "Expired flames stop emitting during smoke tail")
	preload("res://guns/combat/PersonBurning.gd").ignite(burning)
	check(fire.flames.emitting and fire.remaining == 6.0, "Reigniting during smoke tail restarts visible fire")
	for i in 15: fire._physics_process(0.5)
	await frames(2)
	check(not burning.has_node("PersonBurning"), "Fire and smoke clean up after finite duration")
	var wall := StaticBody2D.new()
	wall.position = Vector2(320, 70)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(10, 90)
	shape.shape = rect
	wall.add_child(shape)
	world.add_child(wall)
	var protected = person(Vector2(355, 70))
	await frames(3)
	flame_at(Vector2(295, 70))
	await frames(15)
	check(protected.health == protected.max_health and not protected.has_node("PersonBurning"), "Solid wall blocks ignition and fire damage")
	var rocket_victim = person(Vector2(185, 70))
	var survivor = person(Vector2(185, -58))
	await frames(3)
	var rocket = load("res://guns/Bullet.tscn").instantiate()
	rocket.position = Vector2(150, 70)
	rocket.damage = 200
	rocket.is_explosive = true
	world.add_child(rocket)
	await frames(14)
	check(rocket_victim.is_dead and rocket_victim.has_meta("explosion_remains"), "Real RPG impact dismembers lethal victim")
	check(not survivor.is_dead and survivor.health < survivor.max_health, "Outer blast survivor is not killed by extra run-over damage")
	var grenade_victim = person(Vector2(270, 70))
	await frames(3)
	var grenade = load("res://guns/GrenadeProjectile.tscn").instantiate()
	world.add_child(grenade)
	grenade.setup(Vector2(280, 70), Vector2.ZERO, 0, null)
	grenade.current_fuse = 0.08
	await frames(15)
	check(grenade_victim.is_dead and grenade_victim.has_meta("explosion_remains"), "Real grenade fuse dismembers lethal victim")
	check(protected.health == protected.max_health, "Solid cover blocks grenade blast")
	for victim in [rocket_victim, grenade_victim]:
		if not victim.has_meta("explosion_remains"): continue
		var remains: Node2D = victim.get_meta("explosion_remains")
		check(not victim.visible and remains.pieces.size() >= 4 and remains.pieces.size() <= 6, "Variable anatomical fragments replace whole body")
		var again = preload("res://guns/combat/ExplosionRemains.gd").spawn(victim, victim.position)
		check(again == remains, "Repeated explosion cannot duplicate fragments")
	await create_timer(2).timeout
	await screenshot("explosion-remains")
	for remains in get_nodes_in_group("explosion_remains"):
		for piece in remains.pieces:
			check(piece.height == 0 and piece.velocity == Vector2.ZERO, "Physical fragments settle")
	# A lethal fire must use normal death, without explosion fragmentation.
	var frail = person(Vector2(50, 70))
	frail.health = 8
	await frames(3)
	flame_at(Vector2(5, 70))
	await create_timer(0.9).timeout
	check(frail.is_dead and not frail.has_meta("explosion_remains"), "Persistent fire can kill without dismembering")
	var overlap_victim = person(Vector2(720, 70))
	var isolated := SubViewport.new()
	isolated.world_2d = World2D.new()
	world.add_child(isolated)
	var remote = load("res://characters/AnimatedPedestrian3D.gd").new()
	remote.position = overlap_victim.position
	isolated.add_child(remote)
	remote.set_physics_process(false)
	await frames(3)
	var overlapping_rocket = load("res://guns/Bullet.tscn").instantiate()
	overlapping_rocket.position = overlap_victim.position
	overlapping_rocket.speed = 0
	overlapping_rocket.is_explosive = true
	overlapping_rocket.damage = 200
	world.add_child(overlapping_rocket)
	await frames(6)
	check(overlap_victim.has_meta("explosion_remains"), "Area overlap can spawn physical fragments outside query flushing")
	check(remote.health == remote.max_health and not remote.has_meta("explosion_remains"), "RPG cannot damage actors in another physics world")
	# Let the last projectile's bound lifetime timer finish before teardown.
	await create_timer(2.1).timeout
	world.queue_free()
	await frames(2)
	check(get_nodes_in_group("burning_people").is_empty(), "Scene teardown releases every burn")
	print("PERSON_WEAPON_EFFECTS failures=", failures)
	quit(0 if failures == 0 else 1)
