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
	_build_gardens()
	_build_secret()
	var storyteller := preload("res://district/harbor_preview/events/CemeteryStoryteller.gd").new()
	storyteller.position = Vector2(0,-280)
	add_child(storyteller)
	add_child(preload("res://district/harbor_preview/events/CemeteryAtmosphere.gd").new())
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
	add_child(ground)
	var grass := preload("res://district/nature/GrassDetail.gd").new()
	grass.dark = true
	add_child(grass)

	# Central path from the gate down the middle of the lot.
	var path := Polygon2D.new()
	path.polygon = PackedVector2Array([
		Vector2(-14, -half.y), Vector2(14, -half.y),
		Vector2(14, half.y), Vector2(-14, half.y)
	])
	path.color = Color("#606660")
	path.z_index = 1
	add_child(path)

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

## World position of the north gate opening (see _build_wall) -- a short
## walk/drive outside the walled lot, close enough to real road lanes for
## the normal lane-following travel logic to take over cleanly. The hearse
## uses this both to know where to switch into the lot (grave plots sit
## well inside it) and to back out again before returning to base.
func get_gate_position() -> Vector2:
	return to_global(Vector2(0.0, -LOT_SIZE.y * 0.5 - 12.0))

func _build_gardens() -> void:
	# Six planted rows, two side gardens, open central funeral procession aisle.
	for x in [-290,-210,-130,130,210,290]:
		for y in [-240,-160,-80,20,110,200]:
			var grave := Node2D.new()
			grave.position = Vector2(x,y)
			grave.z_index = 3
			add_child(grave)
			for part in [[Rect2(-23,-13,46,66),Color("303b32")],[Rect2(-20,-16,40,60),Color("666e69")],[Rect2(-16,-12,32,50),Color("858b7d")],[Rect2(-21,-23,42,13),Color("555a55")],[Rect2(-19,-30,38,15),Color("777e76")],[Rect2(-9,-26,18,2),Color("555a55")]]:
				var p := Polygon2D.new()
				var r: Rect2 = part[0]
				p.polygon = PackedVector2Array([r.position,r.position+Vector2(r.size.x,0),r.end,r.position+Vector2(0,r.size.y)])
				p.color = part[1]
				grave.add_child(p)
			var flowers := Polygon2D.new()
			flowers.polygon = PackedVector2Array([Vector2(-6,23),Vector2(0,17),Vector2(8,24),Vector2(0,30)])
			flowers.color = Color("89816b") if (x+y)%3 else Color("725d66")
			grave.add_child(flowers)
	for x in [-350,350]:
		for y in range(-290,320,100):
			var tree := preload("res://district/nature/ProceduralStreetTree.gd").new()
			tree.position=Vector2(x,y)
			tree.tree_style = tree.TreeStyle.PINE
			tree.leaf_color = Color("263f37")
			tree.trunk_color = Color("433e38")
			tree.variant_seed = int(x+y)
			tree.crown_scale = 1.12
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
	approach.color=Color("606660")
	add_child(approach)
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
