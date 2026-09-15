@tool
extends RefCounted
## Static exterior surfacing. Stones here are flush aggregate, never solid props.
const SURFACE := preload("res://world/harbor/UrbanGround.gd")
const TREE := preload("res://world/shared/nature/ProceduralStreetTree.gd")

static func surface_polygon(canvas: CanvasItem, points: PackedVector2Array, tint: Color, kind: String) -> void:
	var uv := PackedVector2Array()
	for point in points: uv.append(point/256.0)
	canvas.texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
	canvas.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	canvas.draw_polygon(points,PackedColorArray([tint]),uv,SURFACE.texture(kind))

static func trail(canvas: CanvasItem, points: PackedVector2Array, width: float, tint: Color) -> void:
	for polygon in Geometry2D.offset_polyline(points,width*.5,Geometry2D.JOIN_ROUND,Geometry2D.END_SQUARE):
		surface_polygon(canvas,polygon,tint,"gravel")

static func meadow(canvas: CanvasItem, area: Rect2, seed_value: int, tint := Color("61734e")) -> void:
	SURFACE.paint(canvas, area, tint, "grass")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var marks := PackedVector2Array()
	var colors := PackedColorArray()
	for i in int(area.get_area()/110.0):
		var p := area.position+Vector2(rng.randf_range(5,area.size.x-5),rng.randf_range(6,area.size.y-5))
		marks.append(p)
		marks.append(p+Vector2(rng.randf_range(-2,2),-rng.randf_range(2,5)))
		colors.append(tint.lightened(rng.randf_range(-.15,.2)))
	canvas.draw_multiline_colors(marks,colors,1.2)
	SURFACE.garden_edge(canvas,area,seed_value)

static func aggregate(canvas: CanvasItem, area: Rect2, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var marks := PackedVector2Array()
	var colors := PackedColorArray()
	for i in int(area.get_area()/220.0):
		var p := area.position+Vector2(rng.randf_range(3,area.size.x-4),rng.randf_range(3,area.size.y-4))
		marks.append(p)
		marks.append(p+Vector2(rng.randf_range(1,3),1))
		colors.append(Color("a49b83").darkened(rng.randf_range(0,.3)))
	canvas.draw_multiline_colors(marks,colors,1.4)

static func tree(parent: Node2D, point: Vector2, seed_value: int, scale_value := 1.1) -> void:
	var plant := TREE.new()
	plant.name = "ExteriorTree%d" % seed_value
	plant.position = point
	plant.variant_seed = seed_value
	plant.crown_scale = scale_value
	plant.tree_style = TREE.TreeStyle.BROADLEAF if seed_value%3 else TREE.TreeStyle.COASTAL
	plant.leaf_color = [Color("526a43"),Color("3f624b"),Color("6b7950")][seed_value%3]
	plant.add_to_group("exterior_finish_solid")
	parent.add_child(plant)

static func rock(parent: Node2D, point: Vector2, seed_value: int) -> void:
	var stone := preload("res://world/shared/nature/ProceduralUrbanRock.gd").new()
	stone.name = "ExteriorRock%d" % seed_value
	stone.position = point
	stone.rock_size = Vector2(38,28)
	stone.base_color = Color("898477")
	stone.variant_seed = seed_value
	stone.add_to_group("exterior_finish_rock")
	parent.add_child(stone)

static func industrial(canvas: CanvasItem, area: Rect2, seed_value: int) -> void:
	SURFACE.paint(canvas,area,Color("929487"),"concrete")
	SURFACE.yard(canvas,area,seed_value,true)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in 18:
		var p := area.position+Vector2(rng.randf_range(.08,.85)*area.size.x,rng.randf_range(.08,.85)*area.size.y)
		var patch := Rect2(p,Vector2(rng.randf_range(20,65),rng.randf_range(12,35)))
		SURFACE.paint(canvas,patch,Color("878a7e"),"gravel")
		canvas.draw_polyline(PackedVector2Array([p,p+Vector2(13,8),p+Vector2(19,6),p+Vector2(30,17)]),Color(.23,.24,.20,.25),1,true)
