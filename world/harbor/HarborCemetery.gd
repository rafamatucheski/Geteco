class_name HarborCemetery
extends Node2D

## Small cemetery lot south of Bay Medical (the clinic) -- destination for
## the coroner's hearse after a body is picked up. See EmergencyVehicle.gd
## (is_heading_to_cemetery / _deploy_morticians_for_burial) and
## Mortician.gd (is_burial_trip / _place_grave_marker).
##
## Not wired into the road network as a dedicated depot -- the hearse
## routes toward get_open_plot_position() using the same lane-guidance
## every emergency vehicle already uses (_get_road_guidance_target), then
## takes the same short final off-road step onto the lot that depot
## aprons already rely on.

const PATH_TEXTURE = preload("res://world/harbor/cemetery/CemeteryPath.svg")

const LOT_SIZE := Vector2(780.0, 700.0)
const PLOT_ROWS := 3
const PLOT_COLS := 4
const PLOT_SPACING := Vector2(52.0, 62.0)
const PLOT_ORIGIN := Vector2(-78.0, -20.0) # local; leaves room for the decorative front row + gate

var _plots: Array[Vector2] = []
var _next_plot_index := 0
var _graves: Array[Node2D] = []

func _ready() -> void:
	add_to_group("cemetery")
	z_index = 1
	_build_ground()
	_build_wall()
	_build_plot_grid()
	restore_burials()
	_build_gardens()
	var keeper_home := preload("res://world/harbor/cemetery/CemeteryKeeperHome.gd").new()
	keeper_home.position = keeper_home.HOME_LOCAL
	add_child(keeper_home)
	_build_secret()
	var storyteller := preload("res://world/harbor/events/CemeteryStoryteller.gd").new()
	storyteller.position = Vector2(0,-280)
	add_child(storyteller)
	add_child(preload("res://world/harbor/events/CemeteryAtmosphere.gd").new())
	for point in [Vector2(-35,-340),Vector2(35,-340),Vector2(-40,50),Vector2(40,280)]:
		var lamp:=preload("res://StreetLamp.gd").new()
		lamp.position=point
		lamp.light_energy=0.65
		lamp.light_radius=220
		lamp.light_color=Color("d3b487")
		add_child(lamp)

func _build_ground() -> void:
	var half := LOT_SIZE * 0.5
	var ground := Polygon2D.new()
	ground.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y)
	])
	ground.color = Color("#27362f")
	ground.add_to_group("audio_ground")
	ground.set_meta("footstep_surface", "grass")
	add_child(ground)
	var grass := preload("res://world/shared/nature/GrassDetail.gd").new()
	grass.dark = true
	add_child(grass)

	# Central path from the gate down the middle of the lot.
	var path := Polygon2D.new()
	path.polygon = PackedVector2Array([
		Vector2(-14, -half.y), Vector2(14, -half.y),
		Vector2(14, half.y), Vector2(-14, half.y)
	])
	_texture_path(path)
	path.z_index = 1
	path.add_to_group("audio_ground")
	path.set_meta("footstep_surface", "dirt")
	add_child(path)

func _texture_path(polygon: Polygon2D) -> void:
	polygon.color = Color.WHITE
	polygon.texture = PATH_TEXTURE
	polygon.uv = polygon.polygon
	polygon.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	polygon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func _build_wall() -> void:
	var half := LOT_SIZE * 0.5
	var gate_half_width := 26.0
	# Low stone perimeter wall, split on the north side (facing the clinic)
	# for a gate opening. Decorative only -- no collision, matching how
	# most small ambient props in this district are built.
	var segments := [
		[Vector2(-half.x, -half.y), Vector2(-gate_half_width, -half.y)],
		[Vector2(gate_half_width, -half.y), Vector2(half.x, -half.y)],
		[Vector2(half.x, -half.y), Vector2(half.x, half.y)],
		[Vector2(half.x, half.y), Vector2(-half.x, half.y)],
		[Vector2(-half.x, half.y), Vector2(-half.x, -half.y)],
	]
	for seg in segments:
		var wall := Line2D.new()
		wall.points = PackedVector2Array([seg[0], seg[1]])
		wall.width = 10.0
		wall.default_color = Color("#444d49")
		wall.z_index = 2
		add_child(wall)
		var barrier := StaticBody2D.new()
		barrier.position = (seg[0] + seg[1]) * 0.5
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(absf(seg[1].x-seg[0].x)+8, absf(seg[1].y-seg[0].y)+8)
		shape.shape = box
		barrier.add_child(shape)
		add_child(barrier)

	for gate_x in [-gate_half_width, gate_half_width]:
		var post := Polygon2D.new()
		post.polygon = PackedVector2Array([Vector2(-4, -14), Vector2(4, -14), Vector2(4, 6), Vector2(-4, 6)])
		post.position = Vector2(gate_x, -half.y)
		post.color = Color("#4a4840")
		post.z_index = 3
		add_child(post)

func _build_decorative_graves() -> void:
	# Pre-existing headstones so the lot never reads as freshly built/empty
	# -- slab style, deliberately distinct from the wooden crosses
	# Mortician.gd plants for newly buried victims.
	var rows := [
		Vector2(-95, -78), Vector2(-40, -78), Vector2(40, -78), Vector2(95, -78),
		Vector2(-95, -35), Vector2(95, -35),
	]
	for pos in rows:
		var headstone := Polygon2D.new()
		headstone.polygon = PackedVector2Array([
			Vector2(-9, 4), Vector2(-9, -12), Vector2(-5, -16), Vector2(5, -16), Vector2(9, -12), Vector2(9, 4)
		])
		headstone.color = Color("#8b8a82")
		headstone.position = pos
		headstone.z_index = 2
		add_child(headstone)
		var base := Polygon2D.new()
		base.polygon = PackedVector2Array([Vector2(-11, 4), Vector2(11, 4), Vector2(11, 8), Vector2(-11, 8)])
		base.color = Color("#6f6e66")
		base.position = pos
		base.z_index = 2
		add_child(base)

func _build_plot_grid() -> void:
	_plots.clear()
	for row in PLOT_ROWS:
		for col in PLOT_COLS:
			_plots.append(PLOT_ORIGIN + Vector2(col * PLOT_SPACING.x, row * PLOT_SPACING.y))

## Hands out the next reserved burial spot in world coordinates, cycling
## through the grid so there is always a valid destination -- this is a
## visual rotation, not a real capacity simulation.
func get_open_plot_position() -> Vector2:
	if _plots.is_empty():
		return global_position
	var local_pos: Vector2 = _plots[_next_plot_index % _plots.size()]
	_next_plot_index += 1
	return to_global(local_pos)

func register_grave(grave: Node2D, _world_pos: Vector2) -> void:
	_graves.append(grave)

func reserve_plot(identity: String) -> Vector2:
	var records: Dictionary = get_node("/root/CoronerCare").records()
	if not records.has(identity): return Vector2.INF
	var slot := int(records[identity].get("plot", -1))
	if slot >= 0 and slot < _plots.size(): return to_global(_plots[slot])
	var occupied := {}
	for record in records.values():
		if int(record.get("plot", -1)) >= 0: occupied[int(record.plot)] = true
	for i in _plots.size():
		if occupied.has(i): continue
		records[identity].plot = i
		return to_global(_plots[i])
	return Vector2.INF # Full means pending, never overwrite another person's grave.

func restore_burials() -> void:
	var care := get_node_or_null("/root/CoronerCare")
	if care == null: return
	for key in care.records():
		var record: Dictionary = care.records()[key]
		if record.phase != "buried" or int(record.get("plot", -1)) < 0: continue
		if _graves.any(func(grave): return is_instance_valid(grave) and grave.get_meta("burial_identity", "") == key): continue
		var point := reserve_plot(key)
		if point == Vector2.INF: continue
		var marker := preload("res://world/shared/emergency/CoronerGrave.gd").new()
		marker.set_meta("burial_identity", key)
		marker.set_meta("deceased_name", record.name)
		add_child(marker)
		marker.global_position = point
		_graves.append(marker)

## World position of the north gate opening (see _build_wall) -- a short
## walk/drive outside the walled lot, close enough to real road lanes for
## the normal lane-following travel logic to take over cleanly. The hearse
## uses this both to know where to switch into the lot (grave plots sit
## well inside it) and to back out again before returning to base.
func get_gate_position() -> Vector2:
	return to_global(Vector2(0.0, -LOT_SIZE.y * 0.5 - 12.0))

func get_coroner_stop_position() -> Vector2:
	# Leave the entire van outside the wall and the pedestrian gate clear.
	return get_gate_position() - Vector2(0,90)

func _build_gardens() -> void:
	# Six planted rows, two side gardens, open central funeral procession aisle.
	for x in [-290,-210,-130,130,210,290]:
		for y in [-240,-160,-80,20,110,200]:
			# Reserve the northwest cottage and its service path to the main aisle.
			if (x <= -210 and y == -240) or (x < 0 and y == -160): continue
			var grave := preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
			grave.name = "StoneTomb_%s_%s" % [x, y]
			grave.position = Vector2(x, y + 12)
			grave.z_index = 3
			add_child(grave)
			grave.build_view(preload("res://world/harbor/cemetery/CemeteryGrave3D.gd"), 5.8, 20.0, Vector3(0,.6,0), Vector3(0,24,20), Vector2i(256,256))
			grave.model.set_plant_variant(posmod((x * 73 + y * 37) / 10, 997))
			grave.add_solid(Rect2(-1.05,-1.75,2.1,3.5), "TombCollision")

	for x in [-350,350]:
		for y in range(-270,291,140):
			# Leave the cottage frontage and service aisle completely open.
			if x < 0 and y < -100: continue
			var tree := preload("res://world/mountain_pass/MountainPine3D.gd").new()
			tree.position=Vector2(x,y)
			tree.variant_seed = 1
			tree.tree_scale = .85
			tree.add_to_group("cemetery_tree")
			add_child(tree)
	for x in [-210,210]:
		var bench := Line2D.new()
		bench.points=PackedVector2Array([Vector2(x-30,280),Vector2(x+30,280)])
		bench.width=12
		bench.default_color=Color("514d43")
		bench.z_index=3
		add_child(bench)
	var approach := Polygon2D.new()
	approach.polygon=PackedVector2Array([Vector2(-25,-490),Vector2(25,-490),Vector2(25,-350),Vector2(-25,-350)])
	_texture_path(approach)
	add_child(approach)
	var service_path := Polygon2D.new()
	service_path.name = "KeeperHousePath"
	var service_route := PackedVector2Array([Vector2(-235,-178),Vector2(-235,-145),Vector2(0,-145)])
	service_path.polygon = Geometry2D.offset_polyline(service_route, 12.0, Geometry2D.JOIN_MITER, Geometry2D.END_BUTT)[0]
	_texture_path(service_path)
	service_path.z_index = 1
	add_child(service_path)
	# Scuffed ground and a discarded ribbon lead toward the hidden letter.
	for i in 7:
		var mark := Polygon2D.new()
		mark.polygon = PackedVector2Array([Vector2(-2,-4),Vector2(2,-4),Vector2(3,3),Vector2(-2,4)])
		mark.position = Vector2(180+i*18, 268+(4 if i%2 else -4))
		mark.rotation = -0.9
		mark.color = Color("45473e")
		mark.z_index=4
		add_child(mark)
	var ribbon := Line2D.new()
	ribbon.points=PackedVector2Array([Vector2(300,280),Vector2(307,275),Vector2(313,278),Vector2(317,273)])
	ribbon.width=2
	ribbon.default_color=Color("76625c")
	ribbon.z_index=4
	add_child(ribbon)

func _build_secret() -> void:
	var secret := preload("res://Collectible.gd").new()
	secret.collectible_id="harbor_memorial_letter"
	secret.flavor_label="CARTA ANTIGA"
	secret.position=Vector2(310,292)
	add_child(secret)
	if not secret.is_queued_for_deletion():
		secret.gem_poly.polygon=PackedVector2Array([Vector2(-7,-5),Vector2(7,-5),Vector2(7,5),Vector2(-7,5)])
		secret.gem_poly.color=Color("a99c7a")
		secret.glow_circle.color=Color(0.7,0.65,0.45,0.04)
		secret.label.hide()
