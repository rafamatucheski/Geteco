extends SceneTree
const SCENERY = preload("res://world/mountain_pass/MountainSceneryBuilder.gd")
const GRENADE = preload("res://guns/GrenadeProjectile.tscn")
var failures := 0
var world: Node2D

class Target extends StaticBody2D:
	var hits := 0
	var damage := 0
	func take_damage(amount: int) -> void:
		hits += 1
		damage += amount

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func frames(count: int) -> void:
	for i in count: await physics_frame
func target(point: Vector2, layer: int, size := Vector2(12, 32)) -> Target:
	var body := Target.new()
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = point
	for i in 2:
		var shape := CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		shape.shape.size = size
		body.add_child(shape)
	world.add_child(body)
	return body
func blocked(point: Vector2, radius := 8.0) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = CircleShape2D.new()
	query.shape.radius = radius
	query.transform = Transform2D(0, point)
	query.collision_mask = 1
	return not world.get_world_2d().direct_space_state.intersect_shape(query).is_empty()
func blocked_by(point: Vector2, radius: float, body: CollisionObject2D) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = CircleShape2D.new()
	query.shape.radius = radius
	query.transform = Transform2D(0, point)
	query.collision_mask = 1
	for hit in world.get_world_2d().direct_space_state.intersect_shape(query):
		if hit.collider == body:
			return true
	return false
func run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	world = Node2D.new()
	root.add_child(world)
	current_scene = world
	var car := target(Vector2(80, 0), 2)
	var grenade := GRENADE.instantiate()
	world.add_child(grenade)
	grenade.setup(Vector2.ZERO, Vector2.RIGHT, 950.0, null)
	await frames(7)
	check(grenade.position.x < 69 and grenade.velocity.x < 0, "Fast grenade strikes vehicle layer and rebounds")
	check(grenade.z_velocity < 0, "Vehicle contact sends grenade down toward ground")
	await frames(75)
	check(grenade.z_height < 0.5 and grenade.velocity.length() < 1, "Grenade settles on ground before fuse expires")
	var settled: Vector2 = grenade.global_position
	await frames(45)
	var blasts := get_nodes_in_group("explosion_visuals")
	check(not is_instance_valid(grenade) and not blasts.is_empty() and blasts[0].global_position.distance_to(settled) < 1.0, "Fuse detonates at the settled ground position")
	car.queue_free()
	await frames(2)
	var thrower := CharacterBody2D.new()
	world.add_child(thrower)
	var near_wall := target(Vector2(15,0), 1, Vector2(4,40))
	await frames(2)
	grenade = GRENADE.instantiate()
	world.add_child(grenade)
	grenade.setup(Vector2(22,0), Vector2.RIGHT, 950, thrower)
	check(grenade.position.x < 13, "Hand offset cannot spawn grenade through nearby cover")
	await frames(3)
	check(grenade.position.x < 13 and grenade.velocity.x < 0, "Grenade also rebounds from solid walls")
	grenade.queue_free()
	near_wall.queue_free()
	thrower.queue_free()
	await frames(2)
	var exposed := target(Vector2(0, 80), 4)
	var shielded := target(Vector2(80, 0), 4)
	var wall := target(Vector2(40, 0), 1, Vector2(8, 64))
	await frames(2)
	grenade = GRENADE.instantiate()
	world.add_child(grenade)
	grenade.setup(Vector2.ZERO, Vector2.ZERO, 0, null)
	grenade.explode()
	check(exposed.hits == 1, "Multiple collision shapes receive only one blast hit")
	check(exposed.damage > 0 and exposed.damage < 180, "Blast damage falls off with distance")
	check(shielded.hits == 0, "Wall shields person from explosion")
	exposed.queue_free()
	shielded.queue_free()
	wall.queue_free()
	SCENERY._init_dirt_roads()
	SCENERY.build_lake_and_rapids(world)
	var bridge := StaticBody2D.new()
	bridge.collision_layer = 1
	bridge.collision_mask = 0
	world.add_child(bridge)
	SCENERY.build_detailed_footbridge(bridge)
	preload("res://world/mountain_pass/MountainFootbridgeCollision.gd").install(bridge)
	var shop := preload("res://world/mountain_pass/MountainGunShopFacade.gd").new()
	shop.position = Vector2(7750,-220)
	world.add_child(shop)
	await frames(2)
	check(blocked(Vector2(7145,100)), "Deep visible lake blocks walking and driving")
	check(not blocked(Vector2(6790,200)), "Shallow visible water is walkable")
	check(not blocked(Vector2(7050,40)), "Footbridge deck stays walkable")
	check(blocked(Vector2(7315,69)), "Footbridge rail stops sideways exits")
	check(blocked_by(Vector2(6928,40), 20, bridge), "Entrance bollard blocks vehicle width")
	check(not blocked(Vector2(6895,40), 9), "Pedestrian fits through center of bridge entrance")
	var walker := CharacterBody2D.new()
	walker.collision_layer = 2
	walker.collision_mask = 1
	walker.position = Vector2(6900,40)
	var walker_shape := CollisionShape2D.new()
	var walker_circle := CircleShape2D.new()
	walker_circle.radius = 9.0
	walker_shape.shape = walker_circle
	walker.add_child(walker_shape)
	world.add_child(walker)
	await frames(2)
	check(walker.move_and_collide(Vector2(400,0)) == null, "Pedestrian physically crosses bridge center")
	walker.position = Vector2(6950,40)
	var rail_hit := walker.move_and_collide(Vector2(0,60))
	check(rail_hit != null and rail_hit.get_collider() == bridge, "Pedestrian cannot pass through bridge side rail")
	walker.queue_free()
	var road: Curve2D = SCENERY.dirt_road_curves[1]
	var access_clear := true
	for sample in range(0, int(road.get_baked_length()), 12):
		if blocked(road.sample_baked(sample), 35): access_clear = false
	var main_road := preload("res://world/mountain_pass/MountainPassRoad.gd").new()
	main_road._build_curve()
	var vale: Curve2D = SCENERY.dirt_road_curves[0]
	var vale_start := vale.get_point_position(0)
	check(vale_start.distance_to(main_road.curve.get_closest_point(vale_start)) < 1.0, "East Vale dirt road joins highway center without a gap")
	var bridge_landing := preload("res://world/mountain_pass/MountainLakeGeometry.gd").DECK.position + Vector2(0,26)
	check(absf(bridge_landing.distance_to(main_road.curve.get_closest_point(bridge_landing)) - main_road.road_width * 0.5) < 2.0, "Bridge decking meets highway edge without covering driving lane")
	var driveway: Array = preload("res://world/mountain_pass/MountainVillageLayout.gd").ACCESS_PATHS[0]
	var vale_clear_of_walkway := true
	for offset in range(0, 201, 20):
		var point := vale.sample_baked(float(offset), true)
		for i in range(driveway.size() - 1):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point, driveway[i], driveway[i + 1])) < 60.0:
				vale_clear_of_walkway = false
	check(vale_clear_of_walkway, "East Vale first stretch stays clear of village walkway")
	var main_clear := true
	for point in main_road.smooth_points:
		if point.x > 6500 and point.y > -400 and point.y < 500 and blocked(point,74): main_clear = false
	check(main_clear, "Lake and bridge leave full mountain highway clear")
	main_road.free()
	check(access_clear, "Full dirt road width reaches front parking without crossing water")
	check(not blocked(Vector2(7750,-90), 20), "Parking aisle and entrance approach remain clear")
	var resident := preload("res://world/mountain_pass/WinterResident.gd").new()
	resident.position = Vector2(7760,-100)
	world.add_child(resident)
	resident.take_damage(100)
	await frames(3)
	check(resident.is_dead and get_nodes_in_group("ground_blood").size() == 1, "Lethal damage leaves visible persistent blood")
	var actor := CharacterBody2D.new()
	actor.add_to_group("player")
	actor.position = Vector2(7145,100)
	world.add_child(actor)
	await frames(20)
	var water_system: Node2D = world.get_node("WaterSystemDetailed")
	var deep_water: Node2D = water_system.get_node("DeepWaterBoundary")
	check(not Geometry2D.is_point_in_polygon(actor.position, deep_water.water), "Old save inside deep water recovers to shallows")
	actor.position = Vector2(6790, 200)
	await frames(2)
	var shallow_water: Node2D = water_system.get_node("AlpineLakeShallows")
	check(shallow_water.is_water_at(actor), "Walkable shallow water uses the same shoreline as its visible surface")
	check(preload("res://audio/footsteps/FootstepSurfaceResolver.gd").resolve(actor, false) == "water", "Shallow water makes real water footsteps")
	actor.queue_free()
	if "--capture" in OS.get_cmdline_user_args(): await capture()
	world.queue_free()
	await process_frame
	print("MOUNTAIN_CONTACT failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func capture() -> void:
	world.queue_free()
	await process_frame
	root.size = Vector2i(1440,900)
	root.content_scale_size = root.size
	root.get_node("SaveManager").clear_pending_save()
	world = load("res://world/mountain_pass/MountainPass.tscn").instantiate()
	world.connect_to_harbor = false
	world.spawn_player_on_ready = false
	world.spawn_suv_on_ready = false
	root.add_child(world)
	current_scene = world
	while not world.region_ready: await process_frame
	world.parallax.hide()
	world.storm_manager.set_process(false)
	for layer in world.find_children("*", "CanvasLayer", true, false): layer.hide()
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	for view in [{"name":"lake", "point":Vector2(7040,80),"zoom":1.7},{"name":"shop", "point":Vector2(7730,-180),"zoom":2.8}]:
		camera.position = view.point
		camera.zoom = Vector2.ONE * view.zoom
		if view.name == "shop":
			var resident := preload("res://world/mountain_pass/WinterResident.gd").new()
			resident.position = Vector2(7800,-65)
			world.add_child(resident)
			resident.take_damage(100)
		for i in 150: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/mountain-contact-" + view.name + ".png")
