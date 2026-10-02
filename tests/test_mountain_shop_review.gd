extends SceneTree
## Physical/storefront contracts; rendered depth and performance are measured
## separately in the real session, not certified by this headless check.
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const RESIDENTS := preload("res://world/places/OriginalResidents.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _run() -> void:
	for id in ["mountain_outfitters", "mountain_boutique", "mountain_village_outfitters"]:
		var room = PLACES.create_place(id)
		root.add_child(room)
		var player = preload("res://scripts/Actor.gd").new()
		player.is_player = true
		root.add_child(player)
		player.set_physics_process(false)
		var staff = preload("res://scripts/Actor.gd").new()
		staff.controlled_automatically = true
		root.add_child(staff)
		staff.set_physics_process(false)
		await physics_frame
		await physics_frame
		check(room.definition.npcs.size() == 1, id + " has one real attendant")
		var definition: Dictionary = room.definition.npcs[0]
		staff.global_position = room.to_global(definition.local_position) + Vector3.UP * .08
		var old_model: Node = staff.visual.get_child(0)
		staff.visual.remove_child(old_model)
		old_model.free()
		var model := RESIDENTS.create_model(definition)
		staff.visual.add_child(model)
		# Let the physics server publish the authored staff transform before
		# sweeping another body past its previous construction position.
		await physics_frame
		check(model.get("hand_targets") != null, id + " current articulated staff")
		check(staff.move_and_collide(Vector3.UP * .001, true) == null, id + " staff whole body fits behind counter")
		var service: Vector3 = room.interaction_points.service
		for point in [room.spawn_position, room.exit_position, service]:
			player.global_position = point + Vector3.UP * .08
			check(player.move_and_collide(Vector3.UP * .001, true) == null, id + " player whole body fits " + str(point))
		# Customer passage: entry to centre aisle, then across to the counter.
		var route := [room.spawn_position, Vector3(0, 0, service.z), service]
		for i in range(route.size() - 1):
			player.global_position = route[i] + Vector3.UP * .08
			var contact: KinematicCollision3D = player.move_and_collide(route[i + 1] - route[i], true)
			if contact != null: print("SHOP_ROUTE_BLOCKER ", id, " ", contact.get_collider().get_path(), " ", contact.get_position(), " route=", route)
			check(contact == null, id + " open customer route " + str(i))
		# Isolate furniture contacts from the second actor while sweeping.
		player.collision_layer = 0
		staff.collision_layer = 0
		for actor in [player, staff]:
			for body in room.solid_bodies:
				var bounds: AABB = body.get_meta("bounds")
				if body.name == "Floor" or bounds.size.y < .15: continue
				# Sweep into every furniture volume from all four faces. Other
				# solids may stop the sweep sooner; crossing the target may not.
				for side in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
					var extent: float = bounds.size.x * .5 if side.x != 0 else bounds.size.z * .5
					var start: Vector3 = Vector3(bounds.get_center().x, .08, bounds.get_center().z) + side * (extent + .7)
					actor.global_position = room.to_global(start)
					check(actor.move_and_collide(-side * (extent + .9), true) != null, id + " solid sweep " + str(body.name) + " " + str(side))
				for corner in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
					var centre := Vector3(bounds.get_center().x, .08, bounds.get_center().z)
					var offset := Vector3(corner.x * (bounds.size.x * .5 + .7), 0, corner.y * (bounds.size.z * .5 + .7))
					actor.global_position = room.to_global(centre + offset)
					check(actor.move_and_collide(-offset, true) != null, id + " solid corner " + str(body.name) + " " + str(corner))
		var mannequins := 0
		for node in room.model.get_children():
			if node.get_script() != preload("res://world/places/ShopMannequin.gd"): continue
			mannequins += 1
			check(node.process_mode == Node.PROCESS_MODE_DISABLED, id + " mannequin stays static")
			check(node.scale.is_equal_approx(Vector3.ONE), id + " human mannequin scale")
			check(not node.find_children("*", "MeshInstance3D", true, false).is_empty(), id + " mannequin visible geometry")
		check(mannequins >= 1, id + " dressed modern mannequin")
		await _facade(room.definition, player)
		staff.free()
		player.free()
		room.free()
		await physics_frame
	print("MOUNTAIN_SHOP_REVIEW checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _facade(definition: Dictionary, player: CharacterBody3D) -> void:
	var facade := preload("res://assets/regions/source/world/mountain_pass/ResortShop3D.gd").new()
	facade.position = definition.exterior_position
	root.add_child(facade)
	var door := preload("res://world/places/WalkupFacadeDoor.gd").install(facade, definition)
	await physics_frame
	var start := facade.to_global(Vector3(0, .08, 2.62))
	player.global_position = start
	check(player.move_and_collide(Vector3(0, 0, -1.1), true) != null, definition.id + " facade closed door blocks player")
	door.set_open_amount(1.0)
	await physics_frame
	player.global_position = start
	check(player.move_and_collide(Vector3(0, 0, -1.1), true) == null, definition.id + " facade open door passes player")
	var count := 0
	for node in facade.get_children():
		if node.get_script() != preload("res://world/places/ShopMannequin.gd"): continue
		count += 1
		check(node.process_mode == Node.PROCESS_MODE_DISABLED, definition.id + " window display static")
		check(node.spine.mesh is ArrayMesh, definition.id + " window tailored body rather than cylinder")
	check(count == 2, definition.id + " two modern window displays")
	facade.free()
	await physics_frame
