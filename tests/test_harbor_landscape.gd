extends SceneTree

## Spatial render bounds + production capsule sweeps; no collision exemptions.
const PREVIEW := preload("res://district/harbor_preview/HarborPreview.tscn")
var failures: Array[String] = []
var world: Node2D
var protected_polygons: Array[Dictionary] = []
var protected_rects: Array[Dictionary] = []
var trees_checked := 0
var rocks_checked := 0
var shadow_contacts := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("LANDSCAPE: " + message)

func frames(count: int) -> void:
	for index in count:
		await physics_frame

func rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])

func add_path(path: PackedVector2Array, half_width: float, label: String) -> void:
	for polygon in Geometry2D.offset_polyline(path, half_width, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT):
		protected_polygons.append({"polygon":polygon,"id":label})

func run() -> void:
	root.size = Vector2i(1280, 720)
	seed(9007)
	world = PREVIEW.instantiate()
	root.add_child(world)
	current_scene = world
	await frames(10)
	var network: Node2D = world.get_node("RoadNetwork")
	check(network.get_validation_errors().is_empty(), "Actual expanded road graph has no validation errors")
	var graph: Dictionary = network.get_graph_data()
	for road in graph.roads:
		if bool(road.render):
			add_path(road.points, float(road.width) * 0.5 + float(network.SIDEWALK_MARGIN), "road/sidewalk " + str(road.id))
	for junction in graph.junctions:
		var geometry: Dictionary = network._build_junction_surface_geometry(junction, float(network.SIDEWALK_MARGIN) * 2.0)
		if geometry.polygon.size() >= 3:
			protected_polygons.append({"polygon":geometry.polygon,"id":"junction/sidewalk"})
	for name in ["District", "EastDistrict", "NorthDistrict"]:
		var district: Node2D = world.get_node(name)
		for site in district.sites:
			protected_rects.append({"bounds":site.bounds,"id":name+"/"+str(site.id)})
		for access in district.accesses:
			protected_rects.append({"bounds":access.bounds,"id":name+"/"+str(access.id)})
	var north: Node2D = world.get_node("NorthDistrict")
	for point in north.BENCH_POINTS:
		protected_rects.append({"bounds":Rect2(point, Vector2(65,19)),"id":"North bench"})
	protected_rects.append({"bounds":Rect2(6040,960,80,80),"id":"East compass sculpture"})
	protected_rects.append({"bounds":north.FIRE_APRON,"id":"Fire dispatch apron"})
	var cobra: Node2D = world.find_child("CobraNeighborhood", true, false)
	check(cobra != null, "Cobra neighborhood exists")
	if cobra == null:
		await finish()
		return
	check(cobra.has_method("get_visual_terrain_bounds"), "Cobra publishes painted terrain independently from physical land")
	var painted_land: Rect2 = cobra.get_visual_terrain_bounds()
	check(not painted_land.intersects(Rect2(4380,2320,2380,280)), "Cobra paint does not cover the East promenade")
	check(cobra.get_neighborhood_bounds().position.x == 6510.0, "Visual crop preserves authored physical neighborhood and connection")
	for footprint in cobra.get_building_footprints():
		protected_rects.append({"bounds":footprint,"id":"Cobra residence"})
	for path in cobra.get_entrance_paths():
		add_path(path, 18.0, "Cobra entrance")
	for path in cobra.get_pedestrian_routes():
		add_path(path, 18.0, "Cobra public path")
	add_path(cobra.get_secret_drive(), 32.0, "Secret vehicle access")
	for point in [Vector2(7210,1760),Vector2(7270,1780),Vector2(8115,2080),Vector2(8150,2015),Vector2(8195,1760),Vector2(8115,1825),Vector2(8115,1695)]:
		protected_rects.append({"bounds":Rect2(point-Vector2(14,14),Vector2(28,28)),"id":"Actual encounter spawn"})
	for name in ["EastDistrict", "NorthDistrict"]:
		var district: Node2D = world.get_node(name)
		check(district.has_method("get_environment_detail_contract"), name+" exposes authored landscape bounds")
		var contract: Dictionary = district.get_environment_detail_contract()
		for path in contract.paths:
			add_path(path, 18.0, name+" walk path")
	for path in cobra.get_garden_paths():
		add_path(path, 15.0, "Cobra garden path")
	for name in ["EastDistrict", "NorthDistrict"]:
		var district: Node2D = world.get_node(name)
		var contract: Dictionary = district.get_environment_detail_contract()
		var styles := {}
		for tree in contract.trees:
			styles[tree.style] = true
			# Same offset/radius as ProceduralStreetTree.TrunkCollision.
			audit_detail(tree.bounds, tree.get("opaque_bounds",tree.bounds), name+" tree "+str(tree.position), Rect2(tree.position+Vector2(-12,-7)*float(tree.scale),Vector2(24,24)*float(tree.scale)))
			trees_checked += 1
		for rock in contract.rocks:
			audit_detail(rock.bounds, rock.bounds, name+" rock "+str(rock.position))
			rocks_checked += 1
		check(styles.size() >= 3, name+" has at least three structural tree styles")
	var cobra_definitions: Array = cobra.get_landscape_definitions()
	check(cobra_definitions.size() == 11, "All eleven authored Cobra landscape groups survive validation")
	var families := {}
	for item in cobra_definitions:
		families[item.kind] = true
		print("LANDSCAPE cobra_group=", item.id)
		audit_detail(item.bounds, item.get("opaque_bounds",item.bounds), "Cobra " + str(item.id), Rect2(item.center-Vector2.ONE*float(item.trunk_radius),Vector2.ONE*float(item.trunk_radius)*2.0))
		trees_checked += 1
	check(families.size() == 3, "Cobra retains all three landscape families")
	var homes: Array[Node] = []
	for i in 3:
		homes.append(world.get_node("EastDistrict/NorthbankHomes%d" % i))
	check(homes[2].footprint.x >= 176.0, "Workshop lot contains its fixed-width authored facade window")
	var silhouettes := {}
	var building_types := {}
	for house in homes:
		silhouettes[str(house.get("footprint"))] = true
		building_types[str(house.get("building_kind"))] = true
	check(silhouettes.size() == 3, "Three East homes have different physical silhouettes, not just paint")
	check(building_types.size() == 3, "Three East homes use distinct actual building_kind designs")
	var player: CharacterBody2D = world.get_node("Player")
	var capsule: CollisionShape2D = player.get_node("Collision")
	check(capsule.shape is CapsuleShape2D and not capsule.disabled, "Production player capsule is active")
	var original_mask := player.collision_mask
	# Deterministic geometry sweep using the actual production body. No physics masks changed.
	player.set_physics_process(false)
	var all_routes: Array = []
	# The authored garden lane runs beside the road, never through its asphalt.
	all_routes.append(PackedVector2Array([Vector2(4825,1727),Vector2(5390,1727)]))
	all_routes.append(PackedVector2Array([Vector2(5990,-330),Vector2(5990,-130),Vector2(5790,-130)]))
	for route in cobra.get_garden_paths():
		all_routes.append(route)
	all_routes.append(PackedVector2Array([Vector2(5880,-1198),Vector2(5880,-1115)]))
	var garage: Node2D = world.get_node("Interiors").garage_interior
	all_routes.append(PackedVector2Array([garage.to_global(Vector2(-220,130)),garage.to_global(Vector2(-60,130)),garage.to_global(Vector2(0,220))]))
	for route in all_routes:
		player.global_position = route[0]
		await frames(2)
		for i in range(1,route.size()):
			var hit := player.move_and_collide(route[i]-player.global_position)
			check(hit == null and player.global_position.distance_to(route[i]) < 0.1, "Real capsule path remains clear " + str(route[i]))
			if hit != null:
				print("LANDSCAPE blocked_by=", hit.get_collider().get_path(), " at=", player.global_position)
	check(player.collision_mask == original_mask and not capsule.disabled, "Sweeps preserve original collision contract")
	await capture(Vector2(5100,1650), 0.95, "east-garden")
	await capture(Vector2(5570,2410), 0.55, "promenade")
	await capture(Vector2(5900,-1480), 0.8, "north")
	await capture(Vector2(7700,1690), 0.7, "cobra")
	await capture(Vector2(7700,1620), 1.2, "cobra-garden")
	await capture(Vector2(8370,2180), 1.25, "cobra-coast")
	print("LANDSCAPE trees=%d rocks=%d shadow_contacts=%d routes=%d failures=%d" % [trees_checked,rocks_checked,shadow_contacts,all_routes.size(),failures.size()])
	await finish()

func audit_detail(full: Rect2, opaque: Rect2, label: String, trunk := Rect2()) -> void:
	check(full.size.x > 0 and full.size.y > 0 and full.encloses(opaque), label+" publishes complete visual bounds")
	var polygon := rect_polygon(opaque)
	var full_polygon := rect_polygon(full)
	for area in protected_rects:
		if str(area.id) == "North bench" and trunk.has_area():
			check(not trunk.intersects(area.bounds), label+" trunk blocks bench")
			continue # A bench under a canopy is intentional shade, not a blocked seat.
		if full.intersects(area.bounds) and not opaque.intersects(area.bounds):
			shadow_contacts += 1
		check(not opaque.intersects(area.bounds), label+" overlaps "+str(area.id))
	for area in protected_polygons:
		var opaque_overlap := not Geometry2D.intersect_polygons(polygon,area.polygon).is_empty()
		if not opaque_overlap and not Geometry2D.intersect_polygons(full_polygon,area.polygon).is_empty():
			shadow_contacts += 1
		check(not opaque_overlap, label+" obscures "+str(area.id))

func capture(point: Vector2, zoom: float, label: String) -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--capture"):
		return
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.global_position = point
	camera.zoom = Vector2.ONE * zoom
	camera.make_current()
	await frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/geteco/harbor-stage6-"+label+".png")
	camera.queue_free()

func finish() -> void:
	world.queue_free()
	await frames(4)
	quit(0 if failures.is_empty() else 1)
