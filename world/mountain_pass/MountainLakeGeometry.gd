extends Node2D
## Render and collision share one shoreline; the footbridge cuts out a dry deck.
const DECK := Rect2(6880, 14, 440, 52)
var water := PackedVector2Array()
var clock := 0.0

static func smooth_outline(points: PackedVector2Array) -> PackedVector2Array:
	for step in 3:
		var rounded := PackedVector2Array()
		for i in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			rounded.append(a.lerp(b, 0.25))
			rounded.append(a.lerp(b, 0.75))
		points = rounded
	return points

static func rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])

func _ready() -> void:
	water = smooth_outline(PackedVector2Array([Vector2(6850,330),Vector2(7040,300),Vector2(7170,250),Vector2(7370,30),Vector2(7400,-130),Vector2(7270,-270),Vector2(7160,-150),Vector2(7110,-90),Vector2(7090,35),Vector2(6970,130),Vector2(6960,240)]))
	# Small seeded variations keep the bank organic without separating its collider.
	for i in water.size():
		var tangent := water[(i + 1) % water.size()] - water[(i + water.size() - 1) % water.size()]
		water[i] += tangent.orthogonal().normalized() * (sin(float(i) * 0.81) * 2.1 + cos(float(i) * 0.37) * 1.4)
	var shore := Polygon2D.new()
	shore.name = "RoundedShore"
	shore.polygon = Geometry2D.offset_polygon(water, 12.0, Geometry2D.JOIN_ROUND)[0]
	shore.color = Color("665f4c")
	add_child(shore)
	preload("res://world/mountain_pass/MountainGroundMaterials.gd").apply(shore, "earth")
	var surface := Polygon2D.new()
	surface.name = "LakeSurface"
	surface.polygon = water
	surface.color = Color("244a50")
	add_child(surface)
	var material := ShaderMaterial.new()
	material.shader = preload("res://world/mountain_pass/MountainLakeSurface.gdshader")
	surface.material = material
	surface.add_to_group("animated_water_visual")
	preload("res://geodata/nature/WaterPresentation.gd").sound_zone(surface, "lake")
	var current := Line2D.new()
	current.points = PackedVector2Array([Vector2(0,0), Vector2(90,-70)])
	current.width = 4.0
	current.default_color = Color(0.5,0.65,0.62,0.0)
	current.name = "LakeCurrentSound"
	current.position = Vector2(7050, 40)
	add_child(current)
	preload("res://geodata/nature/WaterPresentation.gd").sound_zone(current, "stream")
	var body := StaticBody2D.new()
	body.name = "LakeWaterBoundary"
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("mountain_geodata")
	body.set_meta("geometry_contract", "shoreline_minus_bridge_deck")
	for polygon in Geometry2D.clip_polygons(water, rect_polygon(DECK)):
		var shape := CollisionPolygon2D.new()
		shape.polygon = polygon
		body.add_child(shape)
	add_child(body)

func _physics_process(delta: float) -> void:
	clock += delta
	if clock < 0.25: return
	clock = 0.0
	# Recover old saves and streamed actors already standing in the former fake ground.
	for group in ["player", "vehicle"]:
		for actor in get_tree().get_nodes_in_group(group):
			if not actor is Node2D or not actor.is_visible_in_tree(): continue
			var point := to_local(actor.global_position)
			if DECK.has_point(point) or not Geometry2D.is_point_in_polygon(point, water): continue
			var nearest := Vector2.ZERO
			var distance := INF
			for i in water.size():
				var edge := Geometry2D.get_closest_point_to_segment(point, water[i], water[(i+1)%water.size()])
				if point.distance_squared_to(edge) < distance:
					distance = point.distance_squared_to(edge)
					nearest = edge
			var outward := point.direction_to(nearest)
			actor.global_position = to_global(nearest + outward * (65.0 if group == "vehicle" else 18.0))
			if actor is CharacterBody2D: actor.velocity = Vector2.ZERO
			actor.reset_physics_interpolation()
