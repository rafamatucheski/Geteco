extends SceneTree

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, msg: String) -> void:
	if ok:
		print("PASS ", msg)
	else:
		failures += 1
		print("FAIL ", msg)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	
	var residence_script = load("res://world/harbor/residences/ResidenceProperty.gd")
	var cemetery_script = load("res://world/harbor/cemetery/CemeteryKeeperHome.gd")
	
	print("--- Testing ResidenceProperty variants ---")
	for variant in [0, 1, 2]:
		var house = residence_script.new()
		house.house_variant = variant
		house.position = Vector2(variant * 400.0, 0.0)
		world.add_child(house)
		await physics_frame
		await physics_frame
		
		var footprint = house.get_node_or_null("HouseFootprint")
		check(footprint != null, "Variant %d has HouseFootprint" % variant)
		if footprint:
			check(footprint.collision_layer == 1, "Variant %d footprint layer == 1" % variant)
			check(footprint.collision_mask == 0, "Variant %d footprint mask == 0" % variant)
			check(footprint.is_in_group("building_blocker"), "Variant %d in building_blocker" % variant)
			check(footprint.is_in_group("building_geodata"), "Variant %d in building_geodata" % variant)
			var solids: Array = footprint.get_meta("solid_rects_local", [])
			check(not solids.is_empty(), "Variant %d has solid_rects_local meta" % variant)
			if not solids.is_empty():
				var solid: Rect2 = solids[0]
				print("  Variant %d solid rect: %s" % [variant, str(solid)])
				check(solid.position.y <= -100.0, "Variant %d solid rect covers elevated roof (min_y=%.1f <= -100)" % [variant, solid.position.y])
		
		# Test roof points: elevated roof area north of the floor footprint (Y = -90)
		var roof_global = house.to_global(Vector2(0, -90))
		var query := PhysicsPointQueryParameters2D.new()
		query.position = roof_global
		query.collision_mask = 1
		var hits = world.get_world_2d().direct_space_state.intersect_point(query)
		check(not hits.is_empty(), "Variant %d roof point (0, -90) is blocked by collision" % variant)
		
		# Test actor walking south from the north: must collide before crossing the roof
		var actor := CharacterBody2D.new()
		actor.collision_layer = 2
		actor.collision_mask = 1
		var col_shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 5.0
		col_shape.shape = circle
		actor.add_child(col_shape)
		world.add_child(actor)
		
		actor.position = house.to_global(Vector2(0, -180))
		await physics_frame
		var hit = actor.move_and_collide(Vector2(0, 100))
		check(hit != null, "Variant %d southwards walk from north hits roof collision" % variant)
		var local_stop = house.to_local(actor.position)
		check(local_stop.y < -95.0, "Variant %d stopped north of roof interior (stopped at y=%.1f)" % [variant, local_stop.y])
		actor.queue_free()
		
		# Test entrance clearance: entrance_offset must not collide
		var entrance_query := PhysicsPointQueryParameters2D.new()
		entrance_query.position = house.entrance_position()
		entrance_query.collision_mask = 1
		var entrance_hits = world.get_world_2d().direct_space_state.intersect_point(entrance_query)
		check(entrance_hits.is_empty(), "Variant %d entrance is clear for interaction" % variant)
		
		house.queue_free()
		await physics_frame
	
	print("--- Testing CemeteryKeeperHome ---")
	var cem = cemetery_script.new()
	cem.position = Vector2(2000, 0)
	world.add_child(cem)
	await physics_frame
	await physics_frame
	
	var cem_footprint = cem.get_node_or_null("HouseFootprint")
	check(cem_footprint != null, "CemeteryKeeperHome has HouseFootprint")
	if cem_footprint:
		check(cem_footprint.collision_layer == 1, "Cemetery footprint layer == 1")
		check(cem_footprint.collision_mask == 0, "Cemetery footprint mask == 0")
		check(cem_footprint.is_in_group("building_blocker"), "Cemetery footprint in building_blocker")
		check(cem_footprint.is_in_group("building_geodata"), "Cemetery footprint in building_geodata")
		var solids: Array = cem_footprint.get_meta("solid_rects_local", [])
		check(not solids.is_empty(), "Cemetery has solid_rects_local meta")
		if not solids.is_empty():
			var solid: Rect2 = solids[0]
			print("  Cemetery solid rect: %s" % str(solid))
			check(solid.position.y <= -90.0, "Cemetery solid rect covers roof (min_y=%.1f <= -90)" % solid.position.y)
	
	# Test cemetery roof point: (0, -70)
	var cem_roof_global = cem.to_global(Vector2(0, -70))
	var cem_query := PhysicsPointQueryParameters2D.new()
	cem_query.position = cem_roof_global
	cem_query.collision_mask = 1
	var cem_hits = world.get_world_2d().direct_space_state.intersect_point(cem_query)
	check(not cem_hits.is_empty(), "Cemetery roof point (0, -70) is blocked by collision")
	
	# Test cemetery entrance clearance
	var cem_entrance_pos = cem.to_global(cem.entrance.position)
	var cem_ent_query := PhysicsPointQueryParameters2D.new()
	cem_ent_query.position = cem_entrance_pos
	cem_ent_query.collision_mask = 1
	var cem_ent_hits = world.get_world_2d().direct_space_state.intersect_point(cem_ent_query)
	check(cem_ent_hits.is_empty(), "Cemetery entrance is clear for interaction")
	
	cem.queue_free()
	await physics_frame
	
	print("RESIDENCE_ROOF_GEODATA failures=", failures)
	quit(0 if failures == 0 else 1)
