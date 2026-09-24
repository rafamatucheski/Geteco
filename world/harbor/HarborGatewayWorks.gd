@tool
extends Node2D

const ACCESS := preload("res://world/harbor/HarborNorthAccess.gd")
const CONNECTOR := preload("res://world/harbor/HarborMountainConnector.gd")
const BOUNDS := ACCESS.BOUNDS
const AXES := ACCESS.AXES
const WORKERS := [Vector2(5828,-5590),Vector2(5885,-5650),Vector2(5990,-5580),Vector2(6050,-5675),Vector2(5835,-5710),Vector2(6025,-5745)]
var works_complete := false # Legacy campaign milestone; the frontier stays under construction.
var _clock := 0.0
var _refresh := 0.0
var _routes: Array[Curve2D] = ACCESS.curves()
var _upper_roads: Array[Dictionary] = CONNECTOR.road_definitions()
var _rails: StaticBody2D
var _upper_bodies: Array[PhysicsBody2D] = []
var _tracked: Dictionary = {}
var _scan := 0.0
var _layer_update := 0.0
var _actors: Array[Node] = []
var _blur: ShaderMaterial
var _cutout: ShaderMaterial
var _deck: Node2D
var _reveal := 0.0
var _camera: Camera2D
var _previous_materials: Dictionary = {}
var _roof: Node2D
var _level_pairs: Array[Array] = []
var _lower_geometry: RefCounted

class TunnelRoof extends Node2D:
	func _draw() -> void:
		# Low overhead tunnel roof; both ends open and lanes continue underneath.
		var roof := ACCESS.TUNNEL
		draw_rect(roof.grow(12),Color("5a635d"))
		draw_rect(roof,Color("7c8374"))
		for x in AXES:
			draw_rect(Rect2(x-47,roof.position.y+18,94,roof.size.y-36),Color("858b7c"))
			for y in range(int(roof.position.y)+25,int(roof.end.y)-20,28):
				draw_line(Vector2(x-42,y),Vector2(x+42,y),Color("697568"),2)
		for x in AXES:
			for y in [roof.position.y,roof.end.y]:
				draw_rect(Rect2(x-49,y-12,98,24),Color(0.02,0.04,0.04,0.8))
				for side in [-1.0,1.0]: draw_rect(Rect2(x+side*58-8,y-18,16,36),Color("c6c5ad"))

class BridgePatch extends Node2D:
	func _draw() -> void:
		# The exact same structural surface as the live connector, including rails.
		CONNECTOR.draw_surface(self)


func _ready() -> void:
	# Lower access surfaces receive their own rail lights, keeping the upper
	# bridge emitters out of this large canvas item's limited light list.
	light_mask = 2
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 1
	z_as_relative = false
	process_physics_priority = -90
	_build_boundaries()
	_build_lower_road_visuals()
	_roof = TunnelRoof.new()
	_roof.name = "TunnelRoof"
	_roof.z_as_relative = false
	_roof.z_index = 14
	add_child(_roof)
	if not Engine.is_editor_hint(): _setup_bridge.call_deferred()
	queue_redraw()

func _build_boundaries() -> void:
	_rails = StaticBody2D.new()
	_rails.name = "AccessRails"
	_rails.collision_layer = 1
	_rails.collision_mask = 0
	add_child(_rails)
	for route in _routes:
		var points := route.get_baked_points()
		for i in range(points.size()-1):
			# Leave the full merging mouth open on the existing avenue.
			var midpoint := (points[i]+points[i+1])*0.5
			if midpoint.y > -4140: continue
			var normal := (points[i+1]-points[i]).normalized().orthogonal()
			for side in [-1.0,1.0]:
				var edge := SegmentShape2D.new()
				edge.a = points[i]+normal*70*side
				edge.b = points[i+1]+normal*70*side
				var collision := CollisionShape2D.new()
				collision.shape = edge
				_rails.add_child(collision)
	for i in AXES.size():
		var barrier := StaticBody2D.new()
		barrier.name = "FrontierGate%d" % i
		barrier.position = Vector2(AXES[i],ACCESS.GATE_Y)
		barrier.collision_layer = 1
		barrier.collision_mask = 0
		var shape := RectangleShape2D.new()
		shape.size = Vector2(152,18)
		var collision := CollisionShape2D.new()
		collision.shape = shape
		barrier.add_child(collision)
		add_child(barrier)

func _setup_bridge() -> void:
	var world := get_parent().get_parent()
	# Replace just the upper deck at the crossing with a texture so blur affects
	# that deck alone. The lower road and actor are never blurred.
	var viewport := SubViewport.new()
	viewport.name = "UpperDeckTexture"
	viewport.size = Vector2i(ACCESS.PATCH.size)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var art := BridgePatch.new()
	art.position = -ACCESS.PATCH.position
	viewport.add_child(art)
	# Reuse the authored road meshes instead of approximating their widths,
	# colors and lane markings. Capture them unlit; the deck receives world lights.
	var network = world.get_node("RoadNetwork")
	for frame in 8:
		if not network.static_canvas.nodes.is_empty(): break
		await get_tree().process_frame
	var unshaded := CanvasItemMaterial.new()
	unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	art.material = unshaded
	for source in network.static_canvas.nodes.values():
		var mesh_bounds: AABB = source.mesh.get_aabb()
		var bounds := Rect2(Vector2(mesh_bounds.position.x, mesh_bounds.position.y), Vector2(mesh_bounds.size.x, mesh_bounds.size.y))
		if not bounds.intersects(ACCESS.PATCH): continue
		var road_piece := MeshInstance2D.new()
		road_piece.mesh = source.mesh
		road_piece.material = unshaded
		art.add_child(road_piece)
	# UPDATE_ONCE may have been consumed while waiting for the road cache.
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var deck := Node2D.new()
	_deck = deck
	deck.visible = false
	deck.name = "UpperDeck"
	deck.position = ACCESS.PATCH.position
	deck.z_as_relative = false
	deck.z_index = 2
	_blur = ShaderMaterial.new()
	_blur.shader = preload("res://world/harbor/NorthBridgeBlur.gdshader")
	add_child(deck)
	# The deck receives both bridge floodlights and lights below the crossing.
	# Local pieces avoid dropping lights at the per-CanvasItem engine limit.
	for y in range(0,int(ACCESS.PATCH.size.y),200):
		for x in range(0,int(ACCESS.PATCH.size.x),200):
			var piece := Sprite2D.new()
			piece.centered = false
			piece.position = Vector2(x,y)
			piece.texture = viewport.get_texture()
			piece.region_enabled = true
			piece.region_rect = Rect2(x,y,minf(200,ACCESS.PATCH.size.x-x),minf(200,ACCESS.PATCH.size.y-y))
			piece.material = _blur
			deck.add_child(piece)
	var cutout := ShaderMaterial.new()
	_cutout = cutout
	cutout.shader = preload("res://world/harbor/NorthBridgeCutout.gdshader")
	var origin := to_global(ACCESS.PATCH.position)
	cutout.set_shader_parameter("patch",Vector4(origin.x,origin.y,ACCESS.PATCH.size.x,ACCESS.PATCH.size.y))
	for surface in [world.get_node("RoadNetwork"),get_parent().get_node("MountainConnector")]:
		_previous_materials[surface] = surface.material
		surface.material = cutout
	# Only upper bridge/avenue rail bodies that actually cross access asphalt.
	await get_tree().physics_frame
	var probe := CircleShape2D.new()
	probe.radius = 78
	for route in _routes:
		for offset in range(0,int(route.get_baked_length()),40):
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = probe
			query.transform = Transform2D(0,to_global(route.sample_baked(offset)))
			query.collision_mask = 1
			for hit in get_world_2d().direct_space_state.intersect_shape(query,64):
				var body := hit.collider as StaticBody2D
				if body == null or is_ancestor_of(body): continue
				var path := String(body.get_path())
				if ("GuardRail" in path or "MountainConnector" in path) and not _upper_bodies.has(body): _upper_bodies.append(body)

func set_works_complete(value: bool) -> void:
	works_complete = value
	# Campaign compatibility only: never remove workers, barriers or unfinished decks.

func get_focus_position() -> Vector2:
	return to_global(Vector2(5940,-5570))

func get_works_contract() -> Dictionary:
	return {"works_complete":works_complete,"connected":false,"destination_available":false,
		"destination":"future_north_region","bounds":BOUNDS,"coordinate_space":"local",
		"deck_rects":[Rect2(5786,-5860,148,350),Rect2(5946,-5860,148,350)],
		"approach_rects":[Rect2(5786,-5510,148,570),Rect2(5946,-5510,148,570)],
		"barrier_rects":[Rect2(5784,-5519,152,18),Rect2(5944,-5519,152,18)],
		"temporary_return_road_id":"RoadLayout/map2_temporary_return",
		"worker_positions":WORKERS.duplicate(),"access_curves":_routes,"underpass_bounds":ACCESS.PATCH,
		"construction_progress":0.0}

func update_actor_layer(actor: PhysicsBody2D) -> bool:
	var point := to_local(actor.global_position)
	var lower_distance := minf(ACCESS.distance_to_route(point,_routes[0]),ACCESS.distance_to_route(point,_routes[1]))
	var lower := bool(actor.get_meta("north_access_lower",_tracked.get(actor,false)))
	if lower_distance > 110: lower = false
	elif not ACCESS.PATCH.grow(90).has_point(point) and lower_distance < 67:
		var upper_distance := INF
		for road in _upper_roads:
			var points: PackedVector2Array = road.points
			for i in range(points.size()-1): upper_distance = minf(upper_distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,points[i],points[i+1])))
		if upper_distance > 100: lower = true
	_tracked[actor] = lower
	actor.set_meta("north_access_lower",lower)
	if lower: actor.remove_collision_exception_with(_rails)
	else: actor.add_collision_exception_with(_rails)
	for body in _upper_bodies:
		if not is_instance_valid(body): continue
		if lower: actor.add_collision_exception_with(body)
		else: actor.remove_collision_exception_with(body)
	return lower

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or get_tree().paused: return
	_scan -= delta
	if _scan <= 0:
		_scan = 0.35
		_actors = get_tree().get_nodes_in_group("vehicle") + get_tree().get_nodes_in_group("player")
		for pedestrian in get_tree().get_nodes_in_group("pedestrian"):
			if not _actors.has(pedestrian): _actors.append(pedestrian)
		for actor in _tracked.keys():
			if not is_instance_valid(actor): _tracked.erase(actor)
	var target: Node2D = null
	var travel := get_node_or_null("/root/RegionTravel")
	if travel: target = travel.controlled_car()
	if target == null: target = get_tree().get_first_node_in_group("player") as Node2D
	var active := is_instance_valid(target) and bool(target.get_meta("north_access_lower", false)) and ACCESS.PATCH.grow(70).has_point(to_local(target.global_position))
	_layer_update -= delta
	if _layer_update <= 0.0:
		# The 400 px approach band gives even the fastest actor ample warning.
		# Rebuilding cross-level collision exceptions at 10Hz avoids walking the
		# entire streamed population during every physics tick.
		_layer_update = 0.1
		active = false
		for actor in _actors:
			if not is_instance_valid(actor) or not actor is PhysicsBody2D: continue
			if not BOUNDS.grow(400).has_point(to_local(actor.global_position)):
				if _tracked.has(actor):
					actor.remove_meta("north_access_lower")
					actor.remove_collision_exception_with(_rails)
					for body in _upper_bodies:
						if is_instance_valid(body): actor.remove_collision_exception_with(body)
					_tracked.erase(actor)
				continue
			var lower := update_actor_layer(actor)
			if actor == target: active = lower and ACCESS.PATCH.grow(70).has_point(to_local(actor.global_position))
		# Own only the exceptions introduced here; preserve boarding/pursuit exceptions.
		for pair in _level_pairs.duplicate():
			if not is_instance_valid(pair[0]) or not is_instance_valid(pair[1]):
				_level_pairs.erase(pair)
			elif not _tracked.has(pair[0]) or not _tracked.has(pair[1]) or bool(_tracked[pair[0]]) == bool(_tracked[pair[1]]):
				pair[0].remove_collision_exception_with(pair[1])
				_level_pairs.erase(pair)
		for actor in _tracked:
			if not is_instance_valid(actor): continue
			for other in _tracked:
				if not is_instance_valid(other) or other == actor: continue
				if bool(_tracked[actor]) != bool(_tracked[other]) and not actor.get_collision_exceptions().has(other):
					actor.add_collision_exception_with(other)
					_level_pairs.append([actor,other])
	var inside_tunnel := is_instance_valid(target) and bool(target.get_meta("north_access_lower",false)) and ACCESS.TUNNEL.grow(20).has_point(to_local(target.global_position))
	_roof.modulate.a = move_toward(_roof.modulate.a,0.18 if inside_tunnel else 1.0,delta*4)
	var camera := get_viewport().get_camera_2d()
	if camera != _camera:
		if is_instance_valid(_camera): _camera.remove_meta("north_underpass_zoom")
		_camera = camera
	if is_instance_valid(_camera):
		if active and target != null and target.is_in_group("vehicle"): _camera.set_meta("north_underpass_zoom",2.25)
		else: _camera.remove_meta("north_underpass_zoom")
	_reveal = move_toward(_reveal,1.0 if active else 0.0,delta*4)
	# Keep the original vector surface while driving on top. Raster substitution
	# is only needed to reveal a vehicle underneath, never for normal lighting.
	if is_instance_valid(_deck):
		var reveal_deck := _reveal > 0.0
		if _deck.visible != reveal_deck:
			_deck.visible = reveal_deck
			_cutout.set_shader_parameter("enabled", reveal_deck)
	if _blur:
		_blur.set_shader_parameter("reveal",_reveal)
		if is_instance_valid(target): _blur.set_shader_parameter("focus",target.global_position)

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	var camera := get_viewport().get_camera_2d()
	if camera == null or camera.get_screen_center_position().distance_to(get_focus_position()) > 2600: return
	_clock += delta
	_refresh += delta
	if _refresh >= 0.1:
		_refresh = fmod(_refresh,0.1)
		queue_redraw()

func _exit_tree() -> void:
	if is_instance_valid(_camera): _camera.remove_meta("north_underpass_zoom")
	for surface in _previous_materials:
		if is_instance_valid(surface): surface.material = _previous_materials[surface]
	for actor in _tracked:
		if not is_instance_valid(actor): continue
		actor.remove_meta("north_access_lower")
		for body in _upper_bodies:
			if is_instance_valid(body): actor.remove_collision_exception_with(body)
	for pair in _level_pairs:
		if is_instance_valid(pair[0]) and is_instance_valid(pair[1]): pair[0].remove_collision_exception_with(pair[1])

func _build_lower_road_visuals() -> void:
	var surfaces := Node2D.new()
	surfaces.name = "LowerRoadSurfaces"
	add_child(surfaces)
	_lower_geometry = preload("res://geodata/roads/StaticCanvasGeometry.gd").new(surfaces)
	_lower_geometry.begin()
	for route in _routes:
		var points := route.get_baked_points()
		_lower_geometry.draw_polyline(points,Color("414f53"),152,true)
		_lower_geometry.draw_polyline(points,Color("92998e"),144,true)
		_lower_geometry.draw_polyline(points,Color("e1dfca"),102,true)
		_lower_geometry.draw_polyline(points,Color("202932"),96,true)
		for distance in range(100,int(route.get_baked_length())-40,170):
			var center := route.sample_baked(distance)
			var forward := (route.sample_baked(distance+5)-route.sample_baked(distance-5)).normalized()
			var side := forward.orthogonal()
			_lower_geometry.draw_line(center-forward*15,center+forward*10,Color("e9e6d3"),3)
			_lower_geometry.draw_colored_polygon(PackedVector2Array([center+forward*20,center+forward*7+side*7,center+forward*7-side*7]),Color("e9e6d3"))
			for sign in [-1.0,1.0]:
				var p: Vector2 = center+side*sign*70
				_lower_geometry.draw_rect(Rect2(p-Vector2(6,6),Vector2(12,12)),Color("adb7af"))
	_finish_lower_road_masks.call_deferred()

func _finish_lower_road_masks() -> void:
	for sector in _lower_geometry.nodes.values(): sector.light_mask = 2

func _draw() -> void:
	# Two continuous construction decks, each aligned with its own bore.
	for x in AXES:
		draw_rect(Rect2(x-74,-5750,148,250),Color("a4a99c"))
		draw_rect(Rect2(x-48,-5750,96,250),Color("252c31"))
		for y in range(-5880,-5750,30):
			draw_line(Vector2(x-70,y),Vector2(x+70,y),Color("b69d71"),5)
			for side in [-1.0,1.0]: draw_line(Vector2(x+side*48,y),Vector2(x+side*48,y+30),Color("687878"),8)
		for y in range(-5740,-5500,40):
			for side in [-1.0,1.0]:
				draw_line(Vector2(x+side*71,y),Vector2(x+side*71,y+32),Color("d4ccb2"),3)
				var p := Vector2(x+side*58,y)
				draw_rect(Rect2(p-Vector2(5,5),Vector2(10,10)),Color("493d32"))
				draw_circle(p,4,Color("e8a44d"))
		_draw_gate(Vector2(x,ACCESS.GATE_Y))
		_draw_equipment(Vector2(x+15,-5680))
	for i in WORKERS.size():
		_draw_worker(WORKERS[i], i, _clock)
	for p in [Vector2(5825,-5545),Vector2(5990,-5545)]:
		draw_rect(Rect2(p,Vector2(24,12)),Color("967c56"))
		for offset in [4,12,20]: draw_line(p+Vector2(offset,0),p+Vector2(offset,12),Color("ccb88e"),2)

func _draw_gate(center: Vector2) -> void:
	draw_rect(Rect2(center-Vector2(65,10),Vector2(130,20)),Color("4b4942"))
	for offset in range(-58,60,16):
		draw_line(center+Vector2(offset,-7),center+Vector2(offset+9,7),Color("e5b44e"),7)
	for side in [-1.0,1.0]:
		draw_circle(center+Vector2(side*62,0),7,Color("2c3437"))
		draw_circle(center+Vector2(side*62,-2),3,Color("e4aa42"))

func _draw_worker(point: Vector2, index: int, time: float) -> void:
	var cycle := time * 2.0 + index * 1.5
	var breath := sin(cycle) * 0.4
	var arm_swing := sin(cycle * 1.2)

	# 1. Soft Ambient Ground Shadow
	draw_circle(point + Vector2(2, 7), 11.0, Color(0.02, 0.03, 0.05, 0.40))
	draw_circle(point + Vector2(1, 6), 8.0, Color(0.01, 0.02, 0.03, 0.32))

	# 2. Heavy Work Boots
	var boot_left := point + Vector2(-5.5, 8.5)
	var boot_right := point + Vector2(5.5, 8.5)
	if index % 2 == 1:
		boot_left += Vector2(-1, -1)
		boot_right += Vector2(1, 1)

	for boot_pos in [boot_left, boot_right]:
		draw_rect(Rect2(boot_pos - Vector2(3, 4), Vector2(6, 8.5)), Color("#131518"))
		draw_rect(Rect2(boot_pos - Vector2(2.5, 3.5), Vector2(5, 7.0)), Color("#26292e"))
		draw_line(boot_pos + Vector2(-2, 2.5), boot_pos + Vector2(2, 2.5), Color("#3d4249"), 1.5)

	# 3. Reinforced Work Pants
	var pants_color := Color("#28343f") if index % 2 == 0 else Color("#31363e")
	draw_line(point + Vector2(-4, 2), boot_left + Vector2(0, -2), pants_color, 5.5)
	draw_line(point + Vector2(4, 2), boot_right + Vector2(0, -2), pants_color, 5.5)
	draw_circle(point + Vector2(-4.5, 4.0), 2.2, pants_color.darkened(0.25))
	draw_circle(point + Vector2(4.5, 4.0), 2.2, pants_color.darkened(0.25))

	# 4. Tool Belt
	draw_line(point + Vector2(-7, 1 + breath), point + Vector2(7, 1 + breath), Color("#38271a"), 3.0)
	draw_rect(Rect2(point + Vector2(-1.5, breath), Vector2(3, 2)), Color("#8c9298"))
	draw_rect(Rect2(point + Vector2(6.5, breath), Vector2(3, 3.5)), Color("#d99824"))

	# 5. Torso & High-Vis Safety Vest
	var vest_color := Color("#ea580c") if index in [0, 2, 4] else (Color("#c0eb1a") if index in [1, 5] else Color("#f1f5f9"))
	var under_shirt := Color("#202832") if index % 2 == 0 else Color("#2a2e36")

	var torso_poly := PackedVector2Array([
		point + Vector2(-9.5, -5 + breath),
		point + Vector2(9.5, -5 + breath),
		point + Vector2(7.0, 1 + breath),
		point + Vector2(-7.0, 1 + breath)
	])
	draw_colored_polygon(torso_poly, under_shirt)

	var vest_poly := PackedVector2Array([
		point + Vector2(-8.0, -4.5 + breath),
		point + Vector2(8.0, -4.5 + breath),
		point + Vector2(6.0, 0.5 + breath),
		point + Vector2(-6.0, 0.5 + breath)
	])
	draw_colored_polygon(vest_poly, vest_color)

	# 3M Retroreflective Stripes
	draw_line(point + Vector2(-4.0, -4.5 + breath), point + Vector2(-3.0, 0.5 + breath), Color("#f8fafc"), 1.8)
	draw_line(point + Vector2(4.0, -4.5 + breath), point + Vector2(3.0, 0.5 + breath), Color("#f8fafc"), 1.8)
	draw_line(point + Vector2(-5.5, -1.0 + breath), point + Vector2(5.5, -1.0 + breath), Color("#f8fafc"), 1.8)
	draw_line(point + Vector2(0, -4.5 + breath), point + Vector2(0, 0.5 + breath), Color("#1e252e"), 1.0)

	# 6. Arms, Sleeves & Work Gloves
	var glove_color := Color("#c6a87d")
	var shoulder_l := point + Vector2(-8.5, -4 + breath)
	var shoulder_r := point + Vector2(8.5, -4 + breath)

	match index:
		0:
			var hand_l := point + Vector2(-7, 2 + breath)
			var hand_r := point + Vector2(5, 5 + breath + arm_swing * 0.5)
			draw_line(shoulder_l, hand_l, under_shirt, 3.5)
			draw_line(shoulder_r, hand_r, under_shirt, 3.5)
			draw_circle(hand_l, 2.2, glove_color)
			draw_circle(hand_r, 2.2, glove_color)
			draw_line(hand_r - Vector2(2, 6), hand_r + Vector2(4, 10), Color("#4b535d"), 2.5)
			draw_rect(Rect2(hand_r + Vector2(2, 4), Vector2(4, 5)), Color("#26292f"))
		1:
			var hand_l := point + Vector2(-4, -1 + breath)
			var hand_r := point + Vector2(6, -1 + breath + arm_swing * 0.3)
			draw_line(shoulder_l, hand_l, under_shirt, 3.2)
			draw_line(shoulder_r, hand_r, under_shirt, 3.2)
			draw_circle(hand_l, 2.0, glove_color)
			draw_circle(hand_r, 2.0, glove_color)
			draw_rect(Rect2(hand_l + Vector2(1, -3), Vector2(7, 4)), Color("#eab308"))
			draw_rect(Rect2(hand_l + Vector2(7, -2), Vector2(2, 2)), Color("#ef4444"))
		2:
			var hand_l := point + Vector2(-5, 3 + breath)
			var hand_r := point + Vector2(4, 1 + breath)
			draw_line(shoulder_l, hand_l, under_shirt, 3.5)
			draw_line(shoulder_r, hand_r, under_shirt, 3.5)
			draw_circle(hand_l, 2.2, glove_color)
			draw_circle(hand_r, 2.2, glove_color)
			draw_line(point + Vector2(1, -5), point + Vector2(9, 12), Color("#a17c52"), 2.0)
			draw_rect(Rect2(point + Vector2(6, 9), Vector2(7, 5)), Color("#475569"))
		3:
			var hand_l := point + Vector2(-3, breath)
			var hand_r := point + Vector2(4, 1 + breath)
			draw_line(shoulder_l, hand_l, under_shirt, 3.2)
			draw_line(shoulder_r, hand_r, under_shirt, 3.2)
			draw_circle(hand_l, 1.8, glove_color)
			draw_circle(hand_r, 1.8, glove_color)
			draw_rect(Rect2(point + Vector2(-5, -2 + breath), Vector2(10, 7)), Color("#334155"))
			draw_rect(Rect2(point + Vector2(-4, -1 + breath), Vector2(8, 5)), Color("#f8fafc"))
			draw_line(point + Vector2(-3, 1 + breath), point + Vector2(2, 1 + breath), Color("#0284c7"), 1.0)
		4:
			var hand_l := point + Vector2(-6, breath)
			var hand_r := point + Vector2(7, -1 + breath + sin(cycle * 1.5) * 1.5)
			draw_line(shoulder_l, hand_l, under_shirt, 3.5)
			draw_line(shoulder_r, hand_r, under_shirt, 3.5)
			draw_circle(hand_l, 2.2, glove_color)
			draw_circle(hand_r, 2.2, glove_color)
			draw_line(hand_r - Vector2(1, 1), hand_r + Vector2(7, -4), Color("#94a3b8"), 2.2)
			draw_circle(hand_r + Vector2(7, -4), 2.2, Color("#64748b"))
		_:
			var hand_l := point + Vector2(-6, -4 + breath)
			var hand_r := point + Vector2(8, 2 + breath + arm_swing * 0.8)
			draw_line(shoulder_l, hand_l, under_shirt, 3.2)
			draw_line(shoulder_r, hand_r, under_shirt, 3.2)
			draw_circle(hand_l, 2.0, glove_color)
			draw_circle(hand_r, 2.0, glove_color)
			draw_rect(Rect2(shoulder_l + Vector2(-2, -3), Vector2(3, 4)), Color("#0f172a"))
			draw_line(shoulder_l + Vector2(-1, -3), shoulder_l + Vector2(-1, -7), Color("#0f172a"), 1.0)

	# 7. Head & Industrial Safety Hard Hat
	var head_pos := point + Vector2(0, -6 + breath * 0.5)
	draw_circle(head_pos + Vector2(0, 2), 3.2, Color("#b88a6d"))
	draw_line(head_pos + Vector2(-2.5, 2.5), head_pos + Vector2(2.5, 2.5), Color("#2e2620"), 1.5)

	var helmet_color := Color("#f8fafc") if index == 3 else (Color("#fbbf24") if index in [0, 1, 4] else Color("#f97316"))
	var helmet_shadow := helmet_color.darkened(0.28)
	var helmet_highlight := helmet_color.lightened(0.35)

	draw_circle(head_pos + Vector2(0, -0.5), 6.5, helmet_shadow)
	draw_circle(head_pos + Vector2(0, -1.0), 6.0, helmet_color)

	var brim_poly := PackedVector2Array([
		head_pos + Vector2(-5.5, -4.0),
		head_pos + Vector2(-2.0, -7.2),
		head_pos + Vector2(2.0, -7.2),
		head_pos + Vector2(5.5, -4.0),
		head_pos + Vector2(0.0, -4.5)
	])
	draw_colored_polygon(brim_poly, helmet_color)
	draw_line(head_pos + Vector2(-2.0, -7.2), head_pos + Vector2(2.0, -7.2), helmet_highlight, 1.5)
	draw_line(head_pos + Vector2(0, 4.0), head_pos + Vector2(0, -6.5), helmet_highlight, 1.8)

	draw_rect(Rect2(head_pos + Vector2(-7.2, -2.5), Vector2(2.2, 4.0)), Color("#1e293b"))
	draw_rect(Rect2(head_pos + Vector2(5.0, -2.5), Vector2(2.2, 4.0)), Color("#1e293b"))

func _draw_equipment(point: Vector2) -> void:
	for side in [-1.0,1.0]:
		draw_rect(Rect2(point+Vector2(side*15-5,-23),Vector2(10,48)),Color("252b2c"))
	draw_rect(Rect2(point-Vector2(14,20),Vector2(28,39)),Color("bb8838"))
	draw_rect(Rect2(point+Vector2(-10,-16),Vector2(20,18)),Color("334a50"))
	draw_line(point,point+Vector2(12,-38),Color("d2a34c"),7)
	draw_line(point+Vector2(12,-38),point+Vector2(35+sin(_clock*.65)*5,-54),Color("d2a34c"),6)
	draw_rect(Rect2(point+Vector2(29+sin(_clock*.65)*5,-61),Vector2(21,13)),Color("665b45"))
