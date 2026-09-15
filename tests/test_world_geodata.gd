extends SceneTree

const PERIMETER := preload("res://world/harbor/WorldPerimeter.gd")
var failures: Array[String] = []

func _initialize() -> void: call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var perimeter := PERIMETER.new()
	world.add_child(perimeter)
	for point in [Vector2(715,1800), Vector2(-750,550), Vector2(-1250,1120), Vector2(3800,400), Vector2(6600,1700), Vector2(7300,-4560), Vector2(8950,-4560), Vector2(3570,2300), Vector2(4250,3170), Vector2(5000,5500), Vector2(12000,-7500)]:
		_check(perimeter.contains_point(point), "Playable access excluded: %s" % point)
	for point in [Vector2(-2000,1700), Vector2(1000,-300), Vector2(6600,6000), Vector2(17000,-5000), Vector2(10000,-11000), Vector2(10000,500), Vector2(4200,1500)]:
		_check(not perimeter.contains_point(point), "Outside point accepted: %s" % point)
	var actor := CharacterBody2D.new()
	# The unused eastern/southern forest was removed; railway and village remain.
	var mountain_offset := Vector2(4300, -4960)
	for point in [Vector2(11000, 0), Vector2(6500, 3500), Vector2(11000, -4000)]:
		_check(not perimeter.contains_point(point + mountain_offset), "Trimmed mountain land remains walkable: %s" % point)
	for point in preload("res://world/shared/rail/HarborMountainRailRoute.gd").MOUNTAIN_POINTS:
		_check(perimeter.contains_point(point + mountain_offset), "Mountain trim cuts railway: %s" % point)
	var actor_shape := CollisionShape2D.new()
	actor_shape.shape = CircleShape2D.new()
	actor_shape.shape.radius = 10.0
	actor.add_child(actor_shape)
	actor.collision_layer = 2
	actor.collision_mask = 1
	world.add_child(actor)
	actor.position = Vector2(715,1800)
	_check(not perimeter.recover_actor(actor), "Valid player position moved")
	actor.position = Vector2(-50000,0)
	actor.velocity = Vector2(600,0)
	_check(perimeter.recover_actor(actor) and actor.position == Vector2(715,1800) and actor.velocity == Vector2.ZERO, "OOB must restore last valid position and stop motion")
	var buildings: Array[Node2D] = []
	for kind in ["office", "brownstone", "garage", "park"]:
		var building := ProceduralBuilding.new()
		building.position = Vector2(300 + buildings.size()*300, 1700)
		building.building_kind = kind
		world.add_child(building)
		buildings.append(building)
	for north in [false, true]:
		var building := preload("res://world/harbor/HarborBuilding.gd").new()
		building.building_kind = "l_shaped_block"
		building.footprint = Vector2(200,200)
		building.entrance_north = north
		building.position = Vector2(1700 + buildings.size()*250,1700)
		world.add_child(building)
		buildings.append(building)
	await physics_frame
	await physics_frame
	var space := world.get_world_2d().direct_space_state
	# Exercise the actual regional water builder without unrelated city props.
	var east := preload("res://world/harbor/HarborEastDistrict.gd").new()
	east._build_boundaries()
	for child in east.get_children():
		east.remove_child(child)
		world.add_child(child)
	east.free()
	await physics_frame
	await physics_frame
	for position in [Vector2(10000,-3000),Vector2(10000,0)]:
		var query := PhysicsPointQueryParameters2D.new()
		query.position = position
		query.collision_mask = 1
		_check(space.intersect_point(query).is_empty(), "Regional water must not cover the mountain forest: %s" % position)
	actor.position = buildings[0].global_position
	_check(perimeter.recover_actor(actor) and actor.position == Vector2(715,1800), "Invalid save inside a roof must recover outside the building")
	for segment in [
		PackedVector2Array([Vector2(10800,-3460),Vector2(10800,-1960)]),
		PackedVector2Array([Vector2(13800,-4960),Vector2(15300,-4960)]),
		PackedVector2Array([Vector2(-1380,1700),Vector2(-2200,1700)]),
		PackedVector2Array([Vector2(1000,-50),Vector2(1000,-1000)]),
		PackedVector2Array([Vector2(6000,5800),Vector2(7000,5800)]),
		PackedVector2Array([Vector2(5500,5900),Vector2(5500,7000)]),
	]:
		actor.position = segment[0]
		_check(actor.move_and_collide(segment[1]-segment[0]) != null, "High-speed motion crossed exterior wall")
	var walls := 0
	for contour in perimeter.contours:
		for i in contour.size():
			var a: Vector2 = contour[i]
			var b: Vector2 = contour[(i+1)%contour.size()]
			if a.distance_to(b) < 1.0: continue
			var normal := (b-a).normalized().orthogonal()
			_check(not (perimeter.contains_point((a+b)*.5-normal*.1) and perimeter.contains_point((a+b)*.5+normal*.1)), "Wall across internal land seam: %s" % ((a+b)*.5))
			var hit := space.intersect_ray(PhysicsRayQueryParameters2D.create((a+b)*.5-normal*30,(a+b)*.5+normal*30,1))
			_check(not hit.is_empty(), "Unblocked perimeter edge at %s" % ((a+b)*.5))
			walls += 1
	for building in buildings:
		var solids: Array[Rect2] = building.get_solid_rects()
		_check(building.get_node_or_null("PassThroughArea") == null, "Closed buildings must not fade for pass-through")
		for solid in solids:
			for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
				actor.position = building.to_global(solid.get_center() + direction*250)
				var motion := building.to_global(solid.get_center()) - actor.position
				_check(actor.test_move(actor.global_transform,motion), "Actor crossed building %s from %s" % [building.building_kind,direction])
		if building.building_kind == "l_shaped_block":
			var query := PhysicsPointQueryParameters2D.new()
			query.position = building.to_global(Vector2(-50,60) * (-1 if building.entrance_north else 1))
			query.collision_mask = 1
			_check(space.intersect_point(query).is_empty(), "L courtyard must remain open")
	var arcade := ProceduralBuilding.new()
	arcade.position = Vector2(2000,1800)
	arcade.footprint = Vector2(180,254)
	arcade.arcade_depth = 74.0
	world.add_child(arcade)
	await physics_frame
	await physics_frame
	actor.position = arcade.to_global(Vector2(-150,100))
	_check(not actor.test_move(actor.global_transform,Vector2(300,0)), "Authored ground-floor arcade must remain open")
	actor.position = arcade.to_global(Vector2(-150,-70))
	_check(actor.test_move(actor.global_transform,Vector2(300,0)), "Arcade must not make its roof passable")
	print("WORLD_GEODATA contours=%d wall_edges=%d buildings=%d failures=%s" % [perimeter.contours.size(), walls, buildings.size(), failures])
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
